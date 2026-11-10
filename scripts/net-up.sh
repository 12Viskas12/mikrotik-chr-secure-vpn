#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
[[ $EUID -eq 0 ]] || die "net-up.sh must run as root (lab.sh calls it with sudo)"
need ip nft dnsmasq sysctl
[[ -f "$REND/host.nft" ]] || die "run ./lab.sh render first"

mkbr() {
  local br=$1
  ip link show "$br" >/dev/null 2>&1 || ip link add "$br" type bridge stp_state 0
  sysctl -qw "net.ipv6.conf.$br.disable_ipv6=1"
  ip link set "$br" up
  command -v nmcli >/dev/null 2>&1 && nmcli device set "$br" managed no >/dev/null 2>&1 || true
}
mktap() {
  local tap=$1 br=$2 iso=${3:-no}
  ip link show "$tap" >/dev/null 2>&1 || ip tuntap add dev "$tap" mode tap user "$LAB_USER"
  ip link set "$tap" master "$br"
  sysctl -qw "net.ipv6.conf.$tap.disable_ipv6=1" 2>/dev/null || true
  if [[ $iso == yes && $CLIENT_ISOLATION == yes ]]; then ip link set "$tap" type bridge_slave isolated on; fi
  ip link set "$tap" up
  command -v nmcli >/dev/null 2>&1 && nmcli device set "$tap" managed no >/dev/null 2>&1 || true
}

log "creating bridges"
for b in "$MGMT_BR" "$WAN_BR" "$LAN_BR" "$REMOTE_BR"; do mkbr "$b"; done
ip addr replace "$HOST_MGMT_IP/24" dev "$MGMT_BR"
ip addr replace "$HOST_WAN_IP/24" dev "$WAN_BR"

log "creating TAP ports"
mktap tap-chr-mgmt "$MGMT_BR"
mktap tap-chr-wan "$WAN_BR"
mktap tap-chr-lan "$LAN_BR"
mktap tap-c1 "$LAN_BR" yes
mktap tap-c2 "$LAN_BR" yes
mktap tap-rgw-wan "$WAN_BR"
mktap tap-rgw-remote "$REMOTE_BR"
mktap tap-rsrv "$REMOTE_BR"

mkdir -p "$RUN"
if [[ ! -f "$RUN/ip_forward.prev" ]]; then cat /proc/sys/net/ipv4/ip_forward > "$RUN/ip_forward.prev"; fi
sysctl -qw net.ipv4.ip_forward=1

log "loading host nftables (labfw, labnat, labl2)"
nft -f "$REND/host.nft"

log "starting dnsmasq (DNS for the lab + static DHCP lease for the CHR mgmt port)"
if [[ -f "$RUN/dnsmasq.pid" ]] && kill -0 "$(cat "$RUN/dnsmasq.pid")" 2>/dev/null; then
  kill "$(cat "$RUN/dnsmasq.pid")"; sleep 1
fi
dnsmasq --conf-file="$REND/dnsmasq.conf"
log "network is up"
