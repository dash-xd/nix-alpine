{
  redis = { memoryMiB = 40; };
  # Canonical CalVer references (YYYY.0M.0D[.MICRO], UTC). Published tags are immutable.
  # These initial date tags are RESERVED, not qualified or published yet.
  # Smoke must verify and publish the exact image IDs before activation.
  images = {
    redis = "localhost/nix-alpine/redis:qualified-2026.10.21";
    nginx = "localhost/nix-alpine/nginx:qualified-2026.10.21";
    logma = "localhost/nix-alpine/logma:qualified-2026.10.21";
    skymill = "localhost/nix-alpine/skymill:qualified-2026.10.21";
  };
}
