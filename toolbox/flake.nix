{
  description = "Nix-Alpine reusable, pinned development toolchains";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          astroInputs = pkgs.writeShellApplication {
            name = "nix-alpine-astrochicken-inputs";
            runtimeInputs = with pkgs; [ bash coreutils findutils gawk git gzip gnugrep ];
            text = ''
              exec ${pkgs.bash}/bin/bash ${./apps/astrochicken-inputs.sh} "$@"
            '';
          };
          coreosBuild = pkgs.writeShellApplication {
            name = "nix-alpine-coreos-qemu-build";
            runtimeInputs = with pkgs; [ bash coreutils findutils git gawk gnugrep nix ];
            text = builtins.readFile ./apps/coreos-qemu-build.sh;
          };
          checkAclPins = pkgs.writeShellApplication {
            name = "nix-alpine-check-fatline-acl-pins";
            runtimeInputs = [ pkgs.python3 ];
            text = ''
              exec ${pkgs.python3}/bin/python3 ${./apps/check-fatline-acl-pins.py} "$@"
            '';
          };
        in {
          astrochicken-inputs = {
            type = "app";
            program = "${astroInputs}/bin/nix-alpine-astrochicken-inputs";
          };
          coreos-qemu-build = {
            type = "app";
            program = "${coreosBuild}/bin/nix-alpine-coreos-qemu-build";
          };
          check-fatline-acl-pins = {
            type = "app";
            program = "${checkAclPins}/bin/nix-alpine-check-fatline-acl-pins";
          };
        });
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          base = with pkgs; [ git cacert ];
          goTools = with pkgs; [ go_1_26 ];
        in {
          default = pkgs.mkShell { packages = base; };
          go = pkgs.mkShell { packages = base ++ goTools; };
          integration = pkgs.mkShell {
            packages = base ++ goTools ++ (with pkgs; [ redis ]);
          };
        });
    };
}
