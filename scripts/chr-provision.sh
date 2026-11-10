#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need sshpass ssh scp
require_password
[[ -f "$REND/chr-lab.rsc" ]] || die "run ./lab.sh render first"

# shellcheck disable=SC2086
ssh_pw() { local pw=$1; shift; sshpass -p "$pw" ssh $SSH_OPTS_STR "admin@$CHR_MGMT_IP" "$@"; }

log "waiting for CHR SSH on $CHR_MGMT_IP (first boot takes ~30-60 s)"
pw=""
for i in $(seq 90); do
  if ssh_pw "" '/system identity print' >/dev/null 2>&1; then pw=""; break; fi
  if ssh_pw "$ADMIN_PASSWORD" '/system identity print' >/dev/null 2>&1; then pw="$ADMIN_PASSWORD"; break; fi
  sleep 2
  [[ $i -lt 90 ]] || die "CHR did not become reachable over SSH"
done
if [[ -n "$pw" ]]; then
  warn "CHR already uses the lab password - it was provisioned before. Use './lab.sh reset-chr' for a clean slate."
  exit 0
fi

log "uploading and importing chr-lab.rsc"
# shellcheck disable=SC2086
if ! sshpass -p "" scp $SSH_OPTS_STR "$REND/chr-lab.rsc" "admin@$CHR_MGMT_IP:chr-lab.rsc" 2>/dev/null; then
  # shellcheck disable=SC2086
  sshpass -p "" scp -O $SSH_OPTS_STR "$REND/chr-lab.rsc" "admin@$CHR_MGMT_IP:chr-lab.rsc"
fi
out="$(ssh_pw "" '/import file-name=chr-lab.rsc' 2>&1 || true)"
echo "$out" | sed 's/^/  | /'
if echo "$out" | grep -qiE 'failure|error|invalid|bad command|no such'; then
  die "RouterOS reported errors during import - see output above"
fi
sleep 2
chr_ssh '/system identity print' >/dev/null || die "cannot log in with the new password after import"
log "CHR provisioned; admin password set, services locked down"
