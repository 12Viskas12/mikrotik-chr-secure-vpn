#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need curl unzip qemu-img sha512sum

mkdir -p "$IMG"
if [[ ! -f "$IMG/chr-base.qcow2" ]]; then
  ver="$CHR_VERSION"
  if [[ "$ver" == latest ]]; then
    ver="$(curl -fsSL https://upgrade.mikrotik.com/routeros/NEWEST7.stable | awk '{print $1}')"
    [[ -n "$ver" ]] || die "could not determine the latest stable CHR version"
  fi
  log "downloading MikroTik CHR $ver"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fL --progress-bar -o "$tmp/chr.zip" "https://download.mikrotik.com/routeros/$ver/chr-$ver.img.zip"
  unzip -q -o "$tmp/chr.zip" -d "$tmp"
  qemu-img convert -f raw -O qcow2 "$tmp/chr-$ver.img" "$IMG/chr-base.qcow2"
  echo "$ver" > "$IMG/chr-version.txt"
  log "CHR $ver ready"
else
  log "CHR image present ($(cat "$IMG/chr-version.txt" 2>/dev/null || echo unknown))"
fi

if [[ ! -f "$IMG/debian-base.qcow2" ]]; then
  base="${DEBIAN_IMG_URL%/*}"; name="${DEBIAN_IMG_URL##*/}"
  log "downloading Debian cloud image $name"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  curl -fL --progress-bar -o "$tmp/$name" "$DEBIAN_IMG_URL"
  curl -fsSL -o "$tmp/SHA512SUMS" "$base/SHA512SUMS"
  ( cd "$tmp" && grep " $name\$" SHA512SUMS | sha512sum -c - ) || die "Debian image checksum mismatch"
  mv "$tmp/$name" "$IMG/debian-base.qcow2"
  log "Debian image verified"
else
  log "Debian image present"
fi
