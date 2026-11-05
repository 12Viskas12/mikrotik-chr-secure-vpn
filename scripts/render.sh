#!/usr/bin/env bash
# Render all templates into var/render.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need python3 openssl

require_password
load_keys
[[ -r "$SSH_PUBKEY_FILE" ]] || die "SSH public key not found: $SSH_PUBKEY_FILE (create one: ssh-keygen -t ed25519)"
[[ -n "$UPLINK_IFACE" ]] || die "cannot detect the uplink interface - set UPLINK_IFACE in lab.env"

SSH_PUBKEY_CONTENT="$(cat "$SSH_PUBKEY_FILE")"
VM_PASS_HASH="$(openssl passwd -6 "$ADMIN_PASSWORD")"
export SSH_PUBKEY_CONTENT VM_PASS_HASH

r() { python3 -I "$ROOT/scripts/render.py" "$ROOT/$1" "$REND/$2"; }

mkdir -p "$REND"
r chr/chr-lab.rsc.tpl chr-lab.rsc
r host/dnsmasq.conf.tpl dnsmasq.conf
r host/host.nft.tpl host.nft
for vm in rgw rsrv client1 client2; do
  for f in user-data network-config; do
    r "cloud-init/$vm/$f.tpl" "$vm/$f"
  done
done
log "rendered configs into var/render (contain secrets - never commit)"
