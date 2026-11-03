# Test results

Run: 20261103-123950 - **51 passed, 0 failed**

| ID | Check | Expected | Result | Evidence |
|----|-------|----------|--------|----------|
| S2-1 | CHR has WAN address 192.168.100.2 | address present | PASS | rc=0 |
| S2-2 | CHR default route via 192.168.100.1 | route present | PASS | rc=0 |
| S2-3 | CHR reaches the Internet (1.1.1.1) | reply | PASS | rc=0 |
| S2-4 | NAT counter increments (masquerade works) | packets > 0 | PASS | rc=0 |
| 1a | client1 HTTPS to Internet | allowed | PASS | rc=0 |
| 1b | client1 DNS via CHR (10.50.0.1) | resolves | PASS | rc=0 |
| 1c | client1 SMTP/25 to Internet | blocked by policy | PASS | blocked (rc=1) |
| 1d | client1 direct DNS to 8.8.8.8 (DNS leak) | blocked | PASS | blocked (rc=1) |
| 2a | client1 -> 10.60.0.10 TCP/22 | allowed | PASS | rc=0 |
| 2b | client1 -> 10.60.0.10 TCP/443 (content check) | allowed | PASS | rc=0 |
| 2c | client2 -> 10.60.0.10 TCP/22 | allowed | PASS | rc=0 |
| 2d | client1 ping 10.60.0.10 | allowed | PASS | rc=0 |
| 3a | client1 -> 10.60.0.10 TCP/3389 | denied | PASS | blocked (rc=1) |
| 3b | client1 -> 10.60.0.20 TCP/22 (other host, same subnet) | denied | PASS | blocked (rc=1) |
| 3c | client1 ping 10.60.0.20 | denied | PASS | blocked (rc=1) |
| 3d | client1 ping remote gateway 10.60.0.1 | denied | PASS | blocked (rc=1) |
| 3e | nmap from client1: 22,443 open and 3389 filtered | exact port policy | PASS | rc=0 |
| 3f | CHR counted the denies (rule hit counters) | counters > 0 | PASS | rc=0 |
| 4a | WAN host -> client1 via CHR WAN address (routed) | denied | PASS | blocked (rc=1) |
| 4b | WAN host -> LAN gateway 10.50.0.1 | denied | PASS | blocked (rc=1) |
| 4c | WAN host -> LAN via the Linux host (bypass attempt) | denied | PASS | blocked (rc=1) |
| 5a | nmap WAN side of CHR: no open ports | all filtered | PASS | rc=0 |
| 5b | CHR WAN input drops were logged | log lines present | PASS | rc=0 |
| 5c | WAN host -> CHR mgmt address 172.31.0.2 (routed) | denied | PASS | blocked (rc=1) |
| 5d | Foreign host on br-mgmt (not the admin address) -> CHR SSH | denied | PASS | blocked (rc=1) |
| 5e | Foreign host on br-mgmt -> CHR WinBox 8291 | denied | PASS | blocked (rc=1) |
| 5f | Admin host (172.31.0.1) -> CHR SSH works | allowed | PASS | rc=0 |
| 5g | No unneeded services enabled on CHR | only ssh+winbox | PASS | rc=0 |
| 6a | Host ping CHR LAN address 10.50.0.1 | denied | PASS | blocked (rc=1) |
| 6b | Host ping client1 10.50.0.10 | denied | PASS | blocked (rc=1) |
| 6c | Host SSH probe client1 10.50.0.10:22 | denied | PASS | blocked (rc=127) |
| 6d | br-lan has no IPv4 address on the host | no address | PASS | rc=0 |
| 7a | Rogue with static IP in the LAN pings gateway | denied | PASS | blocked (rc=1) |
| 7b | Rogue ARPs for gateway | denied | PASS | blocked (rc=1) |
| 7c | Rogue reaches client1 | denied | PASS | blocked (rc=1) |
| 7d | L2 allow-list counters on the host increased | frames dropped at bridge | PASS | packets 144 -> 192 |
| 10a | LAN address not in lan-authorized list (10.50.0.66) -> server 22 | denied | PASS | blocked (rc=1) |
| 10b | Spoofed source 10.99.9.9 from LAN -> Internet | dropped by anti-spoof | PASS | blocked (rc=28) |
| 10c | Anti-spoof raw rule hit counter | packets > 0 | PASS | rc=0 |
| 10d | Client1 -> client2 directly at L2 (isolated ports) | denied (CLIENT_ISOLATION=yes) | PASS | blocked (rc=1) |
| 8a | CHR disabled the tunnel route after VPN loss | route disabled | PASS | rc=0 |
| 8b | client1 -> 10.60.0.10:22 while VPN is down | denied (fail closed) | PASS | blocked (rc=1) |
| 8c | client1 -> 10.60.0.10:443 while VPN is down | denied (fail closed) | PASS | blocked (rc=28) |
| 8d | client1 still has Internet (only the remote subnet is cut) | allowed | PASS | rc=0 |
| 8e | blackhole route for the remote subnet is present | failclosed route | PASS | rc=0 |
| 8f | Packet capture on br-wan: no remote-subnet traffic leaked | 0 packets | PASS | leaked=0 |
| 9a | Automatic recovery after the VPN returns | server reachable again | PASS | reconnected |
| 9b | WireGuard handshake is recent on the CHR | handshake seen | PASS | rc=0 |
| E1 | Tunnel traffic on br-wan is WireGuard only (no plaintext marker) | marker absent | PASS | rc=0 |
| E2 | IPv6: client1 has no default route / cannot reach IPv6 Internet | no v6 bypass | PASS | blocked (rc=1) |
| E3 | DNS leak check: only the CHR answers (resolver is 10.50.0.1) | resolver = CHR | PASS | rc=0 |

Sanitised raw log: `evidence/sanitized-logs/tests-20261103-123950.log`
