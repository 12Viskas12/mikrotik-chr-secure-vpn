#!/usr/bin/env python3
"""Render a template: replace @@NAME@@ with the value of environment variable NAME.

usage: render.py TEMPLATE OUTPUT
Fails if a placeholder has no value, so a typo can never produce a silently broken config.
"""
import os
import re
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        text = f.read()

    missing = set()

    def sub(match: re.Match) -> str:
        name = match.group(1)
        value = os.environ.get(name)
        if value is None:
            missing.add(name)
            return match.group(0)
        return value

    out = re.sub(r"@@([A-Z0-9_]+)@@", sub, text)
    if missing:
        print(f"render: {src}: undefined variables: {', '.join(sorted(missing))}", file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
