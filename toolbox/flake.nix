{
  description = "Nix-Alpine reusable, pinned development toolchains";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
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
