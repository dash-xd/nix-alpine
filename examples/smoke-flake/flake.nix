{
  description = "Generic nix-alpine smoke output";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = pkgs.writeText "nix-alpine-smoke" "flake consumer works\n";
      packages.${system}.image = pkgs.dockerTools.buildLayeredImage {
        name = "nix-alpine-smoke";
        tag = "test";
        contents = [ pkgs.hello ];
        config.Cmd = [ "${pkgs.hello}/bin/hello" ];
      };
    };
}
