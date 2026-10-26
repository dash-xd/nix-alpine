# Fatline runtime: event-driven recovery

## Scope

Nginx is an independent shared edge/proxy container. A Fatline instance is one
logical unit managed by a host Quadlet, containing Redis, Logma, Skymill and
a small reconciler under an internal supervisor (s6-overlay is the target).
The Nginx lifecycle is not coupled to Fatline's internal process restarts.

## State authority

* Durable Logma lifecycle records, including absolute deadlines, are authoritative.
* Redis (40 MiB, noeviction, no AOF, no RDB) is volatile derived state.
* Redis Functions and timer indexes must be recreated from versioned function
  definitions and durable lifecycle records, without changing deadlines.
* Redis Streams are **not durable across a Redis crash** under this configuration.
  Skymill must not claim durable crash recovery from Streams alone. Any
  delivery guarantees spanning a Redis crash require an external durable log,
  upstream replay, or a different Redis persistence policy.
* Bootstrap privilege must be narrowly scoped and revoked after reconciliation;
  application principals never gain bootstrap/admin privileges.

## Supervisor contract

The host supervises the Fatline container, not its individual processes.
The internal supervisor starts Redis, then runs an idempotent reconcile
transaction, then starts/admits Logma and Skymill. Nginx stays independent.

Redis exits -> internal supervisor restarts Redis -> on successful readiness,
reconcile Functions and volatile indexes -> re-enable dependent operations.
No timer should be required for the normal recovery path. A low-frequency
fallback watchdog is optional only for missed events and should not become
the primary recovery mechanism.

Logma or Skymill exits -> restart that process only. Redis failure should
make dependent operations unready, not force healthy processes to restart.

## Reconciliation contract

Reconciliation must be safe on repeated invocation and after interrupted
execution. It must use a single-owner lock/fence per Fatline instance.
Only the reconciler holds the bootstrap credential. The bootstrap identity
is disabled after each successful reconcile. Rebuild timer indexes from
absolute deadlines; do not restart timers relative to recovery time.

Reconciliation must be triggered on initial startup, Redis process restart,
or an explicit operator request. The triggering event is not proof of success;
dependent readiness must verify live Redis connectivity and required Functions.

## Readiness and recovery

Liveness: supervisor/process exists. Readiness: required dependency operations
are actually usable. Return 503 for an unready HTTP dependency; never 200
from a cached ready flag after Redis is lost. Preserve the existing fail-closed
behavior for lifecycle writes and avoid reporting success on timeout.

Avoid treating an HTTP 000 timeout as a readiness contract. The separate
Logma readiness endpoint must be implemented and exercised in an integration
test before strict readiness is declared qualified.

## Qualification strategy

Build and boot the real assembled image first. Exercise a small set of
integration invariants against its public interface: normal startup, one
Redis failure, one Logma failure, one Skymill failure, and a full-container
restart. Inject failures only at integration level. Do not encode
implementation-specific restart sequences into production code.

The existing Quadlet qualification profile remains a regression baseline
until the compact image boots and passes integration tests. Do not promote
the compact profile or claim production readiness on the strength of this
design document alone.

## Explicit unresolved dependencies

* The existing Logma and Skymill OCI outputs need to be assembled into one
  pinned Nix image with s6-overlay; simply nesting OCI images is insufficient.
* Nginx's Redis Unix-socket access must be preserved through a shared,
  permission-scoped mount, or replaced with an explicitly authenticated
  transport contract.
* Skymill's Redis Streams crash durability must be resolved before claiming
  end-to-end durable delivery across Redis crashes.
* Implement Logma's explicit readiness endpoint and a real process-exit
  event hook for Redis reconciliation.
