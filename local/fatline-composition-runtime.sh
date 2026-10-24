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
cleanup() {
  podman rm -f "$bootstrap" "$logma" "$nginx" "$redis" >/dev/null 2>&1 || true
  podman network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
}
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
podman run -d --name "$redis" --network none --user 65534:65534 \
  --read-only --cap-drop ALL --security-opt no-new-privileges \
  -v "$socket:/run/redis" \
  -v "$work/redis.conf:/etc/redis/redis.conf:ro" \
  -v "$work/users.acl:/etc/redis/users.acl:ro" \
  "$redis_image" >/dev/null
for i in $(seq 1 60); do [[ -S "$socket/redis.sock" ]] && break; sleep .25; done
[[ -S "$socket/redis.sock" ]] || { podman logs "$redis"; exit 1; }
podman run -d --name "$nginx" --network "$net" --network-alias redis-proxy \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=4m,mode=1777 \
  -v "$socket:/run/redis" -v "$work/nginx.conf:/etc/nginx/nginx.conf:ro" \
  "$nginx_image" >/dev/null
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
  exit 1
fi
podman rm -f "$bootstrap" >/dev/null
[[ "$(bootstrap_cli ACL SETUSER bootstrap off)" == OK ]] || { echo "Failed to revoke bootstrap identity" >&2; exit 1; }
[[ "$(bootstrap_cli PING 2>&1)" == *WRONGPASS* ]] || { echo "Bootstrap identity still authenticates" >&2; exit 1; }
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
mkdir -m 777 "$work/lifecycle-state"
podman run -d --name "$logma" --network "$net" \
  --user 65534:65534 --read-only --cap-drop ALL --security-opt no-new-privileges \
  -v "$work/lifecycle-state:/var/lib/logma/lifecycle" \
  -e LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle \
  -e REDIS_USERNAME=logma -e REDISCLI_AUTH="$redis_pass" -e API_KEY="$api_pass" \
  -p 127.0.0.1::8080 "$logma_image" >/dev/null
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
restore_status=$(curl -sS --max-time 10 -o "$work/restore-register.json" -w '%{http_code}' \
  -H "X-API-Key: $api_pass" -H 'Content-Type: application/json' \
  --data "$restore_payload" "$lifecycle_url/")
[[ "$restore_status" == 201 ]] || { echo "Restore fixture registration failed: HTTP $restore_status" >&2; cat "$work/restore-register.json" >&2; exit 1; }
grep -Fq '"armed":true' "$work/restore-register.json" || { echo "Restore fixture was not armed" >&2; exit 1; }
logma_id=$(podman image inspect "$logma_image" --format '{{.Id}}')
[[ "$(podman inspect "$logma" --format '{{.Image}}')" == "$logma_id" ]]
podman restart "$logma" >/dev/null
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
echo "Fatline lifecycle composition gate passed; full production ACL and systemd-user Quadlet restart remain unqualified."
