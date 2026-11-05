#!/usr/bin/env bash
# Shared constants and helpers (source it).
# shellcheck disable=SC2034

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$_LIB_DIR/.." && pwd)"

set -a
# shellcheck disable=SC1091
[[ -f "$ROOT/lab.env" ]] && . "$ROOT/lab.env"

LAB_USER="${LAB_USER:-${SUDO_USER:-$(id -un)}}"
_LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$_LAB_HOME/.ssh/id_ed25519.pub}"
CHR_VERSION="${CHR_VERSION:-latest}"
DEBIAN_IMG_URL="${DEBIAN_IMG_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2}"
CLIENT_ISOLATION="${CLIENT_ISOLATION:-yes}"
UPLINK_IFACE="${UPLINK_IFACE:-$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
if [[ -s /run/systemd/resolve/resolv.conf ]]; then RESOLV_FILE=/run/systemd/resolve/resolv.conf; else RESOLV_FILE=/etc/resolv.conf; fi

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
UPSTREAM_DNS="${UPSTREAM_DNS:-$(awk '/^nameserver/ && $2 !~ /^127\./ && $2 !~ /:/ {print $2; exit}' "$RESOLV_FILE" 2>/dev/null)}"
UPSTREAM_DNS="${UPSTREAM_DNS:-1.1.1.1}"
HOST_WAN_NET=192.168.100.0/24

# local directories
VAR="$ROOT/var"
IMG="$VAR/images"
VMD="$VAR/vm"
RUN="$VAR/run"
REND="$VAR/render"
KEYS="$VAR/keys"
SEED="$VAR/seed"

# virtual bridges (host side)
MGMT_BR=br-mgmt     # host <-> CHR management only
WAN_BR=br-wan       # CHR WAN + simulated Internet; NAT to the physical uplink
LAN_BR=br-lan       # isolated user segment, no host IP
REMOTE_BR=br-remote # isolated segment behind the simulated remote VPN gateway

# addressing
CHR_NAME=chr-lab
HOST_MGMT_IP=172.31.0.1
CHR_MGMT_IP=172.31.0.2
HOST_WAN_IP=192.168.100.1
CHR_WAN_IP=192.168.100.2
RGW_WAN_IP=192.168.100.10
LAN_NET=10.50.0.0/24
CHR_LAN_IP=10.50.0.1
C1_IP=10.50.0.10
C2_IP=10.50.0.11
DHCP_POOL=10.50.0.100-10.50.0.200
REMOTE_NET=10.60.0.0/24
RGW_LAN_IP=10.60.0.1
SRV_IP=10.60.0.10
DECOY_IP=10.60.0.20
VPN_NET=10.200.0.0/24
CHR_VPN_IP=10.200.0.2
RGW_VPN_IP=10.200.0.1
WG_PORT="${WG_PORT:-51820}"
CHR_WG_LISTEN_PORT=13231
WG_ENDPOINT_HOST="${WG_ENDPOINT_HOST:-$RGW_WAN_IP}"

# MAC addresses
CHR_MAC_MGMT=52:54:00:00:01:01
CHR_MAC_WAN=52:54:00:00:01:02
CHR_MAC_LAN=52:54:00:00:01:03
RGW_MAC_WAN=52:54:00:00:02:01
RGW_MAC_REMOTE=52:54:00:00:02:02
RSRV_MAC=52:54:00:00:03:01
C1_MAC=52:54:00:00:04:01
C2_MAC=52:54:00:00:04:02

SSH_OPTS_STR="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -o PreferredAuthentications=password -o PubkeyAuthentication=no"
set +a

# helpers
log()  { printf '\033[1;34m[lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }
need() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c (run ./lab.sh deps)"; done; }

require_password() {
  [[ -n "$ADMIN_PASSWORD" ]] || die "ADMIN_PASSWORD is empty - copy lab.env.example to lab.env and set it"
  [[ "$ADMIN_PASSWORD" =~ ^[A-Za-z0-9]+$ ]] || die "ADMIN_PASSWORD must contain letters and digits only"
}

load_keys() {
  [[ -f "$KEYS/chr.key" ]] || die "WireGuard keys missing - run ./lab.sh keys"
  CHR_WG_PRIVKEY="$(cat "$KEYS/chr.key")"; CHR_WG_PUBKEY="$(cat "$KEYS/chr.pub")"
  RGW_WG_PRIVKEY="$(cat "$KEYS/rgw.key")"; RGW_WG_PUBKEY="$(cat "$KEYS/rgw.pub")"
  WG_PSK="$(cat "$KEYS/psk.key")"
  export CHR_WG_PRIVKEY CHR_WG_PUBKEY RGW_WG_PRIVKEY RGW_WG_PUBKEY WG_PSK
}

# VM helpers
vm_running() { local p="$RUN/$1.pid"; [[ -f "$p" ]] && kill -0 "$(cat "$p")" 2>/dev/null; }
vm_stop() {
  local n=$1 i
  if vm_running "$n"; then
    kill "$(cat "$RUN/$n.pid")" 2>/dev/null || true
    for i in $(seq 20); do vm_running "$n" || break; sleep 0.5; done
    vm_running "$n" && kill -9 "$(cat "$RUN/$n.pid")" 2>/dev/null || true
  fi
  rm -f "$RUN/$n.pid" "$RUN/$n.qga" "$RUN/$n.console"
}
# vm_exec VM 'cmd' [timeout]: run in the guest via the QEMU guest agent
vm_exec() { python3 -I "$ROOT/scripts/qga.py" "$RUN/$1.qga" "$2" "${3:-60}"; }

# chr_ssh 'RouterOS command'
chr_ssh() {
  # shellcheck disable=SC2086
  sshpass -p "$ADMIN_PASSWORD" ssh $SSH_OPTS_STR "admin@$CHR_MGMT_IP" "$@"
}
