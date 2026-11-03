#!/usr/bin/env python3
"""Run a shell command inside a VM through the QEMU guest agent.

The isolated segments have no host IP on purpose, so the host cannot SSH into the
clients or the remote server. The guest-agent channel (virtio-serial) is an
out-of-band path that does not touch the network under test.

usage: qga.py SOCKET 'shell command' [TIMEOUT_SECONDS]
Prints the command's stdout/stderr and exits with its exit code.
Exit 124 = timeout, 125 = guest agent not reachable.
"""
import base64
import json
import socket
import sys
import time


def rpc(sock, rf, cmd, args=None):
    msg = {"execute": cmd}
    if args is not None:
        msg["arguments"] = args
    sock.sendall((json.dumps(msg) + "\n").encode())
    while True:
        line = rf.readline()
        if not line:
            raise ConnectionError("socket closed")
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if "return" in obj or "error" in obj:
            return obj


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path, cmd = sys.argv[1], sys.argv[2]
    timeout = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    deadline = time.time() + timeout
    cmd = "export PATH=$PATH:/usr/sbin:/sbin; " + cmd

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(10)
        s.connect(path)
        rf = s.makefile("rb")
        sync_id = int(time.time() * 1000) & 0x7FFFFFFF
        s.sendall(json.dumps({"execute": "guest-sync", "arguments": {"id": sync_id}}).encode() + b"\n")
        while True:
            line = rf.readline()
            if not line:
                raise ConnectionError("socket closed")
            try:
                if json.loads(line).get("return") == sync_id:
                    break
            except ValueError:
                continue
        s.settimeout(timeout + 15)
        r = rpc(s, rf, "guest-exec", {"path": "/bin/sh", "arg": ["-c", cmd], "capture-output": True})
        if "error" in r:
            print(r["error"], file=sys.stderr)
            return 1
        pid = r["return"]["pid"]
        while True:
            st = rpc(s, rf, "guest-exec-status", {"pid": pid}).get("return", {})
            if st.get("exited"):
                break
            if time.time() > deadline:
                print("qga: timeout", file=sys.stderr)
                return 124
            time.sleep(0.3)
    except (OSError, ConnectionError):
        print("qga: guest agent not reachable", file=sys.stderr)
        return 125

    sys.stdout.buffer.write(base64.b64decode(st.get("out-data", "")))
    sys.stderr.buffer.write(base64.b64decode(st.get("err-data", "")))
    sys.stdout.flush()
    if "exitcode" in st:
        return int(st["exitcode"])
    return 1 if "signal" in st else 0


if __name__ == "__main__":
    sys.exit(main())
