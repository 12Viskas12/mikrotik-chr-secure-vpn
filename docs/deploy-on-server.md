# Moving the lab to a server

## Scenario A: whole lab on the server (simulated remote side included)

Needs a Linux server with KVM (bare metal or nested virtualisation), root/sudo, and Internet access.

```bash
git clone <repo> && cd mikrotik-chr-secure-vpn
cp lab.env.example lab.env && $EDITOR lab.env     # ADMIN_PASSWORD, UPLINK_IFACE (server's public NIC)
./lab.sh deps && ./lab.sh up && ./lab.sh test
```

Checks before you start: `ls /dev/kvm`; the user is in group `kvm`; the host firewall (ufw/firewalld/Docker) must not drop forwarding between `br-wan` and the uplink (add an accept for it). The lab bridges are private to the server; nothing is exposed publicly. Do not publish ports 22/8291 of the CHR.

## Scenario B: CHR in the lab, real remote gateway/server

1. On the machine that runs the CHR generate keys: `./lab.sh keys`.
2. Generate the server-side config: `scripts/remote-gateway-config.sh <public_if> <lan_if> 10.60.0.10`, copy `var/remote-gateway/wg0.conf` to `/etc/wireguard/` on the remote gateway, load `nftables-rgw.conf`, enable forwarding, `wg-quick up wg0`.
3. Open UDP `51820` on the remote gateway to the CHR's public address only.
4. In `lab.env` set `WG_ENDPOINT_HOST=<remote gateway public IP>`.
5. The CHR firewall input rule accepts WireGuard only from `RGW_WAN_IP` (default `192.168.100.10`). Adjust that rule in `chr/chr-lab.rsc.tpl` if the real gateway's source address differs (e.g. your NAT address).
6. `./lab.sh render && ./lab.sh reset-chr`, then `./lab.sh test` (tests 8/9 need shell access to the remote gateway; skip or run manually).
7. Make sure the real server `10.60.0.10` has the gateway as its route back to `10.50.0.0/24`.

## Backups

`./lab.sh backup` stores a sanitised export in `docs/chr-export.rsc`; the CHR also exports daily on its own (`auto-export.rsc`).
