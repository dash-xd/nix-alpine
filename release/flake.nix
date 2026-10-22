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
        in {
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
          touch $out
        '';
      });
    };
}
