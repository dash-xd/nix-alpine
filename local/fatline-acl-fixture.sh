#!/usr/bin/env bash
# Compile a disposable ACL for Fatline integration from explicit package-owned contracts.
# This is NOT a production credential provisioner. All credentials stay in the
# test harness's private temporary directory.
set -Eeuo pipefail
[[ $# == 4 ]] || { echo "usage: $0 OUT LOGMA_PASSWORD SUBSCRIBER_PASSWORD BOOTSTRAP_PASSWORD" >&2; exit 2; }
out=$1 logma_pass=$2 subscriber_pass=$3 bootstrap_pass=$4
for secret in "$logma_pass" "$subscriber_pass" "$bootstrap_pass"; do
  [[ $secret =~ ^[0-9a-f]{48}$ ]] || { echo "ACL passwords must be 48 lowercase hex characters" >&2; exit 2; }
done
# Ratelimiter internal/profiledef/profile.go TimerRuntimeACLCommands(lifecycle):
# fcall type time zadd hset hexists zrangebyscore hget publish zrem hdel
# Logma itself also needs SET/GET and lifecycle read operations; do not
# widen to @read/@write/@pubsub. The command union is provisional pending
# tracing all Logma runtime paths. The five runtime gates prove the subset
# they exercise, not every production API path.
# Redis ACL subcommands are denied unless explicitly granted.
logma_commands=(ping hello client select set get del type time zadd hset hexists zrangebyscore hget publish zrem hdel fcall zscore zrange hgetall exists)
logma_rules=()
for cmd in "${logma_commands[@]}"; do logma_rules+=("+$cmd"); done
{
  printf 'user default off\n'
  printf 'user logma on >%s resetkeys ~logma:* ~active_subscriptions:* ~subscription_groups:* resetchannels &logma:qualification:* %s\n' "$logma_pass" "${logma_rules[*]}"
  printf 'user subscriber on >%s resetkeys resetchannels &logma:qualification:dispatch:* +subscribe +ping\n' "$subscriber_pass"
  printf 'user bootstrap on >%s ~* &* +@all\n' "$bootstrap_pass"
} > "$out"
chmod 600 "$out"
