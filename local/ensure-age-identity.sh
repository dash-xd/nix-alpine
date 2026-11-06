#!/usr/bin/env bash
set -euo pipefail

dir=/run/secrets/age
key="$dir/keys.txt"
test -d "$dir" && test -w "$dir" || { echo 'AGE_IDENTITY=FAIL reason=volume-not-writable' >&2; exit 1; }
if [[ -L "$key" ]]; then
  echo 'AGE_IDENTITY=FAIL reason=symlink' >&2; exit 1
fi
if [[ ! -e "$key" ]]; then
  # Refuse identity replacement if ciphertext already exists.
  if [[ -e /workspaces/.private/sops/ghxd.enc.json ]]; then
    echo 'AGE_IDENTITY=FAIL reason=existing-ciphertext-without-key' >&2; exit 1
  fi
  umask 077
  age-keygen -o "$key" >/dev/null
  echo 'AGE_IDENTITY=CREATED'
else
  echo 'AGE_IDENTITY=REUSED'
fi
chmod 0600 "$key"
test -f "$key" && test -r "$key" || exit 1
recipient="$(age-keygen -y "$key")"
[[ "$recipient" == age1* ]] || exit 1
printf 'AGE_RECIPIENT=%s\n' "$recipient"
printf 'AGE_IDENTITY_VERIFIED=PASS key_mode=0600\n'
