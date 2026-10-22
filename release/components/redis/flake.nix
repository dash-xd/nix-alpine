{
  description = "Standalone Fatline Redis image and behavioral qualification";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = eachSystem (pkgs: {
        image = pkgs.dockerTools.buildLayeredImage {
          name = "localhost/fatline-redis";
          tag = "candidate";
          contents = [ pkgs.redis ];
          config = {
            Entrypoint = [ "${pkgs.redis}/bin/redis-server" ];
            Cmd = [ "/etc/redis/redis.conf" ];
          };
        };
        default = self.packages.${pkgs.system}.image;
      });
      apps = eachSystem (pkgs:
        let
          check = pkgs.writeShellApplication {
            name = "fatline-redis-qualify";
            runtimeInputs = [ pkgs.redis pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
            text = ''
              set -euo pipefail
              work="$(mktemp -d)"
              trap 'redis-cli -s "$work/redis.sock" -a admin-secret shutdown nosave >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
              cat > "$work/users.acl" <<'ACL'
              user default off
              user admin on >admin-secret ~* &* +@all
              user skymill on >skymill-secret ~skymill:* &skymill:* +ping +xadd +xread +xgroup +xack
              ACL
              cat > "$work/redis.conf" <<EOF
              port 0
              protected-mode yes
              save ""
              appendonly no
              unixsocket $work/redis.sock
              unixsocketperm 700
              maxmemory 40mb
              maxmemory-policy noeviction
              aclfile $work/users.acl
              EOF
              redis-server "$work/redis.conf" --daemonize yes --pidfile "$work/redis.pid"
              for i in $(seq 1 100); do
                if redis-cli -s "$work/redis.sock" -a admin-secret ping 2>/dev/null | grep -qx PONG; then break; fi
                sleep 0.05
              done
              admin() { redis-cli --no-auth-warning -s "$work/redis.sock" -a admin-secret "$@"; }
              scoped() { redis-cli --no-auth-warning -s "$work/redis.sock" --user skymill -a skymill-secret "$@"; }
              test "$(admin config get maxmemory | tail -1)" = 41943040
              test "$(admin config get maxmemory-policy | tail -1)" = noeviction
              test "$(admin config get port | tail -1)" = 0
              test "$(admin config get appendonly | tail -1)" = no
              test "$(admin config get save | tail -1)" = ""
              test "$(scoped ping)" = PONG
              test "$(scoped xadd skymill:events '*' event qualified)" != ""
              test "$(scoped xadd other:events '*' event forbidden)" = "NOPERM No permissions to access a key"
              test "$(scoped config get maxmemory)" = "NOPERM this user has no permissions to run the 'config|get' command"
              echo "Redis behavioral qualification passed (isolated process, not Podman integration)"
            '';
          };
        in {
          qualify = { type = "app"; program = "${check}/bin/fatline-redis-qualify"; };
          # A process-level test cannot substitute for a real Podman/Quadlet
          # integration test of mounts, Unix socket ownership and isolation.
          qualify-integration = {
            type = "app";
            program = "${pkgs.writeShellScript "redis-integration-unqualified" ''
              echo "Redis Podman/Quadlet integration gate not yet implemented" >&2
              exit 1
            ''}";
          };
        });
    };
}
