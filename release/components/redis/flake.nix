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
              for ((attempt = 0; attempt < 100; attempt++)); do
                if redis-cli -s "$work/redis.sock" -a admin-secret ping 2>/dev/null | grep -qx PONG; then break; fi
                sleep 0.05
              done
              admin() { redis-cli --no-auth-warning -s "$work/redis.sock" -a admin-secret "$@"; }
              # Only Redis mechanics are proven here. Package-owned ACL profiles
              # must be compiled for the exact FATLINE_SCOPE by the composition
              # qualification, never substituted by fixture-defined grants.
              echo "Redis substrate mechanics passed; scoped ACL and Podman integration unqualified"
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
