{
  description = "Nix-Alpine systemd service qualification";

  outputs = { self }: {
    apps.x86_64-linux.default = {
      type = "app";
      program = "${self}/run";
    };
  };
}
