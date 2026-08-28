# Shared Nix binary cache

The `volume-cache` composite now supports two cache tiers:

```text
Blacksmith/GitHub Actions cache
    = per-repository hot /nix volume reuse

shared S3-compatible Nix binary cache
    = cross-repository immutable store-path reuse
```

For Google Cloud Storage, use the Cloud Storage XML/S3 interoperability API:

```text
endpoint = storage.googleapis.com
region   = auto
```

The shared cache remains a normal signed Nix binary cache. Object-store HMAC
credentials only authorize transport; Nix's public/private cache key pair
authenticates the store objects themselves.

Recommended organization-level configuration shared by every participating
repository:

```text
Repository/organization variable:
  NIX_SHARED_CACHE_BUCKET
  NIX_SHARED_CACHE_PUBLIC_KEY

Repository/organization secrets:
  NIX_SHARED_CACHE_ACCESS_KEY_ID
  NIX_SHARED_CACHE_SECRET_ACCESS_KEY
  NIX_SHARED_CACHE_PRIVATE_KEY
```

The private signing key is only required on builders that publish. Read-only
consumers need the bucket, HMAC credentials and public signing key.

Example:

```yaml
- uses: dash-xd/nix-alpine/volume-cache@<sha>
  with:
    image-name: nix-alpine:builder
    cache-key: my-app-${{ hashFiles('flake.nix', 'flake.lock') }}
    cache-restore-prefix: my-app-
    store-volume: my-app-nix-store
    user-cache-volume: my-app-nix-user-cache

    shared-cache-bucket: ${{ vars.NIX_SHARED_CACHE_BUCKET }}
    shared-cache-endpoint: storage.googleapis.com
    shared-cache-region: auto
    shared-cache-access-key-id: ${{ secrets.NIX_SHARED_CACHE_ACCESS_KEY_ID }}
    shared-cache-secret-access-key: ${{ secrets.NIX_SHARED_CACHE_SECRET_ACCESS_KEY }}
    shared-cache-public-key: ${{ vars.NIX_SHARED_CACHE_PUBLIC_KEY }}
    shared-cache-private-key: ${{ secrets.NIX_SHARED_CACHE_PRIVATE_KEY }}

    command: |
      nix build .#default -L
```

When `shared-cache-bucket` is empty, the action behaves exactly like the
per-repository volume-cache action did before.

Generate the Nix signing key pair once and share it deliberately across the
repositories that trust this cache:

```sh
nix-store --generate-binary-cache-key \
  xd-dash-shared-1 \
  nix-cache-private.key \
  nix-cache-public.key
```

The private key is security-sensitive: possession lets a party sign arbitrary
store paths that participating builders will trust.


## Cross-repository artifact relay

The named-volume cache can also be exported as a normal GitHub Actions
artifact. This is intentionally separate from the signed Nix binary cache.

Set:

```yaml
artifact-name: nix-volume-cache-my-app
artifact-retention-days: "30"
```

The artifact contains:

```text
nix-store.tar.gz
nix-user-cache.tar.gz
manifest.json
```

The manifest records:

```json
{
  "schema": 1,
  "artifact_name": "nix-volume-cache-my-app",
  "source_repo": "owner/repo",
  "source_sha": "...",
  "source_run_id": "...",
  "cache_key": "...",
  "cache_restore_prefix": "..."
}
```

A consumer in another repository may use a user/App token with Actions read
access to download the artifact through the GitHub API, validate the manifest,
and then run `actions/cache/save`. Because the save occurs in the consumer
workflow, the resulting cache belongs to the consumer repository.

This yields lazy eventual convergence:

```text
repo A /nix cache
      |
      v
Actions artifact
      |
 GitHub API
      |
      v
repo B workflow
      |
      v
repo B Actions cache
      |
      v
repo B named /nix volume
```

Artifacts are transport snapshots, not authoritative state. The Nix store's
content-addressing still determines object identity.
