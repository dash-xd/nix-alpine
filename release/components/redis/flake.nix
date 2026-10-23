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
            name = "fatline-redis-qualify-process";
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
              attempt=0
              while (( attempt < 100 )); do
                attempt=$((attempt + 1))
                if redis-cli --no-auth-warning -s "$work/redis.sock" --user admin -a admin-secret ping 2>/dev/null | grep -qx PONG; then break; fi
                sleep 0.05
              done
              admin() { redis-cli --no-auth-warning -s "$work/redis.sock" --user admin -a admin-secret "$@"; }
              [[ "$(admin PING)" == "PONG" ]] || { echo "Redis readiness timeout" >&2; exit 1; }
              [[ "$(admin CONFIG GET maxmemory | tail -n 1)" == "41943040" ]]
              [[ "$(admin CONFIG GET maxmemory-policy | tail -n 1)" == "noeviction" ]]
              [[ "$(admin CONFIG GET appendonly | tail -n 1)" == "no" ]]
              [[ -z "$(admin CONFIG GET save | tail -n 1)" ]]
              admin ACL LIST | grep -q '^user default off '
              if redis-cli -s "$work/redis.sock" PING 2>/dev/null | grep -qx PONG; then
                echo "Unauthenticated access unexpectedly succeeded" >&2
                exit 1
              fi
              # Only Redis mechanics are proven here. Package-owned ACL profiles
              # must be compiled for the exact FATLINE_SCOPE by the composition
              # qualification, never substituted by fixture-defined grants.
              echo "Redis substrate mechanics passed; scoped ACL and Podman integration unqualified"
            '';
          };
        in {
          qualify-process = { type = "app"; program = "${check}/bin/fatline-redis-qualify-process"; };
          qualify = self.apps.${pkgs.system}.qualify-process;
          # A process-level test cannot substitute for a real Podman/Quadlet
          # integration test of mounts, Unix socket ownership and isolation.
          qualify-service = {
            type = "app";
            program = "${pkgs.writeShellScript "redis-integration-unqualified" ''
              echo "Redis Podman/Quadlet integration gate not yet implemented" >&2
              exit 1
            ''}";
          };
          qualify-integration = self.apps.${pkgs.system}.qualify-service;
        });
    };
}
