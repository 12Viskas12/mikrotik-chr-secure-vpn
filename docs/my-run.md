# How I ran it on my computer

A step-by-step record of a full local run of this lab, with the screenshots taken at each step. Everything below was done on one machine; nothing was run in the cloud.

| | |
|---|---|
| Host | Arch Linux, QEMU/KVM, zsh |
| Router | MikroTik CHR 7.12.1 (free licence) |
| Guests | Debian 12 cloud image: remote gateway `rgw`, server `rsrv`, `client1`, `client2` |
| Date | 2026-11-03 |
| Result | 51 of 51 checks passed ([reports/test-results.md](../reports/test-results.md)) |

## 1. Prepare the host

```bash
git clone https://github.com/12Viskas12/mikrotik-chr-secure-vpn
cd mikrotik-chr-secure-vpn
./lab.sh deps                     # qemu, nftables, dnsmasq, wireguard-tools, nmap, ...
sudo usermod -aG kvm "$USER"      # once, then log out and in again
```

## 2. Configure

```bash
cp lab.env.example lab.env
nano lab.env
```

Only `ADMIN_PASSWORD` is required (letters and digits). Everything else keeps its default: `SSH_PUBKEY_FILE` and `UPLINK_IFACE` are detected automatically, `WG_ENDPOINT_HOST` stays empty so the CHR connects to the simulated remote gateway.

`lab.env` is git-ignored and never published.

## 3. Build and start everything

```bash
./lab.sh up
./lab.sh status
```

`up` generates the WireGuard keys, downloads and verifies the images, creates the four bridges and the host firewall, starts the five VMs and imports the RouterOS configuration into the CHR. The first run takes about ten minutes because of the downloads.

![Lab is running](../evidence/screenshots/01-qemu-vms-running.png)

All five VMs are up and the WireGuard peer is alive.

## 4. Check the host network

```bash
ip -br link show type bridge
ip -br addr
sudo nft list table bridge labl2
```

![Host bridges](../evidence/screenshots/02-host-bridges.png)

`br-lan` and `br-remote` have no IPv4 address: the host cannot reach the isolated segments.

![L2 allow-list](../evidence/screenshots/02b-l2-allowlist-nft.png)

The bridge-level allow-list that drops frames from unknown ports.

## 5. Check the CHR

```bash
./lab.sh chr '/interface print; /ip address print'
./lab.sh chr '/interface wireguard peers print proplist=interface,endpoint-address,allowed-address,persistent-keepalive,last-handshake,rx,tx'
./lab.sh chr '/ip route print'
```

![CHR interfaces and addresses](../evidence/screenshots/03-chr-interfaces-addresses.png)

![WireGuard peer](../evidence/screenshots/04-wireguard-handshake.png)

![Routing table](../evidence/screenshots/05-routing-table.png)

The tunnel route to `10.60.0.10/32` and the fail-closed blackhole for `10.60.0.0/24`.

## 6. Check the firewall

```bash
./lab.sh chr '/ip firewall filter print stats'
```

![Forward chain with counters](../evidence/screenshots/06-firewall-rules.png)

## 7. Use the VPN from a client

```bash
./lab.sh shell client1 'nmap -Pn -p 22,443,3389 10.60.0.10; traceroute -n 10.60.0.10'
./lab.sh shell client1 'nc -zv -w3 10.60.0.20 22; ping -c2 10.60.0.20'
```

![Client to server](../evidence/screenshots/07-client-to-server-ok.png)

Ports 22 and 443 are open, 3389 is filtered.

![Other hosts are denied](../evidence/screenshots/08-denied-other-hosts.png)

Any other host of the remote network is unreachable.

## 8. Run the automated tests

```bash
./lab.sh test
```

![Test summary](../evidence/screenshots/12-test-results.png)

The first run gave 47 passed and 4 failed; all four were problems in the test parsers (RouterOS 7.12 prints tables, not `key=value`). After fixing them the final run is **51 passed, 0 failed**. The full table is in [reports/test-results.md](../reports/test-results.md), the raw log in `evidence/sanitized-logs/`.

## 9. Break the VPN and watch it fail closed

Run the commands one at a time, with the pauses, so netwatch has time to react.

```bash
./lab.sh shell rgw 'systemctl stop wg-quick@wg0'
sleep 20
./lab.sh shell client1 'nc -zv -w3 10.60.0.10 22'      # must fail
./lab.sh chr '/ip route print'                          # tunnel route is disabled (X)
```

![VPN down: fail closed](../evidence/screenshots/09-vpn-down-fail-closed.png)

Then bring the VPN back:

```bash
./lab.sh shell rgw 'systemctl start wg-quick@wg0'
sleep 20
./lab.sh shell client1 'nc -zv -w3 10.60.0.10 22'      # works again
```

![VPN back](../evidence/screenshots/10-vpn-reconnect.png)

## 10. Prove that only encrypted traffic is on the wire

```bash
sudo tcpdump -ni br-wan udp port 51820
```

![Only WireGuard on the wire](../evidence/screenshots/11-tcpdump-wireguard-only.png)

## 11. Look at the firewall log

```bash
./lab.sh chr '/log print where message~"DENY"'
```

![Firewall log](../evidence/screenshots/13-firewall-log.png)

## 12. Save the evidence and publish

```bash
./lab.sh backup                      # sanitised CHR export, firewall table, routing table -> docs/
bash scripts/pre-push-check.sh       # scans for secrets before the push
git add -A && git commit -m "Lab results" && git push
```

The results of this step are [docs/chr-export.rsc](chr-export.rsc), [docs/chr-firewall-rules.txt](chr-firewall-rules.txt) and [docs/chr-routing-table.txt](chr-routing-table.txt).

## 13. Clean up

```bash
./lab.sh down          # stops the VMs, removes bridges and host firewall rules
./lab.sh clean         # optional: also deletes downloaded images and var/
```

## Problems I hit

| Problem | Cause | Fix |
|---|---|---|
| 4 tests failed on the first run | RouterOS 7.12 prints tables, the tests parsed `key=value` | rewrote the parsers in `scripts/run-tests.sh` |
| SSH options broke when I debugged in zsh | `scripts/lib.sh` is written for bash | run through `./lab.sh` or `bash -c` |
| Test 7d failed once | it compared the number of non-zero counter lines, which does not grow | compares the total of dropped packets now |
| `peers print stats` is rejected | not supported on RouterOS 7.12 | `print proplist=...` |
| `SSH_PUBKEY_FILE` contained a key fingerprint | pasted by mistake | left it empty, the default key path is used |
| VPN-down screenshot showed no failure | multi-line paste ran without the waits | run the commands one at a time with `sleep` |

The full chronology is in the [lab journal](lab-journal.md).
