#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
[[ $EUID -eq 0 ]] || die "net-down.sh must run as root (lab.sh calls it with sudo)"

[[ -f "$RUN/dnsmasq.pid" ]] && kill "$(cat "$RUN/dnsmasq.pid")" 2>/dev/null; rm -f "$RUN/dnsmasq.pid"
for ns in outside mgmtrogue rogue; do ip netns del "$ns" 2>/dev/null; done
nft delete table inet labfw 2>/dev/null
nft delete table ip labnat 2>/dev/null
nft delete table bridge labl2 2>/dev/null
for t in tap-chr-mgmt tap-chr-wan tap-chr-lan tap-c1 tap-c2 tap-rgw-wan tap-rgw-remote tap-rsrv; do ip link del "$t" 2>/dev/null; done
for b in "$MGMT_BR" "$WAN_BR" "$LAN_BR" "$REMOTE_BR"; do ip link del "$b" 2>/dev/null; done
if [[ -f "$RUN/ip_forward.prev" ]]; then sysctl -qw "net.ipv4.ip_forward=$(cat "$RUN/ip_forward.prev")"; rm -f "$RUN/ip_forward.prev"; fi
log "network removed, ip_forward restored"
