#!/usr/bin/env bash
# Render Agni's tracked ACL policy with disposable qualification credentials.
# Credentials stay in the test harness's private temporary directory.
set -Eeuo pipefail
[[ $# == 7 ]] || { echo "usage: $0 OUT LOGMA_PASSWORD SUBSCRIBER_PASSWORD BOOTSTRAP_PASSWORD SKYMILL_PASSWORD SCOPE SKYMILL_STREAM" >&2; exit 2; }
out=$1 logma_pass=$2 subscriber_pass=$3 bootstrap_pass=$4 skymill_pass=$5 scope=$6 stream=$7
[[ "$scope" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "invalid Fatline scope" >&2; exit 2; }
[[ "$stream" == "$scope:skymill:stream:github.webhooks" ]] || { echo "Skymill stream does not match Fatline scope" >&2; exit 2; }
agni_source=${COMPOSITION_AGNI_SOURCE:?COMPOSITION_AGNI_SOURCE must point to the pinned Agni checkout}
policy="$agni_source/local/fatline/acl-policy.json"
renderer="$agni_source/local/fatline/scripts/render-users-acl.py"
credentials="${out}.credentials"
mkdir -m 700 "$credentials"
printf '%s\n' "$logma_pass" > "$credentials/logma"
printf '%s\n' "$skymill_pass" > "$credentials/skymill"
printf '%s\n' "$bootstrap_pass" > "$credentials/bootstrap"
chmod 600 "$credentials"/*
python3 "$renderer" "$policy" "$credentials" "$out" > "${out}.policy-digest"
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["scope"])' "$policy")" == "$scope" ]]
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["skymillStream"])' "$policy")" == "$stream" ]]
subscriber_hash=$(printf '%s' "$subscriber_pass" | sha256sum | awk '{print $1}')
printf 'user subscriber on #%s -@all resetkeys resetchannels &%s:logma:qualification:dispatch:* +subscribe +ping\n' \
  "$subscriber_hash" "$scope" >> "$out"
cat "${out}.policy-digest"
cat "${out}.evidence.json"
