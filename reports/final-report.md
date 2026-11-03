# Final report

Project: isolated LAN and WireGuard access to a remote server on MikroTik CHR in QEMU/KVM.

| Deliverable (stage VIII) | Where |
|---|---|
| Virtual and physical network scheme | [README](../README.md), [docs/architecture.md](../docs/architecture.md) |
| Addressing scheme | [docs/architecture.md](../docs/architecture.md) |
| QEMU configuration | [docs/qemu-config.md](../docs/qemu-config.md), `scripts/vms.sh`, `host/host.nft.tpl` |
| MikroTik export (.rsc) | `chr/chr-lab.rsc.tpl` (template), `docs/chr-export.rsc` (live export from the running CHR, secrets redacted) |
| VPN configuration | `[wireguard]` section of the template; remote side in `cloud-init/rgw/user-data.tpl` |
| Firewall rules table | [docs/firewall.md](../docs/firewall.md), `docs/chr-firewall-rules.txt` (live) |
| Routing table | `docs/chr-routing-table.txt` (live) |
| Screenshots of the working VPN | [docs/screenshots.md](../docs/screenshots.md) (14 captures from a real run) |
| Network test results | [test-results.md](test-results.md) (generated) |
| Isolation check results | tests 4-7 and 10 in `test-results.md` |
| Vulnerabilities and fixes | [docs/security-findings.md](../docs/security-findings.md) |

## Result

| | |
|---|---|
| Platform | Arch Linux host, QEMU/KVM, MikroTik CHR 7.12.1 (free licence), Debian 12 guests |
| Automated checks | **51 passed, 0 failed** (`./lab.sh test`, see [test-results.md](test-results.md)) |
| Required checks 1-10 | all passed, including fail-closed behaviour (no packet to `10.60.0.0/24` seen on `br-wan` while the VPN was down) and automatic recovery after the VPN returned |
| Extra checks | WireGuard-only traffic on the wire, no DNS leak, no IPv6 bypass, MAC/IP pinning, rogue-VM isolation at layer 2 |

## What was built

* A CHR with separate management, WAN and LAN ports, attached to four Linux bridges. The LAN and remote bridges have no host address, and an nftables bridge filter allows only known ports and MAC addresses.
* A WireGuard tunnel (with pre-shared key and keepalive) whose peer may carry only the gateway address and the one server. The firewall allows TCP 22/443 and ping from two listed clients to `10.60.0.10`; everything else toward the remote subnet is denied and logged.
* Fail closed in three layers: the tunnel route is disabled by a netwatch monitor when the peer stops answering, a blackhole route covers the remote subnet, and firewall rules drop remote-subnet traffic that would leave through a non-VPN interface.
* The remote side is simulated by two VMs (gateway and server) so the whole lab runs on one machine. Moving to a real server only changes the WireGuard endpoint (see [docs/deploy-on-server.md](../docs/deploy-on-server.md)).

## Observations and deviations

* The `FAIL CLOSED` forward rule shows a counter of 0 in the screenshots. This is expected: with the tunnel route disabled, packets to the server hit the blackhole route before the forward chain. The rule is a second line of defence.
* The allow list is narrower than the task table: only the two known clients (`lan-authorized`) may reach the server, not the whole `10.50.0.0/24`.
* The remote gateway and server are virtual machines on the same host, not a separate site. Latency and failure modes of a real WAN link were not tested.
* Client ports are isolated, so client1 and client2 cannot talk to each other directly (by design, test 10d).
* The first run of the tests produced 4 failures (and a fifth on the second run). All were mistakes in the test script, not in the firewall: it expected `key=value` output, but RouterOS 7.12 prints tables, and one check compared the number of counter lines instead of packet totals. The checks were fixed and the full run passed.

## Known limitations and improvements

* The `daily-export` scheduler runs with the default (full) policy set. It should be limited to `ftp,read,write,policy,test`.
* The CHR image is downloaded over HTTPS but not checksum-verified (MikroTik publishes no checksum file next to it); the Debian image is verified against its `SHA512SUMS`.
* Free CHR licence: 1 Mbit/s per interface, which is enough for functional tests but not for throughput measurements.
* Passwords are used for CHR and VM access inside the lab; for production use SSH keys and a secrets manager.
* IPv4 only: IPv6 is disabled on the CHR and guests and covered by default-deny rules as a backup.

## Lessons learned

* A separate IP subnet does not isolate a segment at layer 2; the bridge filter is what keeps foreign machines off the LAN.
* Test the negative cases against a service that really listens (the server listens on 3389 and the decoy host on 22), otherwise "denied" cannot be told from "nothing there".
* Verify the failure path (tcpdump on the WAN bridge while the VPN is down), not only that the happy path works.
