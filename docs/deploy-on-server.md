# Moving the lab to a server

## A: the whole lab on a server

The simulated remote side comes along. You need a Linux server with KVM (bare metal or nested virtualisation), sudo and internet access.

```bash
git clone https://github.com/12Viskas12/mikrotik-chr-secure-vpn
cd mikrotik-chr-secure-vpn
cp lab.env.example lab.env      # set ADMIN_PASSWORD and UPLINK_IFACE, the public NIC of the server
./lab.sh deps && ./lab.sh up && ./lab.sh test
```

Before you start, check that `/dev/kvm` exists and your user is in the `kvm` group. If ufw, firewalld or Docker drops forwarded traffic, add an accept rule for `br-wan` to the uplink. The lab bridges stay private to the server. Don't publish ports 22 and 8291 of the CHR.

## B: CHR in the lab, a real remote gateway and server

1. On the machine that runs the CHR, generate the keys with `./lab.sh keys`.
2. Run `scripts/remote-gateway-config.sh <public_if> <lan_if> 10.60.0.10`. Copy `var/remote-gateway/wg0.conf` to `/etc/wireguard/` on the remote gateway, load `nftables-rgw.conf`, turn on forwarding and run `wg-quick up wg0`.
3. On the gateway, open UDP 51820 only for the public address of the CHR.
4. Set `WG_ENDPOINT_HOST` in `lab.env` to the public IP of the gateway.
5. The CHR input rule accepts WireGuard only from `RGW_WAN_IP`, by default `192.168.100.10`. If the real gateway reaches the CHR from another address (for example behind NAT), change that rule in `chr/chr-lab.rsc.tpl`.
6. Run `./lab.sh render && ./lab.sh reset-chr`, then `./lab.sh test`. Tests 8 and 9 need a shell on the remote gateway, so skip them or do them by hand.
7. Make sure the real server `10.60.0.10` routes `10.50.0.0/24` back through the gateway.

## Backups

`./lab.sh backup` saves a config export without secrets to `docs/chr-export.rsc`. The CHR also exports its config once a day on its own (`auto-export.rsc`).
