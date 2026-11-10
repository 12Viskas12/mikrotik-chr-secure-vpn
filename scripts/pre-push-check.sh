#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mode="git (tracked + untracked, minus .gitignore)"
  list() { git ls-files -co --exclude-standard -z; }
else
  mode="plain folder (no git yet): everything except var/, lab.env, .git"
  list() { find . -type f -not -path './var/*' -not -path './.git/*' -not -name 'lab.env' -print0 | sed -z 's|^\./||'; }
fi
echo "scan mode: $mode"
n=$(list | tr -cd '\0' | wc -c); echo "files scanned: $n"
[[ $n -gt 0 ]] || { echo "FAIL: nothing to scan"; exit 2; }

bad=0
if list | tr '\0' '\n' | grep -E '(^|/)(lab\.env|[^/]*\.key|[^/]*\.qcow2|[^/]*\.img|[^/]*psk[^/]*)$'; then
  echo "FAIL: forbidden file would be published"; bad=1
fi
if list | xargs -0 grep -nIE '[A-Za-z0-9+/]{43}=' 2>/dev/null | grep -v 'scripts/sanitize.sh' | grep -v 'scripts/pre-push-check.sh' | grep -v REDACTED; then
  echo "FAIL: WireGuard-key-like string found"; bad=1
fi
if list | xargs -0 grep -nIE '(private-key|preshared-key|password)="[A-Za-z0-9+/=]{8,}"' 2>/dev/null | grep -v '@@'; then
  echo "FAIL: credential in a file"; bad=1
fi
if [[ -f lab.env ]]; then
  pw="$(sed -n 's/^ADMIN_PASSWORD=//p' lab.env)"
  if [[ -n "$pw" ]] && list | xargs -0 grep -nIF -- "$pw" 2>/dev/null; then
    echo "FAIL: your ADMIN_PASSWORD appears in a file"; bad=1
  fi
fi
[[ $bad -eq 0 ]] && echo "pre-push check OK" || echo "pre-push check FAILED"
exit $bad
