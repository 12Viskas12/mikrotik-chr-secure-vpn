#!/usr/bin/env bash
# Generate WireGuard + nftables config for a real server into var/remote-gateway/.
# usage: remote-gateway-config.sh PUBLIC_IF LAN_IF SERVER_IP
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
load_keys
PUB_IF=${1:?public interface}; LAN_IF=${2:?lan interface}; SRV=${3:-$SRV_IP}
out="$VAR/remote-gateway"; mkdir -p "$out"; umask 077

cat > "$out/wg0.conf" <<CONF
[Interface]
Address = $RGW_VPN_IP/24
ListenPort = $WG_PORT
PrivateKey = $RGW_WG_PRIVKEY

[Peer]
PublicKey = $CHR_WG_PUBKEY
PresharedKey = $WG_PSK
AllowedIPs = $CHR_VPN_IP/32, $LAN_NET
CONF

cat > "$out/nftables-rgw.conf" <<CONF
#!/usr/sbin/nft -f
table inet rgw {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ct state invalid drop
    iifname "$PUB_IF" udp dport $WG_PORT accept
    iifname "$PUB_IF" tcp dport 22 accept   # tighten to your admin IPs!
    iifname "wg0" icmp type echo-request accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    iifname "wg0" oifname "$LAN_IF" ip saddr $LAN_NET ip daddr $SRV tcp dport { 22, 443 } accept
    iifname "wg0" oifname "$LAN_IF" ip saddr $LAN_NET ip daddr $SRV icmp type echo-request accept
  }
}
CONF
log "written to var/remote-gateway/: wg0.conf (-> /etc/wireguard/wg0.conf, chmod 600) and nftables-rgw.conf"
log "on the server: sysctl -w net.ipv4.ip_forward=1; ensure $SRV routes $LAN_NET via this gateway; wg-quick up wg0"
log "on this lab: set WG_ENDPOINT_HOST=<server public IP> in lab.env, then ./lab.sh render && ./lab.sh reset-chr"
