#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

ACCEL=kvm; CPU=host
if [[ ! -w /dev/kvm ]]; then
  warn "/dev/kvm not usable (is the user in the 'kvm' group?) - falling back to slow TCG emulation"
  ACCEL=tcg; CPU=qemu64
fi

disk_chr()    { qemu-img create -q -f qcow2 -b "$IMG/chr-base.qcow2" -F qcow2 "$VMD/chr.qcow2" 2G; }
disk_debian() { qemu-img create -q -f qcow2 -b "$IMG/debian-base.qcow2" -F qcow2 "$VMD/$1.qcow2" 6G; }

make_seed() {
  local vm=$1 d="$REND/$vm"
  need xorriso
  mkdir -p "$SEED"
  printf 'instance-id: lab-%s-%s\nlocal-hostname: %s\n' "$vm" "$(date +%s)" "$vm" > "$d/meta-data"
  xorriso -as mkisofs -quiet -volid cidata -joliet -rock -o "$SEED/$vm.iso" \
    "$d/user-data" "$d/meta-data" "$d/network-config" >/dev/null 2>&1
}

nic() {
  printf -- '-netdev tap,id=%s,ifname=%s,script=no,downscript=no -device virtio-net-pci,netdev=%s,mac=%s ' "$1" "$2" "$1" "$3"
}

launch() {
  local name=$1 mem=$2 disk=$3 seed=$4; shift 4
  vm_running "$name" && { log "$name already running"; return; }
  mkdir -p "$RUN"; rm -f "$RUN/$name.qga"
  local args=(-name "$name" -machine "pc,accel=$ACCEL" -cpu "$CPU" -smp 2 -m "$mem"
    -display none -daemonize -pidfile "$RUN/$name.pid"
    -drive "file=$disk,format=qcow2,if=virtio"
    -serial "unix:$RUN/$name.console,server=on,wait=off")
  if [[ -n "$seed" ]]; then
    args+=(-drive "file=$seed,format=raw,if=virtio,media=cdrom,readonly=on"
      -chardev "socket,path=$RUN/$name.qga,server=on,wait=off,id=qga0"
      -device virtio-serial -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0")
  fi
  # shellcheck disable=SC2206
  args+=($@)
  qemu-system-x86_64 "${args[@]}"
  log "started $name"
}

create() {
  mkdir -p "$VMD" "$RUN"
  local vm
  [[ -f "$VMD/chr.qcow2" ]] || disk_chr
  for vm in rgw rsrv client1 client2; do
    [[ -f "$VMD/$vm.qcow2" ]] || disk_debian "$vm"
    make_seed "$vm"
  done
}

start() {
  case $1 in
    chr)    launch chr 1024 "$VMD/chr.qcow2" "" \
              "$(nic n0 tap-chr-mgmt "$CHR_MAC_MGMT")$(nic n1 tap-chr-wan "$CHR_MAC_WAN")$(nic n2 tap-chr-lan "$CHR_MAC_LAN")" ;;
    rgw)    launch rgw 512 "$VMD/rgw.qcow2" "$SEED/rgw.iso" \
              "$(nic n0 tap-rgw-wan "$RGW_MAC_WAN")$(nic n1 tap-rgw-remote "$RGW_MAC_REMOTE")" ;;
    rsrv)   launch rsrv 512 "$VMD/rsrv.qcow2" "$SEED/rsrv.iso" "$(nic n0 tap-rsrv "$RSRV_MAC")" ;;
    client1) launch client1 512 "$VMD/client1.qcow2" "$SEED/client1.iso" "$(nic n0 tap-c1 "$C1_MAC")" ;;
    client2) launch client2 512 "$VMD/client2.qcow2" "$SEED/client2.iso" "$(nic n0 tap-c2 "$C2_MAC")" ;;
    *) die "unknown vm $1" ;;
  esac
}

cmd=${1:-}; target=${2:-all}
ALL=(rgw chr rsrv client1 client2)
case $cmd in
  create) create ;;
  start)  if [[ $target == all ]]; then for v in "${ALL[@]}"; do start "$v"; done; else start "$target"; fi ;;
  stop)   if [[ $target == all ]]; then for v in client2 client1 rsrv chr rgw; do vm_stop "$v"; done; else vm_stop "$target"; fi ;;
  status) for v in "${ALL[@]}"; do if vm_running "$v"; then echo "$v: running (pid $(cat "$RUN/$v.pid"))"; else echo "$v: stopped"; fi; done ;;
  *) die "usage: vms.sh {create|start|stop|status} [vm|all]" ;;
esac
