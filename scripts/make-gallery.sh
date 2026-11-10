#!/usr/bin/env bash
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
