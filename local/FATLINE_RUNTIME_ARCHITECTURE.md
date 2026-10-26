# Fatline runtime: independently upgradeable, convergent services

## Architecture decision

Retain separate OCI images and systemd/Quadlet units for Redis, Logma and
Skymill. Keep Nginx as a separate shared service with its own lifecycle.
Do not use s6-overlay or assemble a monolithic Fatline OCI image.

Agni defines the desired state (pinned image digests, versions, ACL policy,
runtime configuration, mounts and dependency contracts). A deployment
controller applies the desired state to the host through Quadlets. systemd
owns process supervision. Application-specific reconciliation owns the
reconstruction of derived state. None of these layers should impersonate
another layer's responsibility.

## Unit model

* `fatline-<scope>.target`: lifecycle grouping and operator entry point,
  not a cascade of hard `Requires=` edges.
* `fatline-<scope>-redis.container`: 40 MiB RAM-only Redis, `noeviction`,
  no RDB/AOF. Restart on failure.
* `fatline-<scope>-logma.container`: independently replaceable Logma.
* `fatline-<scope>-skymill.container`: independently replaceable Skymill.
* `fatline-<scope>-reconcile.service`: idempotent, bounded, single-owner
  reconciliation of Redis Functions and timer indexes.
* `fatline-<scope>-nginx.container`: **not part of the target**. Nginx is a
  separate shared proxy; preserve the Redis socket/transport contract.

Avoid `PartOf=` or `BindsTo=` relationships that propagate an individual
container's restart to other application containers. `Wants=`/`After=`
may express startup ordering, but are not readiness guarantees.

## Triggers, not polling as the primary mechanism

The deployment controller invokes reconciliation on initial activation and
when the desired Redis Function/policy version changes. The Redis unit
triggers reconciliation after a successful restart using a bounded
`ExecStartPost=` hook or an equivalent explicit unit-level event. The hook
must be asynchronous to application readiness and must not create a
systemd ordering cycle. It must not block Redis's own startup indefinitely.

A dependency disconnect causes Logma/Skymill to fail closed on affected
operations and retry with bounded backoff. They do not require a process
restart. A missed event can be repaired by an operator-triggered reconcile
or an optional slow watchdog; periodic timer polling is not the primary
recovery path.

A reconciliation event is only a request to converge. A successful
reconciliation requires live Redis connectivity, expected Function version,
reconstructed timer indexes and revocation of elevated bootstrap access.

## Idempotency and authority

* Logma durable lifecycle records, including absolute deadlines, are the
  source of truth. Recreate Redis timer indexes without changing deadlines.
* Use a single-writer lock/fence for reconciliation per scope; reject stale
  writers. Make partial retries safe and record last applied generation.
* Only the reconciler can access bootstrap privileges. The Logma and Skymill
  principals cannot mutate ACLs or load Functions.
* A bootstrap identity disabled in volatile Redis is not sufficient to
  prevent reuse after a restart. The credential must remain inaccessible to
  application containers and the reconciler must revoke it after use.
* Skymill Redis Streams are **not crash-durable** with RAM-only Redis.
  Cross-crash delivery guarantees require a durable upstream replay source,
  durable broker, or a change to the Redis persistence contract.

## Upgrades and rollbacks

Reconcile the desired manifest by comparing immutable image digests and
configuration generations. Replace **only changed units**. Upgrading Logma
must not restart Redis or Skymill; upgrading Skymill must not restart Logma.
Redis replacement triggers derived-state reconciliation.

An upgrade is successful only after the replaced component reports readiness
and its dependency contracts are satisfied. On failure, retain the previous
known-good manifest and roll back the changed unit where safe. Schema and
Function migrations require explicit compatibility windows; do not blindly
roll back irreversible state changes.

Avoid mutable candidate tags as deployment identity. Record resolved OCI
digests and Nix source revisions in a deployment ledger.

## Health semantics

Liveness means the process can be supervised. Readiness means the service can
perform required dependency operations **now**. Logma should expose a
readiness endpoint returning 200 when usable and 503 when unavailable;
a cached process-up state is insufficient. Redis outages must not produce
successful lifecycle mutations. HTTP 000 is not a readiness contract.

## Integration-level qualification

Qualify the assembled **deployment** instead of adding special recovery
branches to the qualification harness:

1. Activate a pinned manifest and verify real end-to-end operations.
2. Upgrade Logma only, then Skymill only; verify unaffected unit identities.
3. Terminate Redis once; verify fail-closed operations and automatic
   event-triggered reconciliation without replacing Logma or Skymill.
4. Restart the deployment/host and verify convergence from durable state.
5. Validate version rollback, ACL boundaries and observability.

Failure injection belongs in integration tests, never in production startup
or reconciliation scripts. Production recovery runs on real events and may
also be explicitly invoked by an operator.

## Migration from the existing qualification harness

The current disposable Quadlet topology and its eight gates remain a
regression baseline, not a production deployment controller. The existing
timer-based Function reconciliation is evidence of behavior, not the
final triggering design.

Next implementation dependencies are a persistent Agni manifest/reconciler,
an event-triggered Redis recovery hook, independent component update logic,
and Logma's explicit readiness contract. Do not claim these are implemented
until the actual Quadlet units and runtime controller are exercised.
