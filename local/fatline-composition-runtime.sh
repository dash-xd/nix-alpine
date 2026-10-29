#!/usr/bin/env bash
# Disposable runtime composition. Never installs units or promotes release tags.
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: $0 BUILDER REDIS_IMAGE NGINX_IMAGE LOGMA_IMAGE" >&2; exit 2; }
builder=$1 redis_image=$2 nginx_image=$3 logma_image=$4
scope="fatline-composition-$$"
work=$(mktemp -d)
net="$scope"
socket="$work/socket"
redis="$scope-redis"
nginx="$scope-nginx"
logma="$scope-logma"
skymill_provider="$scope-skymill-provider"
bootstrap="$scope-bootstrap"
quadlet_mode=${COMPOSITION_QUADLET_MODE:-0}
redis_quadlet_mode=${COMPOSITION_REDIS_QUADLET_MODE:-0}
nginx_quadlet_mode=${COMPOSITION_NGINX_QUADLET_MODE:-0}
cold_start_mode=${COMPOSITION_COLD_START_MODE:-0}
bootstrap_unit_mode=${COMPOSITION_BOOTSTRAP_UNIT_MODE:-0}
agni_reconcile_mode=${COMPOSITION_AGNI_RECONCILE_MODE:-0}
bootstrap_unit="$scope-bootstrap.service"
bootstrap_unit_file="$HOME/.config/systemd/user/$bootstrap_unit"
nginx_quadlet_file="$HOME/.config/containers/systemd/$scope-nginx.container"
nginx_quadlet_service="$scope-nginx.service"
redis_quadlet_file="$HOME/.config/containers/systemd/$scope-redis.container"
redis_quadlet_service="$scope-redis.service"
quadlet_dir="$HOME/.config/containers/systemd"
quadlet_file="$quadlet_dir/$scope-logma.container"
quadlet_service="$scope-logma.service"
cleanup() {
  local original_status=$?
  local cleanup_failed=0
  if [[ "${COMPOSITION_FUNCTION_RECONCILE_MODE:-0}" == 1 ]]; then
    systemctl --user stop "$scope-reconcile.timer" "$scope-reconcile.service" >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/$scope-reconcile.timer" "$HOME/.config/systemd/user/$scope-reconcile.service"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  if [[ "$bootstrap_unit_mode" == 1 ]]; then
    systemctl --user stop "$bootstrap_unit" >/dev/null 2>&1 || true
    rm -f "$bootstrap_unit_file"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  if [[ "$nginx_quadlet_mode" == 1 ]]; then
    systemctl --user stop "$nginx_quadlet_service" >/dev/null 2>&1 || true
    rm -f "$nginx_quadlet_file"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  if [[ "$redis_quadlet_mode" == 1 ]]; then
    systemctl --user stop "$redis_quadlet_service" >/dev/null 2>&1 || true
    rm -f "$redis_quadlet_file"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  if [[ "$quadlet_mode" == 1 ]]; then
    systemctl --user stop "$quadlet_service" >/dev/null 2>&1 || true
    rm -f "$quadlet_file"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  # Ephemeral --rm CLI containers using --network container:$nginx can
  # remain as Podman dependencies even after exiting. --depend removes those
  # children before their scoped network namespace provider.
  local owned
  for owned in "$skymill_provider" "$logma" "$bootstrap" "$nginx" "$redis"; do
    if podman container exists "$owned"; then
      if ! podman rm -f --depend "$owned" >/dev/null; then
        echo "FAIL: could not remove qualification container $owned" >&2
        cleanup_failed=1
      fi
    fi
  done
  # A missing or failed removal must not be mistaken for a clean test run.
  for owned in "$skymill_provider" "$logma" "$bootstrap" "$nginx" "$redis"; do
    if podman container exists "$owned"; then
      echo "FAIL: qualification container remains: $owned" >&2
      cleanup_failed=1
    fi
  done
  if ! podman network rm "$net" >/dev/null 2>&1; then
    if podman network exists "$net"; then
      echo "FAIL: qualification network remains: $net" >&2
      cleanup_failed=1
    fi
  fi
  if (( cleanup_failed )); then
    echo "FAIL: preserving qualification workspace for diagnosis: $work" >&2
  else
    rm -rf "$work"
  fi
  if (( cleanup_failed )); then
    echo "FAIL: Fatline qualification teardown incomplete" >&2
    return 1
  fi
  return "$original_status"
}
diagnose_failure() {
  local code=$?
  echo "FAIL: Quadlet composition at line $1 (exit $code)" >&2
  if [[ "${bootstrap_unit_mode}" == 1 ]]; then
    systemctl --user --no-pager -l status "$bootstrap_unit" >&2 || true
    journalctl --user -u "$bootstrap_unit" -n 70 --no-pager -l >&2 || true
  fi
  if [[ "${nginx_quadlet_mode}" == 1 ]]; then
    systemctl --user --no-pager status "$nginx_quadlet_service" >&2 || true
    journalctl --user -u "$nginx_quadlet_service" -n 35 --no-pager >&2 || true
  fi
  if [[ "${redis_quadlet_mode}" == 1 ]]; then
    systemctl --user --no-pager status "$redis_quadlet_service" >&2 || true
    journalctl --user -u "$redis_quadlet_service" -n 35 --no-pager >&2 || true
  fi
  if [[ "${quadlet_mode}" == 1 ]]; then
    systemctl --user --no-pager status "$quadlet_service" >&2 || true
    journalctl --user -u "$quadlet_service" -n 35 --no-pager >&2 || true
    podman ps -a --filter "name=$logma" >&2 || true
  fi
  exit "$code"
}
trap 'diagnose_failure "$LINENO"' ERR
trap cleanup EXIT
mkdir -m 777 "$socket"
# Nix owns the exact Agni Redis/Nginx configuration; no hand-copied proxy config.
out=$(podman exec "$builder" nix build --no-write-lock-file --no-link --print-out-paths /workspaces/${COMPOSITION_AGNI_CHECKOUT:-agni-qualification}/local/fatline#composition-qualification)
podman cp "$builder:$out/config/redis.conf" "$work/redis.conf"
podman cp "$builder:$out/config/nginx.conf" "$work/nginx.conf"
podman cp "$builder:$out/metadata/components.json" "$work/components.json"
readarray -t fatline_config < <(python3 - "$work/components.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    config = json.load(source)
print(config["scope"])
print(config["skymillStream"])
PY
)
[[ ${#fatline_config[@]} == 2 ]]
fatline_scope=${fatline_config[0]}
skymill_stream=${fatline_config[1]}
chmod 644 "$work/redis.conf" "$work/nginx.conf"
redis_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
api_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
# Restrict keyspace; lifecycle runtime's complete command-level ACL remains
# a separate qualification gate. Do not equate this with production ACL approval.
bootstrap_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
subscriber_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
skymill_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
bash ./fatline-acl-fixture.sh "$work/users.acl" "$redis_pass" "$subscriber_pass" "$bootstrap_pass" "$skymill_pass" "$fatline_scope" "$skymill_stream"
chmod 644 "$work/users.acl" # Rootless Redis UID 65534 must read this bind mount.
podman network create --internal "$net" >/dev/null
# Same unprivileged UID owns the socket and connects through Nginx.
if [[ "$redis_quadlet_mode" == 1 ]]; then
  mkdir -p "$quadlet_dir"
  [[ ! -e "$redis_quadlet_file" ]] || { echo "Refusing existing Quadlet: $redis_quadlet_file" >&2; exit 1; }
  cat > "$redis_quadlet_file" <<EOF
[Unit]
Description=Disposable Fatline Redis Quadlet qualification

[Container]
Image=$redis_image
ContainerName=$redis
Network=none
User=65534:65534
ReadOnly=true
DropCapability=all
NoNewPrivileges=true
Volume=$socket:/run/redis
Volume=$work/redis.conf:/etc/redis/redis.conf:ro
Volume=$work/users.acl:/etc/redis/users.acl:ro

[Service]
Restart=on-failure
TimeoutStartSec=90

EOF
  chmod 600 "$redis_quadlet_file"
  systemctl --user daemon-reload
  systemctl --user start "$redis_quadlet_service"
  [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]]
else
  podman run -d --name "$redis" --network none --user 65534:65534 \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    -v "$socket:/run/redis" \
    -v "$work/redis.conf:/etc/redis/redis.conf:ro" \
    -v "$work/users.acl:/etc/redis/users.acl:ro" \
    "$redis_image" >/dev/null
fi
for i in $(seq 1 60); do [[ -S "$socket/redis.sock" ]] && break; sleep .25; done
[[ -S "$socket/redis.sock" ]] || { podman logs "$redis"; exit 1; }
if [[ "$nginx_quadlet_mode" == 1 ]]; then
  mkdir -p "$quadlet_dir"
  [[ ! -e "$nginx_quadlet_file" ]] || { echo "Refusing existing Quadlet: $nginx_quadlet_file" >&2; exit 1; }
  cat > "$nginx_quadlet_file" <<EOF
[Unit]
Description=Disposable Fatline Nginx Quadlet qualification
EOF
  if [[ "$redis_quadlet_mode" == 1 ]]; then
    if [[ "${COMPOSITION_REDIS_CRASH_BASELINE_MODE:-0}" == 1 ]]; then
      printf 'Wants=%s\nAfter=%s\n' "$redis_quadlet_service" "$redis_quadlet_service" >> "$nginx_quadlet_file"
    else
      printf 'Requires=%s\nAfter=%s\n' "$redis_quadlet_service" "$redis_quadlet_service" >> "$nginx_quadlet_file"
    fi
  fi
  cat >> "$nginx_quadlet_file" <<EOF

[Container]
Image=$nginx_image
ContainerName=$nginx
Network=$net
NetworkAlias=redis-proxy
User=65534:65534
ReadOnly=true
DropCapability=all
NoNewPrivileges=true
Tmpfs=/tmp:rw,noexec,nosuid,size=4m,mode=1777
Volume=$socket:/run/redis
Volume=$work/nginx.conf:/etc/nginx/nginx.conf:ro

[Service]
Restart=on-failure
TimeoutStartSec=90

EOF
  chmod 600 "$nginx_quadlet_file"
  systemctl --user daemon-reload
  systemctl --user start "$nginx_quadlet_service"
  [[ "$(systemctl --user is-active "$nginx_quadlet_service")" == active ]]
else
  podman run -d --name "$nginx" --network "$net" --network-alias redis-proxy \
    --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
    --tmpfs /tmp:rw,noexec,nosuid,size=4m,mode=1777 \
    -v "$socket:/run/redis" -v "$work/nginx.conf:/etc/nginx/nginx.conf:ro" \
    "$nginx_image" >/dev/null
fi
cli_entry=$(podman image inspect "$redis_image" --format '{{index .Config.Entrypoint 0}}')
cli="${cli_entry%redis-server}redis-cli"
redis_cli() {
  podman run --rm --network "container:$nginx" --entrypoint "$cli" \
    "$redis_image" -h 127.0.0.1 -p 6379 --user logma -a "$redis_pass" --no-auth-warning "$@"
}
subscriber_cli() {
  podman run --rm --network "container:$nginx" --entrypoint "$cli" \
    "$redis_image" -h 127.0.0.1 -p 6379 --user subscriber -a "$subscriber_pass" --no-auth-warning "$@"
}
skymill_cli() {
  podman run --rm --network "container:$nginx" --entrypoint "$cli" \
    "$redis_image" -h 127.0.0.1 -p 6379 --user skymill -a "$skymill_pass" --no-auth-warning "$@"
}
bootstrap_cli() {
  podman run --rm --network "container:$nginx" --entrypoint "$cli" \
    "$redis_image" -h 127.0.0.1 -p 6379 --user bootstrap -a "$bootstrap_pass" --no-auth-warning "$@"
}
# Bootstrap the ratelimiter library with a disposable elevated identity.
bootstrap_functions() {
# Failed bootstrap containers must never poison a later retry.
podman rm -f "$bootstrap" >/dev/null 2>&1 || true
podman run -d --name "$bootstrap" --network "$net" \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --mount type=tmpfs,destination=/var/lib/logma/lifecycle,tmpfs-size=4194304,tmpfs-mode=1777 \
  -e LOGMA_RATELIMITER_BOOTSTRAP=internal \
  -e LOGMA_BIND_ADDR=0.0.0.0 \
  -e REDIS_NETWORK=tcp -e REDIS_URI=redis-proxy:6379 \
  -e REDIS_USERNAME=bootstrap -e REDISCLI_AUTH="$bootstrap_pass" \
  -e API_KEY="$api_pass" "$logma_image" >/dev/null
function_ready=false
for i in $(seq 1 60); do
  if bootstrap_cli FUNCTION LIST 2>/dev/null | grep -Fq 'dashxd_ratelimit'; then
    function_ready=true
    break
  fi
  if [[ "$(podman inspect "$bootstrap" --format '{{.State.Running}}')" != true ]]; then break; fi
  sleep .25
done
if [[ "$function_ready" != true ]]; then
  echo "Logma ratelimiter function bootstrap failed" >&2
  podman logs "$bootstrap" >&2
  podman rm -f "$bootstrap" >/dev/null 2>&1 || true
  exit 1
fi
for probe in "CONFIG GET maxmemory" "SET $fatline_scope:bootstrap:probe denied" "PUBLISH $fatline_scope:bootstrap:probe denied" "FUNCTION FLUSH"; do
  result=$(bootstrap_cli $probe 2>&1) || true
  [[ "$result" == *NOPERM* ]] || {
    echo "FAIL: bootstrap identity unexpectedly has authority for '$probe': $result" >&2
    exit 1
  }
done
echo "PASS: bootstrap identity can inspect/load Functions and revoke itself, with no key, channel, or Redis administration authority"
podman rm -f "$bootstrap" >/dev/null
[[ "$(bootstrap_cli ACL SETUSER bootstrap off)" == OK ]] || { echo "Failed to revoke bootstrap identity" >&2; exit 1; }
[[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]] || { echo "Bootstrap identity still authenticates" >&2; exit 1; }
}
if [[ "$cold_start_mode" == 1 ]]; then
  [[ "$quadlet_mode" == 1 && "$redis_quadlet_mode" == 1 && "$nginx_quadlet_mode" == 1 ]] || {
    echo "Cold-start mode requires all three Quadlet modes" >&2; exit 1;
  }
  echo "CHECK: cold-start Redis readiness before function bootstrap"
  for i in $(seq 1 60); do
    [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
    sleep .25
  done
  [[ "$(redis_cli PING)" == PONG ]]
  function_list=$(bootstrap_cli FUNCTION LIST)
  [[ "$function_list" != *dashxd_ratelimit* ]] || {
    echo "Expected empty function library before cold-start bootstrap" >&2; exit 1;
  }
  echo "PASS: cold-start Redis reachable, function library absent before bootstrap"
fi
if [[ "$bootstrap_unit_mode" == 1 ]]; then
  [[ "$cold_start_mode" == 1 ]] || { echo "Bootstrap unit mode requires cold-start mode" >&2; exit 1; }
  mkdir -p "$HOME/.config/systemd/user"
  [[ ! -e "$bootstrap_unit_file" ]] || { echo "Refusing existing unit: $bootstrap_unit_file" >&2; exit 1; }
  # The service executes the same qualification bootstrap function in a
  # separate shell. Its credentials are ephemeral and never promoted.
  declare -f bootstrap_cli bootstrap_functions > "$work/bootstrap-functions.sh"
  cat > "$work/bootstrap-entry.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
redis_image=$(printf '%q' "$redis_image")
logma_image=$(printf '%q' "$logma_image")
nginx=$(printf '%q' "$nginx")
bootstrap=$(printf '%q' "$bootstrap")
net=$(printf '%q' "$net")
cli=$(printf '%q' "$cli")
redis_pass=$(printf '%q' "$redis_pass")
bootstrap_pass=$(printf '%q' "$bootstrap_pass")
api_pass=$(printf '%q' "$api_pass")
EOF
  cat "$work/bootstrap-functions.sh" >> "$work/bootstrap-entry.sh"
  printf '\nbootstrap_functions\n' >> "$work/bootstrap-entry.sh"
  chmod 700 "$work/bootstrap-entry.sh"
  cat > "$bootstrap_unit_file" <<EOF
[Unit]
Description=Disposable Fatline Redis Function bootstrap
$(if [[ "${COMPOSITION_REDIS_CRASH_BASELINE_MODE:-0}" == 1 ]]; then printf 'Wants=%s' "$nginx_quadlet_service"; else printf 'Requires=%s' "$nginx_quadlet_service"; fi)
After=$nginx_quadlet_service

[Service]
Type=oneshot
ExecStart=/usr/bin/bash $work/bootstrap-entry.sh
RemainAfterExit=yes
TimeoutStartSec=90
EOF
  chmod 600 "$bootstrap_unit_file"
  systemctl --user daemon-reload
  if [[ "${COMPOSITION_FUNCTION_RECONCILE_MODE:-0}" == 1 ]]; then
    cat > "$work/reconcile-entry.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
redis_image=$(printf '%q' "$redis_image")
logma_image=$(printf '%q' "$logma_image")
nginx=$(printf '%q' "$nginx")
bootstrap=$(printf '%q' "$bootstrap")
net=$(printf '%q' "$net")
cli=$(printf '%q' "$cli")
redis_pass=$(printf '%q' "$redis_pass")
bootstrap_pass=$(printf '%q' "$bootstrap_pass")
api_pass=$(printf '%q' "$api_pass")
EOF
    cat "$work/bootstrap-functions.sh" >> "$work/reconcile-entry.sh"
    cat >> "$work/reconcile-entry.sh" <<'EOF'
# The privileged principal is available only on a freshly started Redis.
# Inspect the exact library instead of treating arbitrary FCALL errors as readiness.
listing=$(bootstrap_cli --raw FUNCTION LIST 2>&1) || true
if [[ "$listing" == *WRONGPASS* || "$listing" == *NOAUTH* ]]; then
  # Bootstrap already revoked: the application principal must resolve
  # the known Function; never accept unrelated Redis errors.
  probe=$(redis_cli FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0 2>&1) && exit 0
  [[ "$probe" == *"wrong number of arguments"* ]] && exit 0
  echo "FAIL: bootstrap revoked but Function is not callable: $probe" >&2
  exit 1
fi
if [[ "$listing" == *NOPERM* || "$listing" == *ERR* || "$listing" == *"Could not connect"* ]]; then
  echo "FAIL: cannot inspect Redis Functions: $listing" >&2
  exit 1
fi
if [[ "$listing" == *dashxd_ratelimit* ]]; then
  [[ "$(bootstrap_cli ACL SETUSER bootstrap off)" == OK ]]
  echo "PASS: existing Functions verified and bootstrap principal revoked"
else
  echo "CHECK: missing Redis Functions; running elevated bootstrap"
  bootstrap_functions
  echo "PASS: Redis Functions restored and bootstrap principal revoked"
fi
[[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]] || {
  echo "FAIL: bootstrap principal still authenticates" >&2; exit 1;
}
EOF
    chmod 700 "$work/reconcile-entry.sh"
    cat > "$HOME/.config/systemd/user/$scope-reconcile.service" <<EOF
[Unit]
Description=Disposable Fatline Redis Function reconciliation
Wants=$nginx_quadlet_service
After=$nginx_quadlet_service

[Service]
Type=oneshot
ExecStart=/usr/bin/bash $work/reconcile-entry.sh
TimeoutStartSec=90
EOF
    cat > "$HOME/.config/systemd/user/$scope-reconcile.timer" <<EOF
[Unit]
Description=Disposable Fatline Redis Function reconciliation schedule

[Timer]
OnActiveSec=2s
OnUnitInactiveSec=2s
Unit=$scope-reconcile.service

[Install]
WantedBy=timers.target
EOF
    chmod 600 "$HOME/.config/systemd/user/$scope-reconcile.service" "$HOME/.config/systemd/user/$scope-reconcile.timer"
    systemctl --user daemon-reload
  fi
  echo "CHECK: systemd-user Redis Function bootstrap oneshot"
  systemctl --user start "$bootstrap_unit" || {
    echo "Bootstrap oneshot failed; collecting unit status and journal" >&2
    systemctl --user --no-pager -l status "$bootstrap_unit" >&2 || true
    journalctl --user -u "$bootstrap_unit" -n 70 --no-pager -l >&2 || true
    exit 1
  }
  [[ "$(systemctl --user is-active "$bootstrap_unit")" == active ]]
  [[ "$(systemctl --user show "$bootstrap_unit" -p Result --value)" == success ]]
  echo "PASS: systemd-user bootstrap oneshot completed"
  echo "CHECK: bootstrap prerequisite remains successful before Logma startup"
else
  if [[ "$agni_reconcile_mode" == 1 ]]; then
    [[ "$quadlet_mode" == 1 && "$redis_quadlet_mode" == 1 && "$nginx_quadlet_mode" == 1 ]] || {
      echo "Agni reconciler qualification requires the real Redis/Nginx/Logma Quadlet topology" >&2; exit 1;
    }
    bash "$COMPOSITION_AGNI_SOURCE/local/fatline/scripts/reconcile-redis.sh" \
      "$logma_image" "$redis_image" "$fatline_scope" "$work/users.acl.credentials" "$socket"
  else
    bootstrap_functions
  fi
fi
if [[ "$cold_start_mode" == 1 ]]; then
  [[ "$(redis_cli FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0 2>&1)" != *"Function not found"* ]] || {
    echo "Function missing after bootstrap" >&2; exit 1;
  }
  [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]]
  echo "PASS: cold-start function bootstrap completed and privileged identity revoked before Logma"
fi
echo "PASS: ratelimiter functions installed; bootstrap identity revoked"
for i in $(seq 1 60); do
  if [[ "$(redis_cli PING 2>/dev/null)" == PONG ]]; then break; fi
  sleep .25
done
[[ "$(redis_cli PING)" == PONG ]] || { podman logs "$nginx"; exit 1; }
[[ "$(redis_cli HSET "$fatline_scope:logma:pubsub:channel:qualification" name qualification)" == 1 ]]
[[ "$(redis_cli HGET "$fatline_scope:logma:pubsub:channel:qualification" name)" == qualification ]]
[[ "$(redis_cli SET foreign:denied value)" == *NOPERM* ]]
[[ "$(redis_cli ACL LIST)" == *NOPERM* ]]
echo "PASS: authenticated TCP -> Nginx -> Unix Redis, key isolation, admin denial"
if [[ "$agni_reconcile_mode" == 1 ]]; then
  echo "CHECK: Redis Quadlet restart reloads the pinned ACL and Agni reconciliation revokes bootstrap"
  systemctl --user restart "$redis_quadlet_service"
  [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]]
  for i in $(seq 1 60); do
    [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
    sleep .25
  done
  [[ "$(redis_cli PING)" == PONG ]]
  [[ "$(bootstrap_cli PING 2>&1)" == PONG ]] || {
    echo "FAIL: bootstrap identity did not load from ACL after Redis restart" >&2; exit 1;
  }
  bash "$COMPOSITION_AGNI_SOURCE/local/fatline/scripts/reconcile-redis.sh" \
    "$logma_image" "$redis_image" "$fatline_scope" "$work/users.acl.credentials" "$socket"
  [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]] || {
    echo "FAIL: Agni reconciler did not revoke bootstrap after restart" >&2; exit 1;
  }
  echo "PASS: Redis restart reloaded the scoped ACL; Agni restored Functions and revoked bootstrap"
fi
if [[ "${COMPOSITION_SKYMILL_PROVIDER_MODE:-0}" == 1 ]]; then
  provider_image=${COMPOSITION_SKYMILL_IMAGE:-localhost/skymill-provider:scoped-qualification}
  podman image exists "$provider_image" || {
    echo "FAIL: Skymill provider image missing: $provider_image (build/import the scoped provider image first)" >&2
    exit 1
  }
  SKYMILL_TEST_NAME="$skymill_provider" \
  SKYMILL_TEST_IMAGE="$provider_image" \
  SKYMILL_TEST_NETWORK="$net" \
  SKYMILL_TEST_PASSWORD="$skymill_pass" \
  SKYMILL_TEST_SCOPE="$fatline_scope" \
  SKYMILL_TEST_STREAM="$skymill_stream" \
  python3 ./fatline-skymill-provider.py
  echo "PASS: Fatline composition Skymill provider"
  exit 0
fi
# Dedicated negative ACL probes against the actual Nginx -> Redis Unix-socket path.
if [[ "${COMPOSITION_SKYMILL_ACL_MODE:-0}" == 1 ]]; then
  echo "CHECK: Skymill scoped Redis Streams principal and adjacent tenant isolation"
  stream=$skymill_stream
  adjacent="$fatline_scope:skymill:stream:adjacent"
  foreign="$fatline_scope-foreign:skymill:stream:github.webhooks"
  expect_skymill_noperm() {
    local description=$1; shift
    local result
    result=$(skymill_cli "$@" 2>&1) || true
    [[ "$result" == *NOPERM* ]] || { echo "FAIL: $description: expected NOPERM, got: $result" >&2; exit 1; }
  }
  [[ "$(skymill_cli PING)" == PONG ]]
  entry=$(skymill_cli XADD "$stream" '*' payload qualified)
  [[ "$entry" == *-* ]] || { echo "FAIL: scoped stream XADD: $entry" >&2; exit 1; }
  group=$(skymill_cli XGROUP CREATE "$stream" qualifier 0 2>&1)
  [[ "$group" == OK ]] || { echo "FAIL: scoped stream group: $group" >&2; exit 1; }
  entries=$(skymill_cli XREADGROUP GROUP qualifier worker COUNT 1 STREAMS "$stream" '>')
  [[ "$entries" == *qualified* ]] || { echo "FAIL: scoped XREADGROUP missing message: $entries" >&2; exit 1; }
  [[ "$(skymill_cli XACK "$stream" qualifier "$entry")" == 1 ]]
  expect_skymill_noperm "Logma key read" GET "$fatline_scope:logma:acl:allowed"
  expect_skymill_noperm "Logma key write" SET "$fatline_scope:logma:acl:allowed" denied
  expect_skymill_noperm "adjacent stream write" XADD "$adjacent" '*' payload denied
  expect_skymill_noperm "adjacent stream read" XREAD STREAMS "$adjacent" 0
  expect_skymill_noperm "foreign scope stream write" XADD "$foreign" '*' payload denied
  expect_skymill_noperm "Redis administration" CONFIG GET maxmemory
  expect_skymill_noperm "Redis Function management" FUNCTION FLUSH
  expect_skymill_noperm "Redis ACL administration" ACL LIST
  expect_skymill_noperm "Logma channel publish" PUBLISH "$fatline_scope:logma:qualification:dispatch:probe" denied
  expect_skymill_noperm "Logma Function execution" FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0
  [[ "$(skymill_cli XLEN "$stream" 2>&1)" == *NOPERM* ]] || {
    echo "FAIL: undeclared XLEN unexpectedly allowed" >&2; exit 1;
  }
  echo "PASS: Skymill scoped Streams operations, adjacent tenant, Logma and administration isolation"
  [[ "$agni_reconcile_mode" == 1 ]] || exit 0
fi
if [[ "${COMPOSITION_ACL_ISOLATION_MODE:-0}" == 1 ]]; then
  echo "CHECK: dedicated Redis principal, key, channel and administration isolation"
  expect_noperm() {
    local description=$1; shift
    local result
    result=$(redis_cli "$@" 2>&1) || true
    [[ "$result" == *NOPERM* ]] || { echo "FAIL: $description: expected NOPERM, got: $result" >&2; exit 1; }
  }
  expect_subscriber_noperm() {
    local description=$1; shift
    local result
    result=$(subscriber_cli "$@" 2>&1) || true
    [[ "$result" == *NOPERM* ]] || { echo "FAIL: $description: expected NOPERM, got: $result" >&2; exit 1; }
  }
  [[ "$(redis_cli HSET "$fatline_scope:logma:pubsub:channel:acl-allowed" name value)" == 1 ]]
  [[ "$(redis_cli HGET "$fatline_scope:logma:pubsub:channel:acl-allowed" name)" == value ]]
  expect_noperm "cross-tenant write" SET foreign:tenant:secret denied
  expect_noperm "cross-tenant read" GET foreign:tenant:secret
  expect_noperm "cross-tenant delete" DEL foreign:tenant:secret
  expect_noperm "cross-tenant scan" KEYS 'foreign:*'
  expect_noperm "administration" CONFIG GET maxmemory
  expect_noperm "ACL modification" ACL SETUSER intruder on nopass +@all
  expect_noperm "function replacement" FUNCTION FLUSH
  expect_noperm "function load" FUNCTION LOAD '#!lua name=intruder'
  expect_noperm "foreign channel publish" PUBLISH foreign:shutdown test
  expect_subscriber_noperm "subscriber cannot read keys" HGET "$fatline_scope:logma:pubsub:channel:acl-allowed" name
  expect_subscriber_noperm "subscriber cannot publish" PUBLISH "$fatline_scope:logma:qualification:dispatch:probe" test
  expect_subscriber_noperm "subscriber cannot subscribe to foreign channel" SUBSCRIBE foreign:shutdown
  [[ "$(redis_cli HGET "$fatline_scope:logma:pubsub:channel:acl-allowed" name)" == value ]] || { echo "FAIL: allowed scoped hash changed" >&2; exit 1; }
  [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]] || { echo "FAIL: bootstrap principal still authenticates" >&2; exit 1; }
  echo "PASS: dedicated Redis ACL key, channel, administration, Function and bootstrap revocation probes"
  [[ "$agni_reconcile_mode" == 1 ]] || exit 0
fi
if [[ "$nginx_quadlet_mode" == 1 && "$bootstrap_unit_mode" != 1 ]]; then
  echo "CHECK: systemd-user Nginx Quadlet restart"
  systemctl --user restart "$nginx_quadlet_service"
  [[ "$(systemctl --user is-active "$nginx_quadlet_service")" == active ]]
  for i in $(seq 1 60); do
    [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
    sleep .25
  done
  [[ "$(redis_cli PING)" == PONG ]] || { echo "Nginx proxy did not recover" >&2; false; }
  echo "PASS: systemd-user Nginx Quadlet restart and Unix-socket proxy recovery"
fi
if [[ "$redis_quadlet_mode" == 1 && "$bootstrap_unit_mode" != 1 && "$agni_reconcile_mode" != 1 ]]; then
  echo "CHECK: systemd-user Redis Quadlet restart"
  systemctl --user restart "$redis_quadlet_service"
  [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]]
  for i in $(seq 1 60); do
    [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
    sleep .25
  done
  [[ "$(redis_cli PING)" == PONG ]] || { echo "Redis did not recover through Nginx" >&2; false; }
  [[ "$(redis_cli HSET "$fatline_scope:logma:pubsub:channel:after-restart" state ok)" == 1 ]]
  echo "CHECK: reinstalling Redis Functions after RAM-only Redis restart"
  bootstrap_functions
  [[ "$(redis_cli PING)" == PONG ]]
  echo "PASS: Redis Functions reinstalled and bootstrap principal revoked after restart"
  echo "PASS: systemd-user Redis Quadlet restart and Nginx proxy recovery"
fi
mkdir -m 777 "$work/lifecycle-state"
if [[ "$quadlet_mode" == 1 ]]; then
  mkdir -p "$quadlet_dir"
  [[ ! -e "$quadlet_file" ]] || { echo "Refusing existing Quadlet: $quadlet_file" >&2; exit 1; }
  cat > "$quadlet_file" <<EOF
[Unit]
Description=Disposable Fatline Logma Quadlet qualification
EOF
  if [[ "$bootstrap_unit_mode" == 1 ]]; then
    if [[ "${COMPOSITION_REDIS_CRASH_BASELINE_MODE:-0}" == 1 ]]; then
      # Order initial bootstrap without coupling Logma's lifetime to Redis.
      printf 'Wants=%s\nAfter=%s\n' "$bootstrap_unit" "$bootstrap_unit" >> "$quadlet_file"
    else
      printf 'Requires=%s\nAfter=%s\n' "$bootstrap_unit" "$bootstrap_unit" >> "$quadlet_file"
    fi
  elif [[ "$nginx_quadlet_mode" == 1 ]]; then
    printf 'Requires=%s\nAfter=%s\n' "$nginx_quadlet_service" "$nginx_quadlet_service" >> "$quadlet_file"
  fi
  cat >> "$quadlet_file" <<EOF

[Container]
Image=$logma_image
ContainerName=$logma
Network=$net
User=65534:65534
ReadOnly=true
DropCapability=all
NoNewPrivileges=true
Volume=$work/lifecycle-state:/var/lib/logma/lifecycle
Environment=LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle
Environment=FATLINE_SCOPE=$fatline_scope
Environment=LOGMA_BIND_ADDR=0.0.0.0
Environment=REDIS_NETWORK=tcp
Environment=REDIS_URI=redis-proxy:6379
Environment=REDIS_USERNAME=logma
Environment=REDISCLI_AUTH=$redis_pass
Environment=API_KEY=$api_pass
PublishPort=127.0.0.1::8080

[Service]
Restart=on-failure
TimeoutStartSec=90

EOF
  chmod 600 "$quadlet_file"
  systemctl --user daemon-reload
  systemctl --user start "$quadlet_service" || { systemctl --user --no-pager status "$quadlet_service" >&2 || true; exit 1; }
  [[ "$(systemctl --user is-active "$quadlet_service")" == active ]]
else
  podman run -d --name "$logma" --network "$net" \
    --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
    -v "$work/lifecycle-state:/var/lib/logma/lifecycle" \
    -e LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle \
    -e FATLINE_SCOPE="$fatline_scope" \
    -e LOGMA_BIND_ADDR=0.0.0.0 \
    -e REDIS_NETWORK=tcp \
    -e REDIS_URI=redis-proxy:6379 \
    -e REDIS_USERNAME=logma -e REDISCLI_AUTH="$redis_pass" -e API_KEY="$api_pass" \
    -p 127.0.0.1::8080 "$logma_image" >/dev/null
fi
port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
[[ "$port" =~ ^[0-9]+$ ]] || { echo "Cannot resolve published Logma port" >&2; exit 1; }
url="http://127.0.0.1:$port/lifecycle/policies"
for i in $(seq 1 60); do
  status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "$url" 2>/dev/null || true)
  [[ "$status" == 200 ]] && break
  sleep .25
done
[[ "$status" == 200 ]] || { podman logs "$logma"; echo "Authenticated lifecycle policies HTTP $status" >&2; exit 1; }
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$url")" == 401 ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -H 'X-API-Key: incorrect' "$url")" == 401 ]]
# Exercise actual lifecycle arming, ticking, and removal through Logma's Redis client.
# This is deliberately fail-closed: the provisional ACL may need refinement.
lifecycle_url="http://127.0.0.1:$port/lifecycle"
readiness_url="$lifecycle_url/readyz"
if [[ "${COMPOSITION_STRICT_READINESS_MODE:-0}" == 1 ]]; then
  readiness_status=$(curl -sS --max-time 3 -o "$work/readiness-healthy.txt" -w '%{http_code}' "$readiness_url")
  [[ "$readiness_status" == 200 && "$(cat "$work/readiness-healthy.txt")" == ready ]] || {
    echo "FAIL: readiness did not report healthy Redis and lifecycle Functions (HTTP $readiness_status)" >&2; exit 1;
  }
  echo "PASS: readiness reports healthy Redis and lifecycle Functions"
fi
deployment="qualification-$"
# Use a policy code returned by the running Logma build; do not guess enum strings.
policy_code=$(curl -fsS --max-time 5 -H "X-API-Key: $api_pass" "$url" | python3 -c 'import json,sys; p=json.load(sys.stdin); assert isinstance(p,list) and p, "empty lifecycle policy catalog"; x=next((x for x in p if x.get("duration")=="720h0m0s"),p[-1]); assert str(x.get("policy_code","")).isdigit(), "missing policy code"; print(x["policy_code"])')
payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"%s:logma:qualification:shutdown"}' "$deployment" "$policy_code" "$fatline_scope")
register_status=$(curl -sS --max-time 10 -o "$work/register.json" -w '%{http_code}' \
  -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
  --data "$payload" "$lifecycle_url/")
if [[ "$register_status" != 201 ]]; then
  echo "Lifecycle registration failed: HTTP $register_status" >&2
  cat "$work/register.json" >&2
  podman logs --tail 40 "$logma" >&2
  exit 1
fi
grep -Fq '"armed":true' "$work/register.json" || { echo "Lifecycle registration was not armed" >&2; cat "$work/register.json" >&2; exit 1; }
tick_status=$(curl -sS --max-time 10 -o "$work/tick.json" -w '%{http_code}' \
  -X POST -H "X-API-Key: $api_pass" "$lifecycle_url/tick")
[[ "$tick_status" == 200 ]] || { echo "Lifecycle tick failed: HTTP $tick_status" >&2; cat "$work/tick.json" >&2; exit 1; }
remove_status=$(curl -sS --max-time 10 -o "$work/remove.json" -w '%{http_code}' \
  -X DELETE -H "X-API-Key: $api_pass" "$lifecycle_url/$deployment")
[[ "$remove_status" == 200 ]] || { echo "Lifecycle remove failed: HTTP $remove_status" >&2; cat "$work/remove.json" >&2; exit 1; }
echo "PASS: Logma lifecycle register/arm, tick and remove via Redis"
# Live subscriber qualification: dispatch once, then fence reconciliation and restart.
if [[ "${COMPOSITION_DISPATCH_MODE:-0}" == 1 ]]; then
  echo "CHECK: live lifecycle expiration and duplicate-dispatch fence"
  dispatch_id="dispatch-$"
  dispatch_channel="$fatline_scope:logma:qualification:dispatch:$"
  dispatch_key="$fatline_scope:logma:lifecycle:{deployment:$dispatch_id}:lifecycle:timers"
  dispatch_log="$work/dispatch-subscriber.log"
  # --raw emits each RESP2 subscribe event on separate lines.
  subscriber_cli --raw SUBSCRIBE "$dispatch_channel" >"$dispatch_log" 2>&1 &
  subscriber_pid=$!
  # Wait for Redis to confirm an actual subscriber before registering.
  ready=0
  for i in $(seq 1 40); do
    if grep -Fxq "subscribe" "$dispatch_log" && grep -Fxq "$dispatch_channel" "$dispatch_log"; then ready=1; break; fi
    if ! kill -0 "$subscriber_pid" 2>/dev/null; then break; fi
    sleep .25
  done
  [[ "$ready" == 1 ]] || { echo "FAIL: Redis subscriber not ready" >&2; cat "$dispatch_log" >&2; exit 1; }
  # Select a published policy with duration >= 30 seconds, and backdate
  # activation to make its deadline approximately 8 seconds from now.
  curl -fsS --max-time 5 -H "X-API-Key: $api_pass" "$url" > "$work/dispatch-policies.json"
  python3 - "$work/dispatch-policies.json" "$work/dispatch-request.json" "$dispatch_id" "$dispatch_channel" <<'PY'
import json, sys, re
from datetime import datetime, timedelta, timezone
policies = json.load(open(sys.argv[1]))
def seconds(value):
    match = re.fullmatch(r'(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?', value)
    if not match:
        return None
    h, m, s = match.groups()
    return int(h or 0)*3600 + int(m or 0)*60 + float(s or 0)
candidates = [(seconds(p.get('duration','')),p) for p in policies]
candidates = [(d,p) for d,p in candidates if d is not None and d >= 30 and str(p.get('policy_code','')).isdigit()]
if not candidates:
    raise SystemExit("FAIL: no suitable lifecycle policy for dispatch gate")
duration, policy = min(candidates, key=lambda item: item[0])
activated = datetime.now(timezone.utc) - timedelta(seconds=duration-8)
json.dump({'deployment_id':sys.argv[3], 'policy_code':str(policy['policy_code']),
           'shutdown_channel':sys.argv[4], 'activated_at':activated.isoformat().replace('+00:00','Z')},
          open(sys.argv[2],'w'))
PY
  dispatch_status=$(curl -sS --max-time 10 -o "$work/dispatch-register.json" -w '%{http_code}' \
    -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
    --data-binary "@$work/dispatch-request.json" "$lifecycle_url/")
  [[ "$dispatch_status" == 201 ]] || { echo "FAIL: dispatch registration HTTP $dispatch_status" >&2; cat "$work/dispatch-register.json" >&2; exit 1; }
  published=0
  for i in $(seq 1 40); do
    lines=$(wc -l <"$dispatch_log")
    if [[ "$lines" -ge 6 ]]; then published=1; break; fi
    sleep .5
  done
  [[ "$published" == 1 ]] || { echo "FAIL: no dispatch observed on live subscription" >&2; cat "$dispatch_log" >&2; exit 1; }
  [[ -z "$(redis_cli ZSCORE "$dispatch_key" shutdown:timer)" ]] || { echo "FAIL: dispatched timer still armed" >&2; exit 1; }
  [[ -f "$work/lifecycle-state/$dispatch_id.dispatched" ]] || { echo "FAIL: durable dispatch marker absent" >&2; exit 1; }
  echo "PASS: live subscriber received lifecycle shutdown and durable dispatch fence exists"
  sleep 12
  [[ -z "$(redis_cli ZSCORE "$dispatch_key" shutdown:timer)" ]] || { echo "FAIL: reconciliation rearmed dispatched timer" >&2; exit 1; }
  if [[ "$quadlet_mode" == 1 ]]; then systemctl --user restart "$quadlet_service"; else podman restart "$logma" >/dev/null; fi
  sleep 7
  [[ -z "$(redis_cli ZSCORE "$dispatch_key" shutdown:timer)" ]] || { echo "FAIL: restart rearmed dispatched timer" >&2; exit 1; }
  # One Redis subscribe handshake emits three lines; each delivered message
  # adds another three. Exactly one publication must be observed.
  lines=$(wc -l <"$dispatch_log")
  [[ "$lines" -eq 6 ]] || { echo "FAIL: expected one dispatch (6 lines), got $lines" >&2; cat "$dispatch_log" >&2; exit 1; }
  kill "$subscriber_pid" 2>/dev/null || true
  wait "$subscriber_pid" 2>/dev/null || true
  echo "PASS: one lifecycle dispatch, no timer rearm across reconciliation and Logma restart"
  exit 0
fi
# Leave a durable registration in the mounted state directory across restart.
restore_deployment="restore-$"
restore_payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"%s:logma:qualification:shutdown"}' "$restore_deployment" "$policy_code" "$fatline_scope")
echo "CHECK: registering durable lifecycle fixture"
restore_status=$(curl -sS --max-time 10 -o "$work/restore-register.json" -w '%{http_code}' \
  -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
  --data "$restore_payload" "$lifecycle_url/")
[[ "$restore_status" == 201 ]] || { echo "Restore fixture registration failed: HTTP $restore_status" >&2; cat "$work/restore-register.json" >&2; exit 1; }
grep -Fq '"armed":true' "$work/restore-register.json" || { echo "Restore fixture was not armed" >&2; exit 1; }
echo "CHECK: Logma image identity before restart"
logma_id=$(podman image inspect "$logma_image" --format '{{.Id}}')
[[ "$(podman inspect "$logma" --format '{{.Image}}')" == "$logma_id" ]] || { echo "Logma image identity mismatch: $(podman inspect "$logma" --format '{{.Image}}') vs $logma_id" >&2; false; }
echo "CHECK: restarting Logma through selected supervisor"
if [[ "$quadlet_mode" == 1 ]]; then
  systemctl --user restart "$quadlet_service"
  [[ "$(systemctl --user is-active "$quadlet_service")" == active ]]
else
  podman restart "$logma" >/dev/null
fi
# Quadlet replaces the container, so an ephemeral published port can change.
port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
[[ "$port" =~ ^[0-9]+$ ]] || { echo "Cannot resolve restarted Logma published port" >&2; false; }
url="http://127.0.0.1:$port/lifecycle/policies"
lifecycle_url="http://127.0.0.1:$port/lifecycle"
readiness_url="$lifecycle_url/readyz"
echo "CHECK: restored Logma HTTP endpoint on port $port"
for i in $(seq 1 60); do
  status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "$url" 2>/dev/null || true)
  [[ "$status" == 200 ]] && break
  sleep .25
done
[[ "$status" == 200 ]]
[[ "$(podman inspect "$logma" --format '{{.Image}}')" == "$logma_id" ]]
curl -fsS --max-time 10 -H "X-API-Key: $api_pass" "$lifecycle_url/" > "$work/restore-list.json"
grep -Fq "\"deployment_id\":\"$restore_deployment\"" "$work/restore-list.json" || { echo "Lifecycle registration missing after restart" >&2; cat "$work/restore-list.json" >&2; exit 1; }
post_restart_tick=$(curl -sS --max-time 10 -o "$work/post-restart-tick.json" -w '%{http_code}' -X POST -H "X-API-Key: $api_pass" "$lifecycle_url/tick")
[[ "$post_restart_tick" == 200 ]] || { echo "Restored lifecycle tick failed: HTTP $post_restart_tick" >&2; cat "$work/post-restart-tick.json" >&2; exit 1; }
post_restart_remove=$(curl -sS --max-time 10 -o "$work/post-restart-remove.json" -w '%{http_code}' -X DELETE -H "X-API-Key: $api_pass" "$lifecycle_url/$restore_deployment")
[[ "$post_restart_remove" == 200 ]] || { echo "Restored lifecycle remove failed: HTTP $post_restart_remove" >&2; cat "$work/post-restart-remove.json" >&2; exit 1; }
echo "PASS: Logma lifecycle registration restored, ticked and removed after process restart"
echo "PASS: Logma unprivileged read-only HTTP auth and restart with immutable image identity"
if [[ "$quadlet_mode" == 1 ]]; then
  echo "PASS: systemd-user Quadlet Logma startup, restart and lifecycle restoration"
  if [[ "$nginx_quadlet_mode" == 1 && "$redis_quadlet_mode" == 1 ]]; then
    echo "CHECK: generated systemd dependency edges"
    systemctl --user show "$quadlet_service" -p Requires -p After > "$work/logma-dependencies"
    systemctl --user show "$nginx_quadlet_service" -p Requires -p After > "$work/nginx-dependencies"
    grep -Fq "$redis_quadlet_service" "$work/nginx-dependencies"
    if [[ "$bootstrap_unit_mode" == 1 ]]; then
      systemctl --user show "$bootstrap_unit" -p Requires -p After > "$work/bootstrap-dependencies"
      for edge in "$bootstrap_unit:$work/logma-dependencies" "$nginx_quadlet_service:$work/bootstrap-dependencies"; do
        expected=${edge%%:*}
        dependency_file=${edge#*:}
        grep -Fq "$expected" "$dependency_file" || {
          echo "Missing required systemd dependency $expected in $dependency_file" >&2
          cat "$dependency_file" >&2
          exit 1
        }
      done
      echo "PASS: generated systemd dependency edges Logma -> Bootstrap -> Nginx -> Redis"
    else
      grep -Fq "$nginx_quadlet_service" "$work/logma-dependencies"
      echo "PASS: generated systemd dependency edges Logma -> Nginx -> Redis"
    fi
  fi
  if [[ "$redis_quadlet_mode" == 1 && "$nginx_quadlet_mode" == 1 ]]; then
    if [[ "$bootstrap_unit_mode" == 1 && "${COMPOSITION_COORDINATED_RESTART_MODE:-0}" == 1 ]]; then
      echo "CHECK: coordinated cold restart, Logma as sole systemd entrypoint"
      systemctl --user stop "$quadlet_service"
      systemctl --user stop "$bootstrap_unit"
      systemctl --user stop "$nginx_quadlet_service"
      systemctl --user stop "$redis_quadlet_service"
      if [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]] ||
         [[ "$(systemctl --user is-active "$bootstrap_unit")" == active ]]; then
        echo "FAIL: Redis or bootstrap remained active after coordinated stop" >&2
        exit 1
      fi
      echo "CHECK: starting Logma pulls Redis, Nginx and bootstrap prerequisites"
      systemctl --user start "$quadlet_service"
      for unit in "$redis_quadlet_service" "$nginx_quadlet_service" "$bootstrap_unit" "$quadlet_service"; do
        [[ "$(systemctl --user is-active "$unit")" == active ]] || {
          echo "Required systemd unit not active: $unit" >&2
          exit 1
        }
      done
      [[ "$(redis_cli PING)" == PONG ]]
      [[ "$(redis_cli FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0 2>&1)" != *"Function not found"* ]]
      [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]]
      port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
      [[ "$port" =~ ^[0-9]+$ ]]
      status=""
      for i in $(seq 1 60); do
        status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "http://127.0.0.1:$port/lifecycle/policies" 2>/dev/null || true)
        [[ "$status" == 200 ]] && break
        sleep .25
      done
      [[ "$status" == 200 ]] || { echo "Logma HTTP unavailable after coordinated cold restart: $status" >&2; exit 1; }
      readiness_url="http://127.0.0.1:$port/lifecycle/readyz"
      echo "PASS: Logma-only start restored Redis Functions, revoked bootstrap principal and recovered authenticated HTTP"
      if [[ "${COMPOSITION_REDIS_CRASH_BASELINE_MODE:-0}" == 1 ]]; then
        if [[ "${COMPOSITION_LIFECYCLE_CRASH_MODE:-0}" == 1 ]]; then
          # The earlier restart test deliberately deletes restore_deployment.
          # Establish a separate durable fixture immediately before the crash.
          restore_deployment="crash-fixture-$"
          restore_payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"%s:logma:qualification:shutdown"}' "$restore_deployment" "$policy_code" "$fatline_scope")
          lifecycle_url="http://127.0.0.1:$port/lifecycle"
          echo "CHECK: registering persistent lifecycle fixture immediately before Redis crash"
          crash_fixture_status=$(curl -sS --max-time 10 -o "$work/crash-fixture-register.json" -w '%{http_code}' \
            -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
            --data "$restore_payload" "$lifecycle_url/")
          [[ "$crash_fixture_status" == 201 ]] ||
            { echo "FAIL: crash fixture registration HTTP $crash_fixture_status" >&2; cat "$work/crash-fixture-register.json" >&2; exit 1; }
          grep -Fq '"armed":true' "$work/crash-fixture-register.json" ||
            { echo "FAIL: crash fixture not armed" >&2; exit 1; }
          curl -fsS --max-time 10 -H "X-API-Key: $api_pass" "$lifecycle_url/" > "$work/pre-crash-list.json"
          grep -Fq "\"deployment_id\":\"$restore_deployment\"" "$work/pre-crash-list.json" ||
            { echo "FAIL: crash fixture not listed before crash" >&2; exit 1; }
          if [[ "${COMPOSITION_TIMER_STATE_MODE:-0}" == 1 ]]; then
            echo "CHECK: pre-crash lifecycle timer state and durable deadline"
            python3 - "$work/crash-fixture-register.json" "$work/timer-deadline.txt" <<'PY'
import json, sys
from datetime import datetime
obj = json.load(open(sys.argv[1]))
reg = obj.get("registration", obj)
deadline = reg.get("deadline")
if not isinstance(deadline, str) or not deadline:
    raise SystemExit("FAIL: registration response lacks durable deadline")
datetime.fromisoformat(deadline.replace("Z", "+00:00"))
open(sys.argv[2], "w").write(deadline)
PY
            timer_key="$fatline_scope:logma:lifecycle:{deployment:$restore_deployment}:lifecycle:timers"
            expected_deadline_ms=$(python3 - "$work/timer-deadline.txt" <<'PY'
from datetime import datetime
import sys
value = open(sys.argv[1]).read()
print(int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000))
PY
)
            before_score=$(redis_cli ZSCORE "$timer_key" shutdown:timer)
            [[ "$before_score" == "$expected_deadline_ms" ]] || {
              echo "FAIL: pre-crash timer score $before_score differs from durable deadline $expected_deadline_ms" >&2
              exit 1
            }
            echo "PASS: durable deadline captured and Redis lifecycle keys present before crash"
          fi
          echo "PASS: durable crash fixture registered and visible before Redis SIGKILL"
        fi
        echo "CHECK: unexpected Redis crash with Logma remaining active"
        old_redis_id=$(podman inspect "$redis" --format '{{.Id}}')
        old_logma_id=$(podman inspect "$logma" --format '{{.Id}}')
        if [[ "${COMPOSITION_FUNCTION_RECONCILE_MODE:-0}" == 1 && "${COMPOSITION_CRASH_WINDOW_MODE:-0}" != 1 ]]; then
          systemctl --user start "$scope-reconcile.timer"
        fi
        if [[ "${COMPOSITION_CRASH_WINDOW_MODE:-0}" == 1 ]]; then
          echo "CHECK: Logma function-dependent operation while Redis is unavailable"
          podman pause "$redis" >/dev/null
          window_port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
          [[ "$window_port" =~ ^[0-9]+$ ]] || { echo "FAIL: cannot resolve Logma port" >&2; exit 1; }
          window_url="http://127.0.0.1:$window_port/lifecycle/tick"
          unavailable_status=$(curl -sS --connect-timeout 1 --max-time 2 -o "$work/unavailable-response.json" -w '%{http_code}' -X POST -H "X-API-Key: $api_pass" "$window_url" 2>/dev/null || true)
          if [[ "${COMPOSITION_STRICT_READINESS_MODE:-0}" == 1 ]]; then
            readiness_unavailable=$(curl -sS --connect-timeout 1 --max-time 4 -o "$work/readiness-redis-down.txt" -w '%{http_code}' "$readiness_url" 2>/dev/null || true)
            [[ "$readiness_unavailable" == 503 && "$(cat "$work/readiness-redis-down.txt")" == *"not ready"* ]] || {
              echo "FAIL: readiness must return HTTP 503 while Redis is unavailable; got $readiness_unavailable" >&2; exit 1;
            }
            echo "PASS: readiness returned HTTP 503 during Redis outage"
          fi
          podman unpause "$redis" >/dev/null
          [[ "$unavailable_status" != 200 && "$unavailable_status" != 204 ]] || {
            echo "FAIL: Logma reported successful lifecycle tick while Redis was paused" >&2; exit 1;
          }
          echo "PASS: lifecycle tick did not report success with Redis unavailable (HTTP $unavailable_status)"
        fi
        podman kill --signal KILL "$redis" >/dev/null
        restarted=false
        for i in $(seq 1 120); do
          new_redis_id=$(podman inspect "$redis" --format '{{.Id}}' 2>/dev/null || true)
          if [[ -n "$new_redis_id" && "$new_redis_id" != "$old_redis_id" ]] &&
             [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]] &&
             [[ "$(redis_cli PING 2>/dev/null)" == PONG ]]; then
            restarted=true
            break
          fi
          sleep .25
        done
        [[ "$restarted" == true ]] || { echo "FAIL: systemd did not restore Redis after SIGKILL" >&2; exit 1; }
        [[ "$(podman inspect "$logma" --format '{{.Id}}')" == "$old_logma_id" ]] ||
          { echo "FAIL: Logma was replaced during Redis crash" >&2; exit 1; }
        function_listing=$(bootstrap_cli --raw FUNCTION LIST)
        [[ -z "$function_listing" ]] ||
          { printf 'FAIL: expected empty Redis Function library after crash, got: %s\n' "$function_listing" >&2; exit 1; }
        echo "PASS: systemd restarted Redis after SIGKILL; Logma container remained unchanged; RAM-only Functions absent"
        if [[ "${COMPOSITION_STRICT_READINESS_MODE:-0}" == 1 ]]; then
          missing_readiness=$(curl -sS --connect-timeout 1 --max-time 4 -o "$work/readiness-functions-missing.txt" -w '%{http_code}' "$readiness_url" 2>/dev/null || true)
          [[ "$missing_readiness" == 503 && "$(cat "$work/readiness-functions-missing.txt")" == *"not ready"* ]] || {
            echo "FAIL: readiness must return HTTP 503 when Redis Functions are absent; got $missing_readiness" >&2; exit 1;
          }
          echo "PASS: readiness returned HTTP 503 with Redis restarted and Functions missing"
        fi
        if [[ "${COMPOSITION_CRASH_WINDOW_MODE:-0}" == 1 ]]; then
          echo "CHECK: Logma lifecycle tick while Redis is reachable but Functions are missing"
          missing_status=$(curl -sS --connect-timeout 1 --max-time 5 -o "$work/missing-functions-response.json" -w '%{http_code}' -X POST -H "X-API-Key: $api_pass" "$window_url" 2>/dev/null || true)
          [[ "$missing_status" != 200 && "$missing_status" != 204 ]] || {
            echo "FAIL: Logma reported successful lifecycle tick without Redis Functions" >&2; exit 1;
          }
          echo "PASS: lifecycle tick did not report success without Redis Functions (HTTP $missing_status)"
          systemctl --user start "$scope-reconcile.timer"
        fi
        if [[ "${COMPOSITION_FUNCTION_RECONCILE_MODE:-0}" == 1 ]]; then
          echo "CHECK: timer-driven Redis Function reconciliation without Logma replacement"
          reconciled=false
          for i in $(seq 1 120); do
            probe=$(redis_cli FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0 2>&1 || true)
            if [[ "$probe" != *"Function not found"* && "$probe" != *"unknown command"* ]] &&
               [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]]; then
              reconciled=true
              break
            fi
            sleep .5
          done
          if [[ "$reconciled" != true ]]; then
            echo "FAIL: Function reconciliation timed out" >&2
            systemctl --user --no-pager -l status "$scope-reconcile.timer" "$scope-reconcile.service" >&2 || true
            systemctl --user show "$scope-reconcile.timer" -p ActiveState -p Result -p LastTriggerUSec -p NextElapseUSecRealtime >&2 || true
            journalctl --user -u "$scope-reconcile.service" -n 100 --no-pager -l >&2 || true
            exit 1
          fi
          [[ "$(podman inspect "$logma" --format '{{.Id}}')" == "$old_logma_id" ]] ||
            { echo "FAIL: Logma replaced during Function reconciliation" >&2; exit 1; }
          if [[ "${COMPOSITION_STRICT_READINESS_MODE:-0}" == 1 ]]; then
            readiness_recovered=$(curl -sS --connect-timeout 2 --max-time 4 -o "$work/readiness-recovered.txt" -w '%{http_code}' "$readiness_url" 2>/dev/null || true)
            [[ "$readiness_recovered" == 200 && "$(cat "$work/readiness-recovered.txt")" == ready ]] || {
              echo "FAIL: readiness did not recover after Function reconciliation; got $readiness_recovered" >&2; exit 1;
            }
            [[ "$(podman inspect "$logma" --format '{{.Id}}')" == "$old_logma_id" ]] || {
              echo "FAIL: Logma restarted while readiness recovered" >&2; exit 1;
            }
            echo "PASS: readiness recovered after reconciliation without Logma restart"
          fi
          if [[ "${COMPOSITION_LIFECYCLE_CRASH_MODE:-0}" == 1 ]]; then
            echo "CHECK: Logma lifecycle operations after Redis crash and Function restoration"
            [[ "$(podman inspect "$logma" --format '{{.Id}}')" == "$old_logma_id" ]] ||
              { echo "FAIL: Logma identity changed before lifecycle recovery" >&2; exit 1; }
            # A pre-crash registration cannot be presumed present in RAM-only Redis.
            # Exercise the existing durable fixture through the HTTP API first.
            # The coordinated restart replaced Logma and its ephemeral host port.
            # Resolve the current published port rather than reusing lifecycle_url.
            port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
            [[ "$port" =~ ^[0-9]+$ ]] ||
              { echo "FAIL: cannot resolve Logma HTTP port after coordinated restart" >&2; exit 1; }
            url="http://127.0.0.1:$port/lifecycle/policies"
            lifecycle_url="http://127.0.0.1:$port/lifecycle"
            readiness_url="$lifecycle_url/readyz"
            echo "CHECK: Logma HTTP transport after Redis Function restoration"
            echo "INFO: Logma container=$old_logma_id port=$port endpoint=$lifecycle_url/"
            recovered_list_status=000
            for attempt in $(seq 1 20); do
              [[ "$(podman inspect "$logma" --format '{{.Id}}' 2>/dev/null || true)" == "$old_logma_id" ]] ||
                { echo "FAIL: Logma container changed during HTTP recovery" >&2; exit 1; }
              recovered_list_status=$(curl -sS --connect-timeout 2 --max-time 5 -o "$work/crash-list.json" -w '%{http_code}' \
                -H "X-API-Key: $api_pass" "$lifecycle_url/" 2>"$work/crash-curl.err" || true)
              [[ "$recovered_list_status" == 200 ]] && break
              # Retry transport failures while retaining the same process identity.
              [[ "$recovered_list_status" == 000 ]] || break
              sleep .5
            done
            if [[ "$recovered_list_status" != 200 ]]; then
              echo "FAIL: lifecycle listing after Redis crash returned HTTP $recovered_list_status" >&2
              cat "$work/crash-curl.err" >&2 || true
              cat "$work/crash-list.json" >&2 || true
              podman inspect "$logma" --format 'Logma state={{json .State}}' >&2 || true
              podman logs --tail 100 "$logma" >&2 || true
              systemctl --user --no-pager -l status "$quadlet_service" >&2 || true
              exit 1
            fi
            if ! grep -Fq "\"deployment_id\":\"$restore_deployment\"" "$work/crash-list.json"; then
              echo "FAIL: durable lifecycle fixture missing after Redis crash; state replay is not qualified" >&2
              cat "$work/crash-list.json" >&2
              exit 1
            fi
            recovered_tick_status=$(curl -sS --max-time 10 -o "$work/crash-tick.json" -w '%{http_code}' \
              -X POST -H "X-API-Key: $api_pass" "$lifecycle_url/tick" || true)
            [[ "$recovered_tick_status" == 200 ]] ||
              { echo "FAIL: lifecycle tick after Redis crash returned HTTP $recovered_tick_status" >&2; cat "$work/crash-tick.json" >&2 || true; exit 1; }
            if [[ "${COMPOSITION_CRASH_WINDOW_MODE:-0}" == 1 ]]; then
              echo "PASS: lifecycle tick recovered after Functions reconciliation, without Logma replacement"
            fi
            recovered_deployment="crash-recovered-$"
            recovered_payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"%s:logma:qualification:shutdown"}' "$recovered_deployment" "$policy_code" "$fatline_scope")
            recovered_register_status=$(curl -sS --max-time 10 -o "$work/crash-register.json" -w '%{http_code}' \
              -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
              --data "$recovered_payload" "$lifecycle_url/" || true)
            [[ "$recovered_register_status" == 201 ]] ||
              { echo "FAIL: lifecycle registration after Redis crash returned HTTP $recovered_register_status" >&2; cat "$work/crash-register.json" >&2 || true; exit 1; }
            grep -Fq '"armed":true' "$work/crash-register.json" ||
              { echo "FAIL: post-crash lifecycle registration was not armed" >&2; exit 1; }
            [[ "$(podman inspect "$logma" --format '{{.Id}}')" == "$old_logma_id" ]] ||
              { echo "FAIL: Logma restarted during lifecycle recovery" >&2; exit 1; }
            echo "PASS: Logma lifecycle listing, tick, and registration recovered without Logma restart"
            if [[ "${COMPOSITION_CRASH_WINDOW_MODE:-0}" == 1 ]]; then
              echo "PASS: crash-window lifecycle tick fail-closed and post-reconciliation recovery"
              echo "Strict HTTP readiness remains unqualified."
            else
              echo "Crash-window fail-closed behavior remains a separate qualification gate."
            fi
          fi
          if [[ "${COMPOSITION_TIMER_STATE_MODE:-0}" == 1 ]]; then
            echo "CHECK: Redis timer keys reconstructed after RAM-only restart"
            recovered_timer=false
            for attempt in $(seq 1 30); do
              recovered_score=$(redis_cli ZSCORE "$timer_key" shutdown:timer 2>/dev/null || true)
              if [[ "$recovered_score" == "$expected_deadline_ms" ]]; then
                recovered_timer=true
                break
              fi
              sleep 1
            done
            if [[ "$recovered_timer" != true ]]; then
              echo "FAIL: lifecycle timer score not restored to original absolute deadline ($expected_deadline_ms)" >&2
              echo "DIAG: observed ZSCORE=${recovered_score:-<empty>} key=$timer_key" >&2
              echo "DIAG: timer key TYPE and ZRANGE" >&2
              redis_cli TYPE "$timer_key" >&2 || true
              redis_cli ZRANGE "$timer_key" 0 -1 WITHSCORES >&2 || true
              echo "DIAG: lifecycle Redis keys" >&2
              redis_cli --scan --pattern "$fatline_scope:logma:lifecycle:*" >&2 || true
              echo "DIAG: Logma reconciliation logs" >&2
              podman logs --tail 160 "$logma" >&2 || true
              echo "DIAG: durable registrations from Logma HTTP" >&2
              curl -fsS --max-time 10 -H "X-API-Key: $api_pass" "$lifecycle_url/" >&2 || true
              exit 1
            fi
            # Existing registrations must retain their original absolute deadline.
            curl -fsS --max-time 10 -H "X-API-Key: $api_pass" "$lifecycle_url/" > "$work/timer-list-after.json"
            python3 - "$work/timer-list-after.json" "$work/timer-deadline.txt" "$restore_deployment" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1]))
regs = obj if isinstance(obj, list) else obj.get("registrations", [])
matches = [r for r in regs if r.get("deployment_id") == sys.argv[3]]
if len(matches) != 1 or matches[0].get("deadline") != open(sys.argv[2]).read():
    raise SystemExit("FAIL: durable lifecycle deadline changed after Redis crash")
PY
            echo "PASS: Redis timer ZSCORE restored to original deadline; durable absolute deadline unchanged"
          fi
          echo "PASS: Function restored and bootstrap identity revoked without Logma restart"
          echo "Logma lifecycle operation recovery and strict readiness remain unqualified."
        else
          echo "Crash baseline passed; automatic Function reconciliation and Logma readiness remain unqualified."
        fi
      fi
      if [[ "${COMPOSITION_LIVE_REDIS_RECOVERY_MODE:-0}" == 1 ]]; then
        echo "CHECK: coordinated recovery after Redis restart with Logma previously active"
        # Explicit orchestration is required: Requires/After alone do not
        # propagate a running Redis service's restart to dependent services.
        systemctl --user stop "$quadlet_service"
        systemctl --user stop "$bootstrap_unit"
        systemctl --user restart "$redis_quadlet_service"
        [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]]
        for i in $(seq 1 60); do
          [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
          sleep .25
        done
        [[ "$(redis_cli PING)" == PONG ]]
        # A fresh Redis instance must have no Functions; capture evidence if not.
        function_listing=$(bootstrap_cli --raw FUNCTION LIST)
        [[ "$function_listing" != *"NOPERM"* && "$function_listing" != *"WRONGPASS"* && "$function_listing" != *"NOAUTH"* ]] || {
          echo "FAIL: elevated bootstrap principal could not inspect fresh Redis Functions" >&2
          printf '%s\n' "$function_listing" >&2
          exit 1
        }
        if [[ -n "$function_listing" ]]; then
          echo "FAIL: Redis Functions present after restart; diagnosing process replacement and bootstrap activation" >&2
          printf 'Redis Function listing:\n%s\n' "$function_listing" >&2
          systemctl --user show "$redis_quadlet_service" -p InvocationID -p ActiveEnterTimestamp -p MainPID >&2
          systemctl --user show "$bootstrap_unit" -p ActiveState -p InvocationID -p ActiveEnterTimestamp -p Result >&2
          podman inspect "$redis" --format 'Redis container={{.Id}} started={{.State.StartedAt}}' >&2 || true
          redis_cli INFO server | grep -E '^(run_id|uptime_in_seconds):' >&2 || true
          exit 1
        fi
        echo "PASS: Redis restart erased Functions; Logma stopped before re-bootstrap"
        systemctl --user start "$quadlet_service"
        for unit in "$redis_quadlet_service" "$nginx_quadlet_service" "$bootstrap_unit" "$quadlet_service"; do
          [[ "$(systemctl --user is-active "$unit")" == active ]] || { echo "Recovery unit not active: $unit" >&2; exit 1; }
        done
        [[ "$(redis_cli FCALL dashxd_ratelimit_lifecycle_timer_arm_absolute_v1 0 2>&1)" != *"Function not found"* ]]
        [[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]]
        port=$(podman port "$logma" 8080/tcp | sed -n '1s/.*://p')
        [[ "$port" =~ ^[0-9]+$ ]]
        status=""
        for i in $(seq 1 60); do
          status=$(curl -sS --max-time 2 -o /dev/null -w '%{http_code}' -H "X-API-Key: $api_pass" "http://127.0.0.1:$port/lifecycle/policies" 2>/dev/null || true)
          [[ "$status" == 200 ]] && break
          sleep .25
        done
        [[ "$status" == 200 ]] || { echo "Logma HTTP unavailable after Redis recovery: $status" >&2; exit 1; }
        echo "PASS: coordinated Redis restart restored Functions and Logma HTTP with bootstrap identity revoked"
        echo "Operator-coordinated live Redis recovery passed; automatic restart propagation and production ACL remain unqualified."
      else
        echo "Coordinated cold restart gate passed; live Redis restart and production ACL remain unqualified."
      fi
    elif [[ "$bootstrap_unit_mode" == 1 ]]; then
      echo "Bootstrap oneshot prerequisite gate passed; coordinated restart and production ACL remain unqualified."
    else
      echo "Three-component Quadlet restart gate passed; cold-start ordering and production ACL remain unqualified."
    fi
  else
    echo "Logma Quadlet gate passed; remaining components and production ACL remain unqualified."
  fi
else
  echo "Fatline lifecycle composition gate passed; full production ACL and systemd-user Quadlet restart remain unqualified."
fi
