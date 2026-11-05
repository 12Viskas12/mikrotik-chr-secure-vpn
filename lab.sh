#!/usr/bin/env bash
# MikroTik CHR + WireGuard lab. Run as a normal user.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh
[[ $EUID -ne 0 ]] || die "run ./lab.sh as a normal user, not root (QEMU runs unprivileged; sudo is called when needed)"

wait_vm() {  # wait_vm NAME -> guest agent answers and cloud-init finished
  local n=$1 i
  log "waiting for $n (first boot installs packages, up to ~5 min)"
  for i in $(seq 150); do
    vm_exec "$n" true 10 >/dev/null 2>&1 && break
    sleep 4; [[ $i -lt 150 ]] || die "$n: guest agent never came up"
  done
  vm_exec "$n" 'cloud-init status --wait' 600 >/dev/null 2>&1 || warn "$n: cloud-init reported errors (check: ./lab.sh shell $n 'cloud-init status --long')"
}

cmd_deps() {
  if command -v pacman >/dev/null; then
    $SUDO pacman -S --needed --noconfirm qemu-base qemu-system-x86 qemu-img nftables dnsmasq iproute2 wireguard-tools \
      openssh sshpass libisoburn socat nmap traceroute tcpdump wireshark-cli curl unzip bind jq python openssl iputils
  elif command -v apt-get >/dev/null; then
    $SUDO apt-get update
    $SUDO apt-get install -y qemu-system-x86 qemu-utils nftables dnsmasq iproute2 wireguard-tools openssh-client sshpass \
      xorriso socat nmap traceroute tcpdump tshark curl unzip dnsutils jq python3 openssl iputils-ping
  else
    die "unsupported distro - install the packages listed in docs/setup-arch.md manually"
  fi
  if [[ ! -w /dev/kvm ]]; then warn "no access to /dev/kvm: run 'sudo usermod -aG kvm $USER' and re-login"; fi
  log "dependencies ready"
}

cmd_up() {
  require_password
  mkdir -p "$VAR" "$RUN" "$VMD"
  [[ -w /dev/kvm ]] || warn "KVM not available - everything will be very slow"
  scripts/gen-keys.sh
  scripts/render.sh
  scripts/fetch-images.sh
  scripts/vms.sh create
  log "building the network (needs sudo)"
  $SUDO env "SUDO_USER=$(id -un)" bash scripts/net-up.sh
  scripts/vms.sh start rgw
  scripts/vms.sh start chr
  scripts/chr-provision.sh
  wait_vm rgw
  scripts/vms.sh start rsrv
  scripts/vms.sh start client1
  scripts/vms.sh start client2
  wait_vm rsrv; wait_vm client1; wait_vm client2
  log "waiting for the VPN to come up (netwatch enables the server route)"
  for _ in $(seq 40); do
    vm_exec client1 'nc -z -w2 10.60.0.10 22' 10 >/dev/null 2>&1 && { log "LAB READY: client1 -> 10.60.0.10:22 works through the tunnel"; return; }
    sleep 3
  done
  warn "lab started but the server is not reachable yet - run ./lab.sh status and ./lab.sh test"
}

cmd_down() {
  scripts/vms.sh stop all || true
  $SUDO env "SUDO_USER=$(id -un)" bash scripts/net-down.sh
}

cmd_status() {
  scripts/vms.sh status
  echo "--- CHR"; chr_ssh '/interface wireguard peers print; /ip route print where dst-address~"10.60"' 2>/dev/null || echo "(CHR not reachable)"
}

cmd_console() {
  local n=${1:?usage: ./lab.sh console chr|rgw|rsrv|client1|client2}
  log "serial console of $n (Ctrl-] to leave)"
  socat -,rawer,escape=0x1d "UNIX-CONNECT:$RUN/$n.console"
}

cmd_shell() {  # run a command inside a VM through the guest agent
  local n=${1:?usage: ./lab.sh shell VM 'command'}; shift
  vm_exec "$n" "$*" 120
}

cmd_chr() {  # run a RouterOS command on the CHR (password from lab.env, no prompt)
  [[ $# -gt 0 ]] || die "usage: ./lab.sh chr '/ip route print'"
  chr_ssh "$*"
}

cmd_reset_chr() {
  vm_stop chr
  rm -f "$VMD/chr.qcow2"
  scripts/vms.sh create
  scripts/vms.sh start chr
  scripts/chr-provision.sh
}

cmd_clean() { cmd_down || true; rm -rf "$VAR"; log "removed var/ (images, disks, keys, rendered configs)"; }

case "${1:-help}" in
  deps)      cmd_deps ;;
  keys)      scripts/gen-keys.sh ;;
  render)    scripts/render.sh ;;
  up)        cmd_up ;;
  down)      cmd_down ;;
  status)    cmd_status ;;
  console)   shift; cmd_console "$@" ;;
  shell)     shift; cmd_shell "$@" ;;
  chr)       shift; cmd_chr "$@" ;;
  test)      scripts/run-tests.sh ;;
  backup)    scripts/backup-chr.sh ;;
  reset-chr) cmd_reset_chr ;;
  clean)     cmd_clean ;;
  *) cat <<USAGE
usage: ./lab.sh <command>
  deps       install host packages (Arch: pacman, Debian/Ubuntu: apt)
  up         build everything: network, VMs, VPN (first run downloads images)
  down       stop VMs and remove bridges/firewall from the host
  status     VM state, VPN peer, server route
  test       run the 10 required checks + extras, write reports/test-results.md
  backup     export the CHR configuration (sanitised) to docs/chr-export.rsc
  console    serial console of a VM      (./lab.sh console chr)
  shell      run a command in a VM       (./lab.sh shell client1 'ip a')
  chr        run a RouterOS command      (./lab.sh chr '/ip route print')
  reset-chr  re-create the CHR from the factory image and re-provision it
  clean      down + delete var/ (images, disks, keys)
USAGE
  ;;
esac
