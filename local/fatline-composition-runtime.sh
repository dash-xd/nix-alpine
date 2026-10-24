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
bootstrap="$scope-bootstrap"
quadlet_mode=${COMPOSITION_QUADLET_MODE:-0}
redis_quadlet_mode=${COMPOSITION_REDIS_QUADLET_MODE:-0}
nginx_quadlet_mode=${COMPOSITION_NGINX_QUADLET_MODE:-0}
cold_start_mode=${COMPOSITION_COLD_START_MODE:-0}
bootstrap_unit_mode=${COMPOSITION_BOOTSTRAP_UNIT_MODE:-0}
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
  podman rm -f "$bootstrap" "$logma" "$nginx" "$redis" >/dev/null 2>&1 || true
  podman network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
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
chmod 644 "$work/redis.conf" "$work/nginx.conf"
redis_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
api_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
# Restrict keyspace; lifecycle runtime's complete command-level ACL remains
# a separate qualification gate. Do not equate this with production ACL approval.
bootstrap_pass=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
printf 'user default off\nuser logma on >%s ~logma:* ~active_subscriptions:* ~subscription_groups:* +@read +@write +@pubsub +ping -@admin -@dangerous +fcall +time\nuser bootstrap on >%s ~* &* +@all\n' "$redis_pass" "$bootstrap_pass" > "$work/users.acl"
chmod 644 "$work/users.acl"
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
    printf 'Requires=%s\nAfter=%s\n' "$redis_quadlet_service" "$redis_quadlet_service" >> "$nginx_quadlet_file"
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
Requires=$nginx_quadlet_service
After=$nginx_quadlet_service

[Service]
Type=oneshot
ExecStart=/usr/bin/bash $work/bootstrap-entry.sh
RemainAfterExit=yes
TimeoutStartSec=90
EOF
  chmod 600 "$bootstrap_unit_file"
  systemctl --user daemon-reload
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
  bootstrap_functions
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
[[ "$(redis_cli SET logma:qualification ok)" == OK ]]
[[ "$(redis_cli GET logma:qualification)" == ok ]]
[[ "$(redis_cli SET foreign:denied value)" == *NOPERM* ]]
[[ "$(redis_cli ACL LIST)" == *NOPERM* ]]
echo "PASS: authenticated TCP -> Nginx -> Unix Redis, key isolation, admin denial"
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
if [[ "$redis_quadlet_mode" == 1 && "$bootstrap_unit_mode" != 1 ]]; then
  echo "CHECK: systemd-user Redis Quadlet restart"
  systemctl --user restart "$redis_quadlet_service"
  [[ "$(systemctl --user is-active "$redis_quadlet_service")" == active ]]
  for i in $(seq 1 60); do
    [[ "$(redis_cli PING 2>/dev/null)" == PONG ]] && break
    sleep .25
  done
  [[ "$(redis_cli PING)" == PONG ]] || { echo "Redis did not recover through Nginx" >&2; false; }
  [[ "$(redis_cli SET logma:after-restart ok)" == OK ]]
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
    printf 'Requires=%s\nAfter=%s\n' "$bootstrap_unit" "$bootstrap_unit" >> "$quadlet_file"
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
deployment="qualification-$"
# Use a policy code returned by the running Logma build; do not guess enum strings.
policy_code=$(curl -fsS --max-time 5 -H "X-API-Key: $api_pass" "$url" | python3 -c 'import json,sys; p=json.load(sys.stdin); assert isinstance(p,list) and p, "empty lifecycle policy catalog"; x=next((x for x in p if x.get("duration")=="720h0m0s"),p[-1]); assert str(x.get("policy_code","")).isdigit(), "missing policy code"; print(x["policy_code"])')
payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"logma:qualification:shutdown"}' "$deployment" "$policy_code")
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
# Leave a durable registration in the mounted state directory across restart.
restore_deployment="restore-$"
restore_payload=$(printf '{"deployment_id":"%s","policy_code":"%s","shutdown_channel":"logma:qualification:shutdown"}' "$restore_deployment" "$policy_code")
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
    grep -Fq "$nginx_quadlet_service" "$work/logma-dependencies"
    grep -Fq "$redis_quadlet_service" "$work/nginx-dependencies"
    echo "PASS: generated systemd dependency edges Logma -> Nginx -> Redis"
  fi
  if [[ "$redis_quadlet_mode" == 1 && "$nginx_quadlet_mode" == 1 ]]; then
    if [[ "$bootstrap_unit_mode" == 1 ]]; then
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
