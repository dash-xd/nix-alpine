# Nix-Alpine artifact versioning idioms

This is the canonical versioning contract for software artifacts **built and imported by Nix-Alpine**. It applies across components and compositions, not just Fatline or Agni.

## Boundaries

A version is a human-readable release identity. A tag is a name-to-artifact mapping. An artifact digest identifies exact bytes. Qualification evidence describes what was tested; **external workflow authority** decides what may be published or deployed. Smoke must not infer authorization merely from a tag or its own runtime identity.

Smoke's existing composition and workspace digests remain observational identities, not release versions or authorization. Nix-Alpine's Makefile orchestrates the build and qualification gates; it does not gain authority merely by assigning a tag.

## Canonical CalVer

Use UTC `YYYY.0M.0D[.MICRO]` for published release versions. The optional MICRO is a nonnegative decimal integer without leading zeros, for multiple releases on the same UTC day. Example: `2026.10.21`, `2026.10.21.1`, `2026.10.21.2`. Release versions must be unique within a named artifact stream. A later date is not a compatibility guarantee.

## Names and lifecycle

An adapter maps these logical labels into its backend (OCI tags, Git tags, artifact metadata, etc.):

- `<version>`: immutable release identity.
- `candidate-<version>`: immutable candidate identity, bound to a specific artifact.
- `qualified-<version>`: immutable evidence-backed qualification marker. The marker itself is not authority.
- `candidate`: optional mutable convenience alias for local iteration, never deployable.
- `qualified`: optional mutable discovery channel, not a deployment pin.
- Additional channels, e.g. `stable` or `testing`, must be explicitly defined and are mutable pointers only.

Never reuse or rebind an immutable versioned name. A failed, superseded or revoked version remains reserved and auditable. A qualification record may be revoked without mutating historical artifact identity.

## Promotion and deployment

1. Select exact source inputs and produce an artifact; record content identity and provenance.
2. Allocate an unused candidate version; reject conflicting mappings.
3. Run appropriate tests and record evidence, policy revision and immutable artifact digest.
4. The **Nix-Alpine Makefile qualification workflow** decides whether its specified gates succeeded. No separate Huram authority is assumed. A future external authority may be integrated explicitly.
5. Publish versioned references without overwriting existing mappings. Promotion of mutable channels must use compare-and-swap or an equivalent serialized guarded update.
6. For a multi-artifact composition, publish an independent immutable manifest listing exact member identities, configuration and policy digests. Qualify the composition separately.
7. Resolve aliases to exact artifacts before deployment. Verify qualification and authority; pin the deployed artifact digest and composition identity so restart does not silently follow a moving channel.
8. Roll back by selecting an earlier authorized immutable composition, never by rewriting versioned references.

Publishing multiple tags is not an atomic deployment transaction. An adapter must provide explicit rollback/recovery semantics for partial publication.

## Adapter ownership

Nix-Alpine owns release naming, Makefile qualification orchestration, and eventual publication adapters. Smoke may supply optional reusable validation primitives but is not the authority or owner of this policy. Podman-specific publication remains an optional adapter; versioning does not require an OCI registry.

**Infra consumers**, including Agni/Fatline, supply artifact namespaces and release manifests, and own their runtime configurations. They reference this policy rather than copying it.

## Current implementation status

Nix-Alpine currently has Makefile build and qualification targets, but no qualified release publication, durable tag CAS, revocation enforcement, or deployment activation. Smoke's experimental versioning package on a working branch is not integrated into this Makefile. Qualification evidence must be recorded and verified before any publication target is added.
