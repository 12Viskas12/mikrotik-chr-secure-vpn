#!/usr/bin/env bash
# Build docs/screenshots.md from the images present in evidence/screenshots (file name = caption).
# Name files like 03-wireguard-handshake.png -> caption "wireguard handshake".
set -euo pipefail
cd "$(dirname "$0")/.."
out=docs/screenshots.md
{
  echo "# Screenshots"
  echo
  shopt -s nullglob
  for f in evidence/screenshots/*.{png,jpg,jpeg}; do
    b="$(basename "$f")"; cap="${b#*-}"; cap="${cap%.*}"; cap="${cap//-/ }"
    echo "## ${cap^}"; echo; echo "![${cap}](../${f})"; echo
  done
} > "$out"
echo "wrote $out"
