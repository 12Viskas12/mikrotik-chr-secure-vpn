#!/usr/sbin/nft -f
# Host-side firewall for the lab bridges. Loaded by scripts/net-up.sh, removed by net-down.sh.
# Only traffic of the lab bridges is touched; everything else on the host is left alone.
# (If Docker/ufw already drops forwarded traffic, add an accept for br-wan <-> @@UPLINK_IFACE@@ there too.)

add table inet labfw
delete table inet labfw
add table ip labnat
delete table ip labnat
add table bridge labl2
delete table bridge labl2

table inet labfw {
	chain input {
		type filter hook input priority -10; policy accept;

		# The host never talks to the isolated segments (no IP on them) - belt and braces.
		iifname { "br-lan", "br-remote" } counter log prefix "LAB-HOST-IN-ISOLATED " drop

		# br-mgmt: only the CHR may ask for DHCP/DNS
		iifname "br-mgmt" ct state established,related accept
		iifname "br-mgmt" udp dport 67 accept
		iifname "br-mgmt" ip saddr @@CHR_MGMT_IP@@ udp dport 53 accept
		iifname "br-mgmt" ip saddr @@CHR_MGMT_IP@@ tcp dport 53 accept
		iifname "br-mgmt" counter log prefix "LAB-HOST-IN-MGMT " drop

		# br-wan ("Internet" side): only DNS for the lab, nothing else reaches the host
		iifname "br-wan" ct state established,related accept
		iifname "br-wan" ip saddr @@HOST_WAN_NET@@ udp dport 53 accept
		iifname "br-wan" ip saddr @@HOST_WAN_NET@@ tcp dport 53 accept
		iifname "br-wan" counter log prefix "LAB-HOST-IN-WAN " drop
	}

	chain forward {
		type filter hook forward priority -10; policy accept;

		# Lab Internet access: only from the WAN bridge, only with a WAN-range source address
		iifname "br-wan" oifname "@@UPLINK_IFACE@@" ip saddr @@HOST_WAN_NET@@ accept
		iifname "@@UPLINK_IFACE@@" oifname "br-wan" ct state established,related accept

		# Nothing else may be routed to/from any lab bridge: no way around the CHR through the host
		iifname { "br-mgmt", "br-wan", "br-lan", "br-remote" } counter log prefix "LAB-FWD-DROP " drop
		oifname { "br-mgmt", "br-wan", "br-lan", "br-remote" } counter drop
	}
}

table ip labnat {
	chain post {
		type nat hook postrouting priority 100; policy accept;
		ip saddr @@HOST_WAN_NET@@ oifname "@@UPLINK_IFACE@@" masquerade
	}
}

# L2 isolation: this is what keeps foreign VMs/containers off br-lan even if they are plugged in.
table bridge labl2 {
	chain forward {
		type filter hook forward priority -200; policy accept;

		# per-port MAC pinning (anti MAC spoofing)
		iifname "tap-chr-lan" ether saddr != @@CHR_MAC_LAN@@ counter drop
		iifname "tap-c1" ether saddr != @@C1_MAC@@ counter drop
		iifname "tap-c2" ether saddr != @@C2_MAC@@ counter drop
		iifname "tap-rgw-remote" ether saddr != @@RGW_MAC_REMOTE@@ counter drop
		iifname "tap-rsrv" ether saddr != @@RSRV_MAC@@ counter drop

		# br-lan membership: only the CHR LAN port and the two clients (anything else = rogue port)
		iifname != { "tap-chr-lan", "tap-c1", "tap-c2" } oifname { "tap-chr-lan", "tap-c1", "tap-c2" } counter log prefix "L2-ROGUE-INTO-LAN " drop
		iifname { "tap-chr-lan", "tap-c1", "tap-c2" } oifname != { "tap-chr-lan", "tap-c1", "tap-c2" } counter log prefix "L2-LAN-TO-ROGUE " drop

		# br-remote membership: only the remote gateway and the server
		iifname != { "tap-rgw-remote", "tap-rsrv" } oifname { "tap-rgw-remote", "tap-rsrv" } counter log prefix "L2-ROGUE-INTO-REMOTE " drop
		iifname { "tap-rgw-remote", "tap-rsrv" } oifname != { "tap-rgw-remote", "tap-rsrv" } counter log prefix "L2-REMOTE-TO-ROGUE " drop
	}
}
