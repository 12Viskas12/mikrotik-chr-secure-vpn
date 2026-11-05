#cloud-config
# simulated remote VPN gateway
hostname: rgw
manage_etc_hosts: true
users:
  - name: lab
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: '@@VM_PASS_HASH@@'
    ssh_authorized_keys:
      - @@SSH_PUBKEY_CONTENT@@
ssh_pwauth: false
package_update: true
packages: [wireguard-tools, nftables, qemu-guest-agent, tcpdump, iputils-ping]
write_files:
  - path: /etc/sysctl.d/99-lab.conf
    content: |
      net.ipv4.ip_forward=1
      net.ipv6.conf.all.disable_ipv6=1
      net.ipv4.conf.all.rp_filter=1
  - path: /etc/wireguard/wg0.conf
    permissions: '0600'
    content: |
      [Interface]
      Address = @@RGW_VPN_IP@@/24
      ListenPort = @@WG_PORT@@
      PrivateKey = @@RGW_WG_PRIVKEY@@

      [Peer]
      # CHR tunnel address and its LAN only
      PublicKey = @@CHR_WG_PUBKEY@@
      PresharedKey = @@WG_PSK@@
      AllowedIPs = @@CHR_VPN_IP@@/32, @@LAN_NET@@
  - path: /etc/nftables.conf
    content: |
      #!/usr/sbin/nft -f
      flush ruleset
      table inet rgw {
        chain input {
          type filter hook input priority 0; policy drop;
          iif lo accept
          ct state established,related accept
          ct state invalid drop
          iifname "wan" udp dport @@WG_PORT@@ accept
          iifname "wan" ip saddr @@HOST_WAN_IP@@ tcp dport 22 accept
          iifname "wg0" icmp type echo-request accept
          iifname "remote" icmp type echo-request accept
        }
        chain forward {
          type filter hook forward priority 0; policy drop;
          ct state established,related accept
          ct state invalid drop
          # one server, SSH/HTTPS/ping, from the CHR LAN only
          iifname "wg0" oifname "remote" ip saddr @@LAN_NET@@ ip daddr @@SRV_IP@@ tcp dport { 22, 443 } accept
          iifname "wg0" oifname "remote" ip saddr @@LAN_NET@@ ip daddr @@SRV_IP@@ icmp type echo-request accept
          # server -> Internet: web and DNS only
          iifname "remote" oifname "wan" tcp dport { 80, 443 } accept
          iifname "remote" oifname "wan" meta l4proto { tcp, udp } th dport 53 accept
          iifname "remote" oifname "wan" icmp type echo-request accept
          counter log prefix "RGW-FWD-DROP " drop
        }
      }
      table ip rgwnat {
        chain post {
          type nat hook postrouting priority 100; policy accept;
          oifname "wan" ip saddr @@REMOTE_NET@@ masquerade
        }
      }
runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ sysctl, --system ]
  - [ systemctl, enable, --now, nftables ]
  - [ systemctl, enable, --now, wg-quick@wg0 ]
