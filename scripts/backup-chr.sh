#!/usr/bin/env bash
# Export the live CHR configuration (RouterOS hides secrets in /export by default) and sanitise it.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need sshpass ssh
mkdir -p "$VAR/backups" "$ROOT/docs"
ts="$(date +%Y%m%d-%H%M%S)"
chr_ssh '/export terse' > "$VAR/backups/chr-$ts.rsc"
"$ROOT/scripts/sanitize.sh" < "$VAR/backups/chr-$ts.rsc" > "$ROOT/docs/chr-export.rsc"
chr_ssh '/ip firewall filter print terse without-paging' | "$ROOT/scripts/sanitize.sh" > "$ROOT/docs/chr-firewall-rules.txt"
chr_ssh '/ip route print detail without-paging' | "$ROOT/scripts/sanitize.sh" > "$ROOT/docs/chr-routing-table.txt"
log "raw export: var/backups/chr-$ts.rsc (git-ignored); sanitised: docs/chr-export.rsc, docs/chr-firewall-rules.txt, docs/chr-routing-table.txt"
