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
          coreosBuild = pkgs.writeShellApplication {
            name = "nix-alpine-coreos-qemu-build";
            runtimeInputs = with pkgs; [ bash coreutils findutils git gawk gnugrep nix ];
            text = builtins.readFile ./apps/coreos-qemu-build.sh;
          };
        in {
          coreos-qemu-build = {
            type = "app";
            program = "${coreosBuild}/bin/nix-alpine-coreos-qemu-build";
          };
        });
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          base = with pkgs; [ git cacert ];
          goTools = with pkgs; [ go_1_26 ];
          qualificationTools = with pkgs; [
            bash coreutils curl findutils gawk gnugrep gnused gnumake git
            podman python3 systemd
          ];
        in {
          default = pkgs.mkShell { packages = base; };
          go = pkgs.mkShell { packages = base ++ goTools; };
          security = pkgs.mkShell { packages = base ++ goTools ++ (with pkgs; [ age sops gh ]); };
          integration = pkgs.mkShell {
            packages = base ++ goTools ++ (with pkgs; [ redis ]);
          };
          qualification = pkgs.mkShell {
            packages = base ++ qualificationTools;
          };
        });
    };
}
