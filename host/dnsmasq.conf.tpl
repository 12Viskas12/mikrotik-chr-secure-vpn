# DNS for br-wan/br-mgmt, one static DHCP lease for the CHR; never on br-lan/br-remote
no-resolv
no-hosts
bind-interfaces
except-interface=lo
listen-address=@@HOST_WAN_IP@@
listen-address=@@HOST_MGMT_IP@@
server=@@UPSTREAM_DNS@@
cache-size=300
pid-file=@@VAR@@/run/dnsmasq.pid
log-facility=@@VAR@@/dnsmasq.log

# DHCP only on br-mgmt, no gateway handed out
dhcp-range=172.31.0.0,static,255.255.255.0,12h
dhcp-host=@@CHR_MAC_MGMT@@,@@CHR_MGMT_IP@@,chr-lab
dhcp-option=option:router
dhcp-option=option:dns-server
no-dhcp-interface=br-wan
