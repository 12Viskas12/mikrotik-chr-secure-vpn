#!/usr/sbin/nft -f
add table inet labfw
delete table inet labfw
add table ip labnat
delete table ip labnat
add table bridge labl2
delete table bridge labl2

table inet labfw {
	chain input {
		type filter hook input priority -10; policy accept;

		iifname { "br-lan", "br-remote" } counter log prefix "LAB-HOST-IN-ISOLATED " drop

		iifname "br-mgmt" ct state established,related accept
		iifname "br-mgmt" udp dport 67 accept
		iifname "br-mgmt" ip saddr @@CHR_MGMT_IP@@ udp dport 53 accept
		iifname "br-mgmt" ip saddr @@CHR_MGMT_IP@@ tcp dport 53 accept
		iifname "br-mgmt" counter log prefix "LAB-HOST-IN-MGMT " drop

		iifname "br-wan" ct state established,related accept
		iifname "br-wan" ip saddr @@HOST_WAN_NET@@ udp dport 53 accept
		iifname "br-wan" ip saddr @@HOST_WAN_NET@@ tcp dport 53 accept
		iifname "br-wan" counter log prefix "LAB-HOST-IN-WAN " drop
	}

	chain forward {
		type filter hook forward priority -10; policy accept;

		iifname "br-wan" oifname "@@UPLINK_IFACE@@" ip saddr @@HOST_WAN_NET@@ accept
		iifname "@@UPLINK_IFACE@@" oifname "br-wan" ct state established,related accept

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

table bridge labl2 {
	chain forward {
		type filter hook forward priority -200; policy accept;

		iifname "tap-chr-lan" ether saddr != @@CHR_MAC_LAN@@ counter drop
		iifname "tap-c1" ether saddr != @@C1_MAC@@ counter drop
		iifname "tap-c2" ether saddr != @@C2_MAC@@ counter drop
		iifname "tap-rgw-remote" ether saddr != @@RGW_MAC_REMOTE@@ counter drop
		iifname "tap-rsrv" ether saddr != @@RSRV_MAC@@ counter drop

		iifname != { "tap-chr-lan", "tap-c1", "tap-c2" } oifname { "tap-chr-lan", "tap-c1", "tap-c2" } counter log prefix "L2-ROGUE-INTO-LAN " drop
		iifname { "tap-chr-lan", "tap-c1", "tap-c2" } oifname != { "tap-chr-lan", "tap-c1", "tap-c2" } counter log prefix "L2-LAN-TO-ROGUE " drop

		iifname != { "tap-rgw-remote", "tap-rsrv" } oifname { "tap-rgw-remote", "tap-rsrv" } counter log prefix "L2-ROGUE-INTO-REMOTE " drop
		iifname { "tap-rgw-remote", "tap-rsrv" } oifname != { "tap-rgw-remote", "tap-rsrv" } counter log prefix "L2-REMOTE-TO-ROGUE " drop
	}
}
