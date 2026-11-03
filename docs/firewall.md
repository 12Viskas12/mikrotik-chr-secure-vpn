# Firewall rules (CHR) - order matters

Full export: `docs/chr-export.rsc` (after `./lab.sh backup`). Source of truth: `chr/chr-lab.rsc.tpl`.

## Required access matrix

| Source | Destination | Port | Action | Rule |
|---|---|---|---|---|
| lan-authorized (10.50.0.10/.11) | 10.60.0.10 | TCP 22 | ALLOW | forward, out=wg-remote |
| lan-authorized | 10.60.0.10 | TCP 443 | ALLOW | forward, out=wg-remote |
| 10.50.0.0/24 | 10.60.0.10 | TCP 3389 | DENY (logged `DENY-RDP`) | forward |
| 10.50.0.0/24 | 10.60.0.0/24 | any | DENY (logged `DENY-REMOTE`) | forward |
| WAN | 10.60.0.0/24 | any | DENY (raw + forward) | raw prerouting, forward |
| WAN | 10.50.0.0/24 | any | DENY (raw) | raw prerouting |

The allow list is intentionally narrower than the task table (`lan-authorized` instead of the whole `10.50.0.0/24`): an unknown address in the LAN subnet cannot reach the server either.

## Chains

* **raw/prerouting**: DHCPDISCOVER exception, anti-spoofing (LAN source must be `10.50.0.0/24`, mgmt source must be the admin host, WAN may not use LAN/remote/VPN sources), WAN to LAN/remote dropped early.
* **input**: established, invalid drop, SSH+WinBox only from `172.31.0.1` on `mgmt`, LAN gets DHCP/DNS/ping only, WAN gets WireGuard from the known peer only, then **drop + log**.
* **forward**: established, invalid drop, no dstnat from WAN, the allow/deny matrix above, fail-closed rule, no new connections from the VPN, LAN to Internet only web/NTP/ping (DNS only via the CHR, DoT blocked), then **drop + log**.
* **output**: remote-subnet traffic may only leave via `VPN` interfaces.
* **NAT**: single masquerade for LAN to WAN. No NAT on the tunnel (the remote gateway routes `10.50.0.0/24` back through WireGuard).
* **IPv6**: disabled, plus default-deny rules in case it is enabled.

## Hardening list

Telnet/FTP/HTTP/HTTPS/API disabled; SSH and WinBox restricted to `172.31.0.1/32`; MAC-server, neighbor discovery, bandwidth server, proxy, SOCKS, UPnP, cloud DDNS off; strong SSH crypto; read-only `audit` user; firewall log to disk file `fwlog`; daily `/export`.
