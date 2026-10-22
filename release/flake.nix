{
  description = "Nix-Alpine release metadata and validation tools (container-side only)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      apps = eachSystem (pkgs:
        let
          release = pkgs.writeShellApplication {
            name = "nix-alpine-release-metadata";
            runtimeInputs = with pkgs; [ coreutils git jq nix ];
            text = builtins.readFile ./release-metadata.sh;
          };
          compose = pkgs.writeShellApplication {
            name = "nix-alpine-compose";
            runtimeInputs = with pkgs; [ bash coreutils findutils git gnugrep jq nix ];
            text = builtins.readFile ./compose.sh;
          };
        in {
          compose = { type = "app"; program = "${compose}/bin/nix-alpine-compose"; };
          release-metadata = {
            type = "app";
            program = "${release}/bin/nix-alpine-release-metadata";
          };
        });
      checks = eachSystem (pkgs: {
        metadata-syntax = pkgs.runCommand "release-metadata-syntax" {
          nativeBuildInputs = [ pkgs.bash ];
        } ''
          bash -n ${./release-metadata.sh}
          bash -n ${./compose.sh}
          touch $out
        '';
      });
    };
}
