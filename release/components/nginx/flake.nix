{
  description = "Nix-Alpine Fatline Nginx process qualification";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = eachSystem (pkgs: {
        image = pkgs.dockerTools.buildLayeredImage {
          name = "localhost/fatline-nginx";
          tag = "candidate";
          contents = [ pkgs.nginx ];
          config = {
            Entrypoint = [ "${pkgs.nginx}/bin/nginx" ];
            Cmd = [ "-g" "daemon off;" "-c" "/etc/nginx/nginx.conf" ];
          };
        };
        default = self.packages.${pkgs.system}.image;
      });
      apps = eachSystem (pkgs:
        let
          check = pkgs.writeShellApplication {
            name = "fatline-nginx-qualify-process";
            runtimeInputs = [ pkgs.nginx pkgs.coreutils pkgs.gnugrep ];
            text = ''
              set -euo pipefail
              work="$(mktemp -d)"
              trap 'rm -rf "$work"' EXIT
              cat > "$work/nginx.conf" <<EOF
              pid $work/nginx.pid;
              error_log /dev/stderr warn;
              events { worker_connections 128; }
              http {
                access_log off;
                server {
                  listen 127.0.0.1:18080;
                  location /health { return 200 "ok"; }
                }
              }
              EOF
              nginx -t -c "$work/nginx.conf"
              nginx -v
              echo "Nginx configuration parse gate passed; Quadlet lifecycle is separate"
            '';
          };
        in {
          qualify-process = { type = "app"; program = "${check}/bin/fatline-nginx-qualify-process"; };
          qualify = self.apps.${pkgs.system}.qualify-process;
        });
    };
}
