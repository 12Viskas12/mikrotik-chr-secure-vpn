#!/usr/bin/env bash
# Generate WireGuard key pairs and a pre-shared key into var/keys (git-ignored, mode 600).
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need wg

mkdir -p "$KEYS"; chmod 700 "$KEYS"
umask 077
for side in chr rgw; do
  if [[ -f "$KEYS/$side.key" ]]; then
    log "key for $side already exists - keeping it"
  else
    wg genkey | tee "$KEYS/$side.key" | wg pubkey > "$KEYS/$side.pub"
    log "generated key pair: $side"
  fi
done
[[ -f "$KEYS/psk.key" ]] || { wg genpsk > "$KEYS/psk.key"; log "generated pre-shared key"; }
