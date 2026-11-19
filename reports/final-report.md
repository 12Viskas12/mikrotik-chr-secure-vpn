# Final report

Isolated LAN and WireGuard access to a remote server on a MikroTik CHR in QEMU/KVM.

## Where to find what

- Network scheme and addressing: [README](../README.md), [docs/architecture.md](../docs/architecture.md)
- QEMU configuration: [docs/qemu-config.md](../docs/qemu-config.md), `scripts/vms.sh`, `host/host.nft.tpl`
- MikroTik config: `chr/chr-lab.rsc.tpl` is the template, `docs/chr-export.rsc` is the export from the running CHR with secrets removed
- VPN: the `wireguard` part of the template, the remote side in `cloud-init/rgw/user-data.tpl`
- Firewall table: [docs/firewall.md](../docs/firewall.md) and `docs/chr-firewall-rules.txt`
- Routing table: `docs/chr-routing-table.txt`
- Screenshots: [docs/screenshots.md](../docs/screenshots.md), 14 of them from my run
- Test results: [test-results.md](test-results.md), tests 4 to 7 and 10 are the isolation checks
- Vulnerabilities and fixes: [docs/security-findings.md](../docs/security-findings.md)

## Result

I ran it on an Arch Linux host with QEMU/KVM, CHR 7.12.1 on the free licence and Debian 12 guests. `./lab.sh test` gave 51 passed and 0 failed. All ten required checks passed. While the VPN was down, `br-wan` showed no packets to `10.60.0.0/24`, and the access came back by itself after the VPN returned. The extra checks passed too: only WireGuard on the wire, no DNS leak, no IPv6 bypass, MAC and IP pinning, and a rogue VM blocked at layer 2.

## What I built

The CHR has separate management, WAN and LAN ports on four Linux bridges. The LAN and remote bridges have no host address, and an nftables bridge filter lets in only known ports and MAC addresses.

The WireGuard tunnel uses a pre-shared key and keepalive. Its peer may carry only the gateway address and the one server. Two listed clients can reach `10.60.0.10` on TCP 22 and 443 and ping it. Everything else going to the remote subnet is denied and logged.

Fail closed works in three layers. Netwatch disables the tunnel route when the peer stops answering, a blackhole route covers the remote subnet, and firewall rules drop remote traffic that would leave through a non-VPN interface.

The remote side is two VMs on the same machine, so the whole lab runs on one computer. Switching to a real server changes only the WireGuard endpoint, see [docs/deploy-on-server.md](../docs/deploy-on-server.md).

## Notes

- The `FAIL CLOSED` forward rule has a counter of 0 in the screenshots. That is expected. With the tunnel route disabled, packets for the server hit the blackhole route before the forward chain, so the rule is only a second line.
- My allow list is narrower than the task table. Only the two known clients can reach the server, not all of `10.50.0.0/24`.
- The remote gateway and server are VMs on the same host, not a separate site. I didn't test the latency or failures of a real WAN link.
- Client ports are isolated, so client1 and client2 can't talk to each other directly (test 10d).
- The first test run had 4 failures and the second had one. All of them were mistakes in my test script, not in the firewall. It expected `key=value` output but RouterOS 7.12 prints tables, and one check compared the number of counter lines instead of the packet totals. After fixing them everything passed.

## Limits and what I would improve

- The `daily-export` scheduler runs with the default full policy. It should be limited to `ftp,read,write,policy,test`.
- The CHR image is downloaded over HTTPS but not checked against a checksum, because MikroTik doesn't publish one next to it. The Debian image is checked against `SHA512SUMS`.
- The free CHR licence gives 1 Mbit/s per interface. That's fine for functional tests but not for measuring speed.
- Passwords are used to log in to the CHR and VMs. In production I would use SSH keys and a secrets manager.
- Only IPv4 is used. IPv6 is disabled on the CHR and the guests and covered by default deny rules.

## What I learned

- A separate IP subnet doesn't isolate a segment at layer 2. The bridge filter is what keeps foreign machines out of the LAN.
- A negative test needs a service that really listens. The server listens on 3389 and the decoy host on 22, otherwise "denied" looks the same as "nothing there".
- The failure path needs a check of its own, a tcpdump on the WAN bridge while the VPN is down, not only a check that the normal path works.
