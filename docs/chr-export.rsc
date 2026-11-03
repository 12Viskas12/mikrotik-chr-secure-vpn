# 2026-11-03 11:27:54 by RouterOS 7.12.1
# software id = 
#
/interface ethernet set [ find default-name=ether3 ] arp=reply-only comment="LAN - br-lan (isolated)" disable-running-check=no name=lan
/interface ethernet set [ find default-name=ether1 ] comment="MGMT - br-mgmt (admin host only)" disable-running-check=no name=mgmt
/interface ethernet set [ find default-name=ether2 ] comment="WAN - br-wan (simulated Internet)" disable-running-check=no name=wan
/interface wireguard add comment="VPN to remote site" listen-port=13231 mtu=1420 name=wg-remote
/disk set slot1 slot=slot1 type=hardware
/interface list add name=WAN
/interface list add name=LAN
/interface list add name=MGMT
/interface list add name=VPN
/interface wireless security-profiles set [ find default=yes ] supplicant-identity=MikroTik
/ip pool add name=lan-pool ranges=10.50.0.100-10.50.0.200
/ip dhcp-server add add-arp=yes address-pool=lan-pool interface=lan lease-time=1h name=lan-dhcp
/port set 0 name=serial0
/system logging action add disk-file-name=fwlog disk-lines-per-file=2000 name=fwdisk target=disk
/ip firewall connection tracking set enabled=yes
/ip neighbor discovery-settings set discover-interface-list=none
/ip settings set rp-filter=loose secure-redirects=no send-redirects=no tcp-syncookies=yes
/ipv6 settings set disable-ipv6=yes
/interface list member add interface=wan list=WAN
/interface list member add interface=lan list=LAN
/interface list member add interface=mgmt list=MGMT
/interface list member add interface=wg-remote list=VPN
/interface wireguard peers add allowed-address=10.200.0.1/32,10.60.0.10/32 comment="remote gateway - only VPN peer address and the one server" endpoint-address=192.168.100.10 endpoint-port=51820 interface=wg-remote persistent-keepalive=10s preshared-key=<REDACTED> public-key="<REDACTED-KEY>"
/ip address add address=192.168.100.2/24 comment=WAN interface=wan network=192.168.100.0
/ip address add address=10.50.0.1/24 comment="LAN gateway" interface=lan network=10.50.0.0
/ip address add address=10.200.0.2/24 comment=VPN interface=wg-remote network=10.200.0.0
/ip dhcp-client add add-default-route=no interface=mgmt use-peer-dns=no use-peer-ntp=no
/ip dhcp-server lease add address=10.50.0.10 comment=client1 mac-address=52:54:00:00:04:01 server=lan-dhcp
/ip dhcp-server lease add address=10.50.0.11 comment=client2 mac-address=52:54:00:00:04:02 server=lan-dhcp
/ip dhcp-server network add address=10.50.0.0/24 comment=LAN dns-server=10.50.0.1 gateway=10.50.0.1
/ip dns set allow-remote-requests=yes servers=192.168.100.1
/ip firewall address-list add address=10.50.0.10 comment=client1 list=lan-authorized
/ip firewall address-list add address=10.50.0.11 comment=client2 list=lan-authorized
/ip firewall address-list add address=172.31.0.1 comment="admin address on br-mgmt" list=admin-hosts
/ip firewall filter add action=accept chain=input comment=established/related connection-state=established,related,untracked
/ip firewall filter add action=drop chain=input comment="drop invalid" connection-state=invalid
/ip firewall filter add action=accept chain=input comment="mgmt DHCP client reply" dst-port=68 in-interface=mgmt protocol=udp src-port=67
/ip firewall filter add action=accept chain=input comment="SSH + WinBox only from admin host on mgmt" dst-port=22,8291 in-interface=mgmt protocol=tcp src-address-list=admin-hosts
/ip firewall filter add action=accept chain=input comment="ping from admin host" in-interface=mgmt protocol=icmp src-address-list=admin-hosts
/ip firewall filter add action=accept chain=input comment="LAN DHCP server" dst-port=67 in-interface=lan protocol=udp
/ip firewall filter add action=accept chain=input comment="LAN DNS (udp)" dst-port=53 in-interface=lan protocol=udp
/ip firewall filter add action=accept chain=input comment="LAN DNS (tcp)" dst-port=53 in-interface=lan protocol=tcp
/ip firewall filter add action=accept chain=input comment="LAN ping to gateway" in-interface=lan limit=20,5:packet protocol=icmp
/ip firewall filter add action=accept chain=input comment="WireGuard from the known peer only" dst-port=13231 in-interface=wan protocol=udp src-address=192.168.100.10
/ip firewall filter add action=accept chain=input comment="VPN peer ping (monitor)" in-interface=wg-remote protocol=icmp src-address=10.200.0.1
/ip firewall filter add action=drop chain=input comment="DEFAULT DENY input" log=yes log-prefix="INPUT-DROP "
/ip firewall filter add action=accept chain=forward comment=established/related connection-state=established,related,untracked
/ip firewall filter add action=drop chain=forward comment="drop invalid" connection-state=invalid
/ip firewall filter add action=drop chain=forward comment="no port-forwards from WAN" connection-nat-state=dstnat connection-state=new in-interface=wan
/ip firewall filter add action=accept chain=forward comment="ALLOW LAN -> server TCP/22" dst-address=10.60.0.10 dst-port=22 in-interface=lan out-interface=wg-remote protocol=tcp src-address-list=lan-authorized
/ip firewall filter add action=accept chain=forward comment="ALLOW LAN -> server TCP/443" dst-address=10.60.0.10 dst-port=443 in-interface=lan out-interface=wg-remote protocol=tcp src-address-list=lan-authorized
/ip firewall filter add action=accept chain=forward comment="ALLOW LAN -> server ping" dst-address=10.60.0.10 in-interface=lan out-interface=wg-remote protocol=icmp src-address-list=lan-authorized
/ip firewall filter add action=drop chain=forward comment="DENY LAN -> server TCP/3389" dst-address=10.60.0.10 dst-port=3389 in-interface=lan log=yes log-prefix="DENY-RDP " protocol=tcp
/ip firewall filter add action=drop chain=forward comment="DENY LAN -> rest of remote network (any)" dst-address=10.60.0.0/24 in-interface=lan log=yes log-prefix="DENY-REMOTE "
/ip firewall filter add action=drop chain=forward comment="FAIL CLOSED: remote subnet never leaves via non-VPN interface" dst-address=10.60.0.0/24 log=yes log-prefix="FAILCLOSED " out-interface-list=!VPN
/ip firewall filter add action=drop chain=forward comment="DENY WAN -> remote network (any)" dst-address=10.60.0.0/24 in-interface=wan log=yes log-prefix="DENY-WAN-REMOTE "
/ip firewall filter add action=drop chain=forward comment="no new connections from VPN into LAN or elsewhere" in-interface=wg-remote log=yes log-prefix="DENY-VPN-IN "
/ip firewall filter add action=drop chain=forward comment="no direct DNS to Internet" dst-port=53 in-interface=lan log=yes log-prefix="DNS-LEAK " out-interface=wan protocol=udp
/ip firewall filter add action=drop chain=forward comment="no direct DNS to Internet (tcp)" dst-port=53 in-interface=lan log=yes log-prefix="DNS-LEAK " out-interface=wan protocol=tcp
/ip firewall filter add action=drop chain=forward comment="no DNS-over-TLS bypass" dst-port=853 in-interface=lan log=yes log-prefix="DOT-BLOCK " out-interface=wan protocol=tcp
/ip firewall filter add action=accept chain=forward comment="LAN -> Internet web" dst-port=80,443 in-interface=lan out-interface=wan protocol=tcp
/ip firewall filter add action=accept chain=forward comment="LAN -> Internet NTP" dst-port=123 in-interface=lan out-interface=wan protocol=udp
/ip firewall filter add action=accept chain=forward comment="LAN -> Internet ping" in-interface=lan out-interface=wan protocol=icmp
/ip firewall filter add action=drop chain=forward comment="DEFAULT DENY forward" log=yes log-prefix="FWD-DROP "
/ip firewall filter add action=drop chain=output comment="router itself never sends remote-subnet traffic to WAN" dst-address=10.60.0.0/24 log=yes log-prefix="OUT-FAILCLOSED " out-interface-list=!VPN
/ip firewall nat add action=masquerade chain=srcnat comment="LAN -> Internet" out-interface=wan src-address=10.50.0.0/24
/ip firewall raw add action=accept chain=prerouting comment="allow DHCPDISCOVER" dst-address=255.255.255.255 dst-port=67 in-interface=lan protocol=udp src-address=0.0.0.0
/ip firewall raw add action=drop chain=prerouting comment="anti-spoof: LAN source must be LAN subnet" in-interface=lan log=yes log-prefix="SPOOF-LAN " src-address=!10.50.0.0/24
/ip firewall raw add action=drop chain=prerouting comment="mgmt only from admin host" in-interface=mgmt log=yes log-prefix="SPOOF-MGMT " src-address=!172.31.0.1
/ip firewall raw add action=drop chain=prerouting comment="anti-spoof: LAN subnet from WAN" in-interface=wan src-address=10.50.0.0/24
/ip firewall raw add action=drop chain=prerouting comment="anti-spoof: remote subnet from WAN" in-interface=wan src-address=10.60.0.0/24
/ip firewall raw add action=drop chain=prerouting comment="anti-spoof: VPN subnet from WAN" in-interface=wan src-address=10.200.0.0/24
/ip firewall raw add action=drop chain=prerouting comment="no routing from WAN to LAN" dst-address=10.50.0.0/24 in-interface=wan log=yes log-prefix="WAN-TO-LAN "
/ip firewall raw add action=drop chain=prerouting comment="WAN -> remote network: DENY" dst-address=10.60.0.0/24 in-interface=wan log=yes log-prefix="WAN-TO-REMOTE "
/ip route add comment="default via WAN" dst-address=0.0.0.0/0 gateway=192.168.100.1
/ip route add comment=vpn-route disabled=no distance=1 dst-address=10.60.0.10/32 gateway=wg-remote
/ip route add blackhole comment=failclosed-blackhole distance=250 dst-address=10.60.0.0/24
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set ssh address=172.31.0.1/32
/ip service set api disabled=yes
/ip service set winbox address=172.31.0.1/32
/ip service set api-ssl disabled=yes
/ip ssh set strong-crypto=yes
/ipv6 firewall filter add action=accept chain=input connection-state=established,related
/ipv6 firewall filter add action=drop chain=input comment="IPv6 default deny"
/ipv6 firewall filter add action=drop chain=forward comment="IPv6 default deny"
/system clock set time-zone-name=UTC
/system identity set name=chr-lab
/system logging add action=fwdisk topics=firewall
/system logging add topics=wireguard
/system note set show-at-login=no
/system scheduler add comment="daily config export (no secrets)" interval=1d name=daily-export on-event="/export file=auto-export" policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon start-date=2026-11-03 start-time=03:00:00
/tool bandwidth-server set enabled=no
/tool mac-server set allowed-interface-list=none
/tool mac-server mac-winbox set allowed-interface-list=none
/tool mac-server ping set enabled=no
/tool netwatch
# Warning: probe waiting startup-delay=5m; 1m35s remaining
add comment="VPN monitor" down-script="/ip route disable [find comment=vpn-route]; :log error \"lab: VPN DOWN - server route disabled (fail closed)\"" host=10.200.0.1 interval=5s timeout=2s type=simple up-script="/ip route enable [find comment=vpn-route]; :log warning \"lab: VPN UP - server route enabled\""
