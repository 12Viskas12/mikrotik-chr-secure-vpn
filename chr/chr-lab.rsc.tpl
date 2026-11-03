# =====================================================================
# MikroTik CHR lab configuration (RouterOS 7.x)
# Template: scripts/render.sh fills the double-at placeholders -> var/render/chr-lab.rsc
# Applied to a factory-fresh CHR by scripts/chr-provision.sh (/import).
# Design: default deny, fail-closed VPN, management only from the host admin address.
# =====================================================================
:log info "lab: import started"

/system identity set name=chr-lab
/system clock set time-zone-name=UTC

# ---------------------------------------------------------------- interfaces
# Matched by MAC so that NIC order never matters.
/interface ethernet
set [find mac-address=@@CHR_MAC_MGMT@@] name=mgmt comment="MGMT - br-mgmt (admin host only)"
set [find mac-address=@@CHR_MAC_WAN@@] name=wan comment="WAN - br-wan (simulated Internet)"
set [find mac-address=@@CHR_MAC_LAN@@] name=lan arp=reply-only comment="LAN - br-lan (isolated)"

/interface list
add name=WAN
add name=LAN
add name=MGMT
add name=VPN
/interface list member
add list=WAN interface=wan
add list=LAN interface=lan
add list=MGMT interface=mgmt

# ---------------------------------------------------------------- addressing
# MGMT keeps the DHCP client of the factory config (static lease from the host dnsmasq),
# but must never install a default route or DNS from it.
:if ([:len [/ip dhcp-client find]] = 0) do={ /ip dhcp-client add interface=mgmt add-default-route=no use-peer-dns=no use-peer-ntp=no disabled=no } else={ /ip dhcp-client set [find] interface=mgmt add-default-route=no use-peer-dns=no use-peer-ntp=no disabled=no }

/ip address
add address=@@CHR_WAN_IP@@/24 interface=wan comment="WAN"
add address=@@CHR_LAN_IP@@/24 interface=lan comment="LAN gateway"

/ip route
add dst-address=0.0.0.0/0 gateway=@@HOST_WAN_IP@@ comment="default via WAN"

/ip dns
set servers=@@HOST_WAN_IP@@ allow-remote-requests=yes cache-size=2048KiB

# ---------------------------------------------------------------- DHCP (LAN only)
/ip pool
add name=lan-pool ranges=@@DHCP_POOL@@
/ip dhcp-server
add name=lan-dhcp interface=lan address-pool=lan-pool lease-time=1h add-arp=yes disabled=no
/ip dhcp-server network
add address=@@LAN_NET@@ gateway=@@CHR_LAN_IP@@ dns-server=@@CHR_LAN_IP@@ comment="LAN"
/ip dhcp-server lease
add address=@@C1_IP@@ mac-address=@@C1_MAC@@ server=lan-dhcp comment="client1"
add address=@@C2_IP@@ mac-address=@@C2_MAC@@ server=lan-dhcp comment="client2"

# ---------------------------------------------------------------- WireGuard
/interface wireguard
add name=wg-remote listen-port=@@CHR_WG_LISTEN_PORT@@ mtu=1420 private-key="@@CHR_WG_PRIVKEY@@" comment="VPN to remote site"
/interface wireguard peers
add interface=wg-remote public-key="@@RGW_WG_PUBKEY@@" preshared-key="@@WG_PSK@@" endpoint-address=@@WG_ENDPOINT_HOST@@ endpoint-port=@@WG_PORT@@ allowed-address=@@RGW_VPN_IP@@/32,@@SRV_IP@@/32 persistent-keepalive=10s comment="remote gateway - only VPN peer address and the one server"
/ip address
add address=@@CHR_VPN_IP@@/24 interface=wg-remote comment="VPN"
/interface list member
add list=VPN interface=wg-remote

# ---------------------------------------------------------------- routing / fail closed
# 1) Route to the single allowed server over the tunnel. Disabled until the VPN monitor says "up".
# 2) Blackhole for the whole remote subnet with a worse distance: whatever the tunnel route
#    does not cover (or when it is disabled) is discarded and can NEVER follow the default route to WAN.
/ip route
add dst-address=@@SRV_IP@@/32 gateway=wg-remote distance=1 disabled=yes comment="vpn-route"
add dst-address=@@REMOTE_NET@@ blackhole distance=250 comment="failclosed-blackhole"

/tool netwatch
add host=@@RGW_VPN_IP@@ interval=5s timeout=2s comment="VPN monitor" \
    up-script="/ip route enable [find comment=vpn-route]; :log warning \"lab: VPN UP - server route enabled\"" \
    down-script="/ip route disable [find comment=vpn-route]; :log error \"lab: VPN DOWN - server route disabled (fail closed)\""

# ---------------------------------------------------------------- address lists
/ip firewall address-list
add list=lan-authorized address=@@C1_IP@@ comment="client1"
add list=lan-authorized address=@@C2_IP@@ comment="client2"
add list=admin-hosts address=@@HOST_MGMT_IP@@ comment="admin address on br-mgmt"

# ---------------------------------------------------------------- firewall: RAW (anti-spoofing, early drops)
/ip firewall raw
add chain=prerouting action=accept in-interface=lan protocol=udp src-address=0.0.0.0 dst-address=255.255.255.255 dst-port=67 comment="allow DHCPDISCOVER"
add chain=prerouting action=drop in-interface=lan src-address=!@@LAN_NET@@ log=yes log-prefix="SPOOF-LAN " comment="anti-spoof: LAN source must be LAN subnet"
add chain=prerouting action=drop in-interface=mgmt src-address=!@@HOST_MGMT_IP@@ log=yes log-prefix="SPOOF-MGMT " comment="mgmt only from admin host"
add chain=prerouting action=drop in-interface=wan src-address=@@LAN_NET@@ comment="anti-spoof: LAN subnet from WAN"
add chain=prerouting action=drop in-interface=wan src-address=@@REMOTE_NET@@ comment="anti-spoof: remote subnet from WAN"
add chain=prerouting action=drop in-interface=wan src-address=10.200.0.0/24 comment="anti-spoof: VPN subnet from WAN"
add chain=prerouting action=drop in-interface=wan dst-address=@@LAN_NET@@ log=yes log-prefix="WAN-TO-LAN " comment="no routing from WAN to LAN"
add chain=prerouting action=drop in-interface=wan dst-address=@@REMOTE_NET@@ log=yes log-prefix="WAN-TO-REMOTE " comment="WAN -> remote network: DENY"

# ---------------------------------------------------------------- firewall: INPUT (to the router itself)
/ip firewall filter
add chain=input action=accept connection-state=established,related,untracked comment="established/related"
add chain=input action=drop connection-state=invalid comment="drop invalid"
add chain=input action=accept in-interface=mgmt protocol=udp src-port=67 dst-port=68 comment="mgmt DHCP client reply"
add chain=input action=accept in-interface=mgmt src-address-list=admin-hosts protocol=tcp dst-port=22,8291 comment="SSH + WinBox only from admin host on mgmt"
add chain=input action=accept in-interface=mgmt src-address-list=admin-hosts protocol=icmp comment="ping from admin host"
add chain=input action=accept in-interface=lan protocol=udp dst-port=67 comment="LAN DHCP server"
add chain=input action=accept in-interface=lan protocol=udp dst-port=53 comment="LAN DNS (udp)"
add chain=input action=accept in-interface=lan protocol=tcp dst-port=53 comment="LAN DNS (tcp)"
add chain=input action=accept in-interface=lan protocol=icmp limit=20,5:packet comment="LAN ping to gateway"
add chain=input action=accept in-interface=wan src-address=@@RGW_WAN_IP@@ protocol=udp dst-port=@@CHR_WG_LISTEN_PORT@@ comment="WireGuard from the known peer only"
add chain=input action=accept in-interface=wg-remote src-address=@@RGW_VPN_IP@@ protocol=icmp comment="VPN peer ping (monitor)"
add chain=input action=drop log=yes log-prefix="INPUT-DROP " comment="DEFAULT DENY input"

# ---------------------------------------------------------------- firewall: FORWARD (order matters)
add chain=forward action=accept connection-state=established,related,untracked comment="established/related"
add chain=forward action=drop connection-state=invalid comment="drop invalid"
add chain=forward action=drop connection-state=new connection-nat-state=dstnat in-interface=wan comment="no port-forwards from WAN"
# --- LAN -> remote server, only through the tunnel, only for authorized clients
add chain=forward action=accept in-interface=lan out-interface=wg-remote src-address-list=lan-authorized dst-address=@@SRV_IP@@ protocol=tcp dst-port=22 comment="ALLOW LAN -> server TCP/22"
add chain=forward action=accept in-interface=lan out-interface=wg-remote src-address-list=lan-authorized dst-address=@@SRV_IP@@ protocol=tcp dst-port=443 comment="ALLOW LAN -> server TCP/443"
add chain=forward action=accept in-interface=lan out-interface=wg-remote src-address-list=lan-authorized dst-address=@@SRV_IP@@ protocol=icmp comment="ALLOW LAN -> server ping"
add chain=forward action=drop in-interface=lan dst-address=@@SRV_IP@@ protocol=tcp dst-port=3389 log=yes log-prefix="DENY-RDP " comment="DENY LAN -> server TCP/3389"
add chain=forward action=drop in-interface=lan dst-address=@@REMOTE_NET@@ log=yes log-prefix="DENY-REMOTE " comment="DENY LAN -> rest of remote network (any)"
add chain=forward action=drop dst-address=@@REMOTE_NET@@ out-interface-list=!VPN log=yes log-prefix="FAILCLOSED " comment="FAIL CLOSED: remote subnet never leaves via non-VPN interface"
add chain=forward action=drop in-interface=wan dst-address=@@REMOTE_NET@@ log=yes log-prefix="DENY-WAN-REMOTE " comment="DENY WAN -> remote network (any)"
add chain=forward action=drop in-interface=wg-remote log=yes log-prefix="DENY-VPN-IN " comment="no new connections from VPN into LAN or elsewhere"
# --- LAN -> Internet policy: web, NTP and ping only; DNS only via the CHR (no DNS leaks)
add chain=forward action=drop in-interface=lan out-interface=wan protocol=udp dst-port=53 log=yes log-prefix="DNS-LEAK " comment="no direct DNS to Internet"
add chain=forward action=drop in-interface=lan out-interface=wan protocol=tcp dst-port=53 log=yes log-prefix="DNS-LEAK " comment="no direct DNS to Internet (tcp)"
add chain=forward action=drop in-interface=lan out-interface=wan protocol=tcp dst-port=853 log=yes log-prefix="DOT-BLOCK " comment="no DNS-over-TLS bypass"
add chain=forward action=accept in-interface=lan out-interface=wan protocol=tcp dst-port=80,443 comment="LAN -> Internet web"
add chain=forward action=accept in-interface=lan out-interface=wan protocol=udp dst-port=123 comment="LAN -> Internet NTP"
add chain=forward action=accept in-interface=lan out-interface=wan protocol=icmp comment="LAN -> Internet ping"
add chain=forward action=drop log=yes log-prefix="FWD-DROP " comment="DEFAULT DENY forward"

# ---------------------------------------------------------------- firewall: OUTPUT (router itself)
add chain=output action=drop dst-address=@@REMOTE_NET@@ out-interface-list=!VPN log=yes log-prefix="OUT-FAILCLOSED " comment="router itself never sends remote-subnet traffic to WAN"

# ---------------------------------------------------------------- NAT
/ip firewall nat
add chain=srcnat action=masquerade src-address=@@LAN_NET@@ out-interface=wan comment="LAN -> Internet"

# ---------------------------------------------------------------- IPv6: off, plus default-deny in case it is switched on
/ipv6 firewall filter
add chain=input action=accept connection-state=established,related
add chain=input action=drop comment="IPv6 default deny"
add chain=forward action=drop comment="IPv6 default deny"
/ipv6 settings
set disable-ipv6=yes

# ---------------------------------------------------------------- hardening
/ip settings
set rp-filter=loose tcp-syncookies=yes accept-source-route=no accept-redirects=no send-redirects=no secure-redirects=no
/ip firewall connection tracking
set enabled=yes

/ip service
set [find name=telnet] disabled=yes
set [find name=ftp] disabled=yes
set [find name=www] disabled=yes
set [find name=www-ssl] disabled=yes
set [find name=api] disabled=yes
set [find name=api-ssl] disabled=yes
set [find name=ssh] disabled=no address=@@HOST_MGMT_IP@@/32
set [find name=winbox] disabled=no address=@@HOST_MGMT_IP@@/32
/ip ssh
set strong-crypto=yes
/tool mac-server
set allowed-interface-list=none
/tool mac-server mac-winbox
set allowed-interface-list=none
/tool mac-server ping
set enabled=no
/ip neighbor discovery-settings
set discover-interface-list=none
/tool bandwidth-server
set enabled=no
/ip proxy
set enabled=no
/ip socks
set enabled=no
/ip upnp
set enabled=no
/ip cloud
set ddns-enabled=no update-time=no

# ---------------------------------------------------------------- users: admin vs read-only
/user
set [find name=admin] password="@@ADMIN_PASSWORD@@" address=@@HOST_MGMT_IP@@/32
add name=audit group=read password="@@ADMIN_PASSWORD@@" address=@@HOST_MGMT_IP@@/32 comment="read-only monitoring"

# ---------------------------------------------------------------- logging + backups
/system logging action
add name=fwdisk target=disk disk-file-name=fwlog disk-lines-per-file=2000 disk-file-count=2
/system logging
add topics=firewall action=fwdisk
add topics=wireguard action=memory
/system scheduler
add name=daily-export interval=1d start-time=03:00:00 on-event="/export file=auto-export" comment="daily config export (no secrets)"

:log info "lab: import finished"
