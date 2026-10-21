#!/usr/bin/env bash
set -euo pipefail

# This script runs inside the Nix-Alpine container, never on the host.
# Bind Redis to an isolated loopback port, with no persistence.
tmp="$(mktemp -d)"
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# Refuse a shared Redis URL supplied by the caller.
if [[ -n "${SKYMILL_TEST_REDIS_ADDR:-}" || -n "${SKYMILL_TEST_REDIS_URL:-}" ]]; then
  echo "Refusing external Redis test endpoints" >&2
  exit 2
fi

# Probe a bounded series of high ports; Redis must start and answer PING.
ready=0
for attempt in $(seq 1 20); do
  port=$((20000 + RANDOM % 20000))
  redis-server --bind 127.0.0.1 --port "$port" --save "" --appendonly no \
    --maxmemory 40mb --maxmemory-policy noeviction \
    --protected-mode yes --dir "$tmp" >"$tmp/redis.log" 2>&1 &
  pid=$!
  for retry in $(seq 1 30); do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    if redis-cli -h 127.0.0.1 -p "$port" ping 2>/dev/null | grep -qx PONG; then
      ready=1
      break
    fi
    sleep 0.1
  done
  if [[ "$ready" == 1 ]]; then break; fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=""
done

if [[ "$ready" != 1 ]]; then
  cat "$tmp/redis.log" >&2
  echo "Isolated Redis failed to start" >&2
  exit 1
fi

export SKYMILL_TEST_REDIS_ADDR="127.0.0.1:$port"
export SKYMILL_TEST_REDIS_URL="redis://127.0.0.1:$port/0"
export SKYMILL_TEST_REDIS_DESTRUCTIVE=YES
export GOWORK=off CGO_ENABLED=1

echo "Qualifying against isolated 40 MiB Redis on loopback:$port"
go test -race -count=1 -v ./... | tee "$tmp/test.log"
# Explicitly fail if either integration suite was skipped.
if grep -E '^--- SKIP: (TestRedis|TestDeliveryCanBeAckedAfterHTTPServerRestart)' "$tmp/test.log"; then
  echo "Redis integration tests were skipped" >&2
  exit 1
fi
grep -q '^--- PASS: TestRedisConcurrentSubscriptionsCloseAll ' "$tmp/test.log"
grep -q '^--- PASS: TestRedisRequestCancellationClosesSubscription ' "$tmp/test.log"
grep -q '^--- PASS: TestDeliveryCanBeAckedAfterHTTPServerRestart ' "$tmp/test.log"

# Repeat the restart regression against the same isolated Redis to detect intermittent failures.
go test -race -count=20 -run '^TestDeliveryCanBeAckedAfterHTTPServerRestart$' ./httpapi
