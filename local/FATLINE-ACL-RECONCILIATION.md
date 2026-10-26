# Fatline Redis ACL reconciliation (2026-10-25)

## Source-of-authority comparison

- **Agni** `dash-xd/agni`, `codex/fatline-composition-qualification-config`, `local/fatline/composition.nix`: Redis loads `/etc/redis/users.acl` from a host mount at `%h/.config/fatline/redis/users.acl`. The composition emits no production ACL identities, passwords, key patterns or channel patterns. It defines both Logma and Skymill provider units, but not their Redis credentials. `composition-config.nix` has reserved, unpublished image tags. Therefore the qualification fixture is **not** the production ACL.
- **Ratelimiter** `dash-xd/ratelimiter` README (main): runtime permission sets are profile-specific. In particular `TimerRuntimeACLCommands(profile)` is authoritative for lifecycle Function execution; `BurstRuntimeACLCommands` declares `FCALL`, `TIME`, `HMGET`, `HSET`, `PEXPIRE`. `RedisStore.Bootstrap` performs `FUNCTION LOAD REPLACE` and requires a separate privileged identity. The runtime principal must not receive `FUNCTION`, `CONFIG` or `ACL` authority. Redis Functions run under the caller's ACL.
- **Nix-Alpine** `local/fatline-composition-runtime.sh`: disposable ACL fixture grants Logma broad `+@read +@write +@pubsub` on `~logma:*`, `~active_subscriptions:*`, `~subscription_groups:*` and a qualification channel; it explicitly removes `-function` and uses `+fcall +time`. A distinct subscriber has a qualification-only channel pattern; a bootstrap user is disabled after Function installation. These are **test fixtures**, not least-privilege production policies.
- **Skymill**: independent Redis Streams consumer/producer ACL contract and cross-world restrictions require review on the deployment-selected branch. Not yet verified against a production Redis ACL file.

## Required reconciliation before production approval

1. Obtain the exact deployed Ratelimiter revision and the returned `TimerRuntimeACLCommands` for the selected lifecycle profile; replace broad ACL categories with its command contract plus the actual Logma HTTP/runtime commands.
2. Obtain the deployed Skymill revision and its ACL generator/manifest. Create separate scoped credentials for each Skymill stream/tenant, Logma, and bootstrap. Test both positive operations and cross-scope negative operations on the **same loaded ACL file**.
3. Source the production `users.acl` from a single explicit policy generator or sealed configuration artifact. Agni should consume that artifact; do not silently synthesize ACLs in the runtime harness. Preserve host-side credential delivery and ensure file permissions/rotation are qualified.
4. Add a production-policy qualification gate that starts the real Agni topology with the production ACL artifact and tests denied `FUNCTION FLUSH/LOAD`, `ACL`, `CONFIG`, foreign keys/channels, and permitted `FCALL`/timer/Streams operations.
5. Retest `GATE=all` against the selected production policy, with an immutable policy digest and component revisions recorded in the result. Until then, passing `GATE=all` means **fixture-level integration**, not production multi-tenant isolation.

## Independent crash-window limitation

The durable Logma `.dispatched` marker prevents replays after the marker is written. A crash between Redis `PUBLISH` and marker fsync can still duplicate dispatch. A crash before publication can delay dispatch. Exactly-once external effects require consumer-side idempotency or an acknowledged durable delivery protocol, not only a Redis Pub/Sub subscriber and a local marker.

## Current qualification evidence

The user ran `make qualify-composition COMPOSITION=fatline GATE=all` with exit status 0 on the `codex/fatline-composition-qualification` branch. Baseline, ACL fixture isolation, cold start, timer recovery and lifecycle dispatch all passed. Production policy reconciliation and crash-window delivery guarantees remain open.

## 2026-10-25 implementation: explicit-command test ACL

The previously overlooked Skymill repository is **`xd-dash/skymill`**, not `dash-xd/skymill`. The relevant scoped contract is `provider.go` on `codex/scoped-requirements-qualification` (also inspect `codex/fatline-shared-redis` for integration). Its `ScopedRedisRequirements(scope, stream)` returns `~<stream>` and `~<scope>:skymill:idempotency:<base64url(stream)>:*`, plus `ping hello client select get set eval xadd xread xreadgroup xgroup xpending xclaim xack xinfo`. This is a package-owned scope contract; a generic wildcard like `~skymill:*` would be incorrect. The Skymill main branch is older and lacks this scoped contract.

Ratelimiter `internal/profiledef/profile.go` on main returns `fcall type time zadd hset hexists zrangebyscore hget publish zrem hdel` for the lifecycle profile. It does not grant `FUNCTION` administration. The Logma runtime additionally issues ordinary Redis operations (key reads, writes, etc.) which must be audited separately.

Nix-Alpine now compiles its **disposable qualification-only** Logma ACL through `local/fatline-acl-fixture.sh`: explicit named commands rather than broad `+@read +@write +@pubsub` categories. The harness loads this ACL and runs the existing integration suite. The command union is provisional until all live Logma runtime paths have been exercised. This change must pass the local qualification gate before it can be considered validated.

Next implementation step: an **independent Skymill scoped-principal gate** using the exact `ScopedRedisRequirements` output, a distinct runtime credential, positive `EVAL/XADD/XREADGROUP` flow, and negative tests against Logma keys, adjacent Skymill stream/scope, Redis Function and administration privileges. Do not claim the current five gates test Skymill: the current harness runs only Redis, Nginx and Logma.

The production policy remains external to Agni's host-mounted `users.acl`. Never copy test-generated secrets into production and never identify this fixture as a production policy.
