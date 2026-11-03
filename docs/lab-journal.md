# Lab journal

| Date | Step | Result / notes |
|---|---|---|
| 2026-11-02 | Planned the lab: addressing, four bridges, CHR with WireGuard to a simulated remote site | Task requirements mapped to scripts and configs; templates rendered and checked offline (nftables syntax, YAML) |
| 2026-11-03 | Created `lab.env`, generated an SSH key | A key fingerprint had been pasted into `SSH_PUBKEY_FILE` by mistake; set the variable back to empty (default key path) |
| 2026-11-03 | `./lab.sh up` | Images downloaded (CHR 7.12.1, Debian 12, checksum OK). The RouterOS import ran without errors on the first try. Lab ready: client1 reaches `10.60.0.10:22` through the tunnel |
| 2026-11-03 | First `./lab.sh test` | 47 passed, 4 failed. All four were test-script problems: RouterOS 7.12 prints tables, not `key=value` |
| 2026-11-03 | Debugging in the zsh shell | `lib.sh` is written for bash; sourcing it in zsh broke SSH option splitting. Running through `bash -c` or `./lab.sh` works |
| 2026-11-03 | Fixed the parsers; second test run | 50 passed, 1 failed: check 7d compared the number of non-zero counter lines, which does not grow between runs. Changed it to compare total dropped packets |
| 2026-11-03 | Third test run | **51 passed, 0 failed** |
| 2026-11-03 | Screenshots | `peers print stats` is not supported on 7.12; used `print proplist=...` instead. Added `./lab.sh chr '...'` to avoid password prompts. Captured VPN down (fail closed) and reconnect manually |
| 2026-11-03 | `pre-push-check.sh` | The first version printed OK without scanning anything because the folder was not yet a git repository. Rewrote it to scan plain folders too and tested it with planted secrets |
| 2026-11-03 | `./lab.sh backup` | Live CHR export, firewall table and routing table saved to `docs/`; checked that no secrets remain |
