#!/usr/bin/env bash
# Functional + security tests for the 10 required checks and the extras.
# Writes reports/test-results.md and a sanitised log to evidence/sanitized-logs/.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
need sshpass nmap python3

TS="$(date +%Y%m%d-%H%M%S)"
RAW="$VAR/tests-$TS.log"; mkdir -p "$VAR" "$ROOT/reports" "$ROOT/evidence/sanitized-logs"
RESULTS="$VAR/results.tsv"; : > "$RESULTS"
PASS=0; FAIL=0

c1() { vm_exec client1 "$1" "${2:-30}"; }
c2() { vm_exec client2 "$1" "${2:-30}"; }
rgw() { vm_exec rgw "$1" "${2:-30}"; }
ns() { local n=$1; shift; $SUDO ip netns exec "$n" "$@"; }
say() { printf '\n### %s\n' "$*" | tee -a "$RAW"; }

# record ID "title" "expected" PASS|FAIL "evidence"
record() {
  local id=$1 title=$2 expected=$3 verdict=$4 ev=${5:-}
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "$expected" "$verdict" "$ev" >> "$RESULTS"
  if [[ $verdict == PASS ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  printf '[%s] %s - %s\n' "$verdict" "$id" "$title" | tee -a "$RAW"
}
# ok ID title expected cmd...  : passes when cmd exits 0
ok()   { local id=$1 t=$2 e=$3; shift 3; local out; out="$("$@" 2>&1)"; local rc=$?; echo "$out" >> "$RAW"; [[ $rc -eq 0 ]] && record "$id" "$t" "$e" PASS "rc=0" || record "$id" "$t" "$e" FAIL "rc=$rc"; }
# deny ID title expected cmd...: passes when cmd exits non-zero
deny() { local id=$1 t=$2 e=$3; shift 3; local out; out="$("$@" 2>&1)"; local rc=$?; echo "$out" >> "$RAW"; [[ $rc -ne 0 ]] && record "$id" "$t" "$e" PASS "blocked (rc=$rc)" || record "$id" "$t" "$e" FAIL "unexpectedly succeeded"; }

ns_add() {  # ns_add NAME BRIDGE IP/MASK MAC
  local n=$1 br=$2 ip=$3 mac=$4
  $SUDO ip netns del "$n" 2>/dev/null
  $SUDO ip netns add "$n"
  $SUDO ip link add "v-$n" type veth peer name "p-$n"
  $SUDO ip link set "p-$n" netns "$n"
  $SUDO ip link set "v-$n" master "$br" up
  ns "$n" ip link set lo up
  ns "$n" ip link set "p-$n" address "$mac"
  ns "$n" ip addr add "$ip" dev "p-$n"
  ns "$n" ip link set "p-$n" up
  sleep 1
}
ns_del() { $SUDO ip netns del "$1" 2>/dev/null; }
nft_pkts() { $SUDO nft list table bridge labl2 2>/dev/null | awk '/counter packets/{for(i=1;i<=NF;i++) if($i=="packets") s+=$(i+1)} END{print s+0}'; }

exec > >(tee -a "$RAW") 2>&1
say "Test run $TS"

# ------------------------------------------------------------------ Stage II: WAN
say "Stage II - CHR WAN"
ok S2-1 "CHR has WAN address $CHR_WAN_IP" "address present" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ip address print terse' | grep -q '$CHR_WAN_IP/24'"
ok S2-2 "CHR default route via $HOST_WAN_IP" "route present" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ip route print terse where dst-address=0.0.0.0/0' | grep -q '$HOST_WAN_IP'"
ok S2-3 "CHR reaches the Internet (1.1.1.1)" "reply" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ping 1.1.1.1 count=2' | grep -Eq '^ *[0-9]+ +1\.1\.1\.1 +[0-9]+ +[0-9]+ +[0-9]+(ms|us)'"
ok S2-4 "NAT counter increments (masquerade works)" "packets > 0" bash -c "source '$ROOT/scripts/lib.sh'; vm_exec client1 'curl -s -m8 -o /dev/null http://example.com' 20; chr_ssh '/ip firewall nat print stats terse' | awk '/^ *[0-9]+ /{s+=\$NF} END{exit !(s>0)}'"

# ------------------------------------------------------------------ 1: LAN -> Internet
say "1. LAN -> Internet (policy: web, NTP, ping; DNS only via CHR)"
ok 1a "client1 HTTPS to Internet" "allowed" c1 "curl -sS -m10 -o /dev/null -w '%{http_code}\n' https://example.com | grep -Eq '^(200|301|302)$'"
ok 1b "client1 DNS via CHR ($CHR_LAN_IP)" "resolves" c1 "dig +short +time=3 +tries=1 @$CHR_LAN_IP example.com | grep -Eq '^[0-9]+\.'"
deny 1c "client1 SMTP/25 to Internet" "blocked by policy" c1 "nc -z -w3 1.1.1.1 25"
deny 1d "client1 direct DNS to 8.8.8.8 (DNS leak)" "blocked" c1 "dig +short +time=3 +tries=1 @8.8.8.8 example.com | grep -Eq '^[0-9]+\.'"

# ------------------------------------------------------------------ 2: LAN -> server
say "2. LAN -> Internal server $SRV_IP (SSH/HTTPS allowed)"
ok 2a "client1 -> $SRV_IP TCP/22" "allowed" c1 "nc -z -w4 $SRV_IP 22"
ok 2b "client1 -> $SRV_IP TCP/443 (content check)" "allowed" c1 "curl -sk -m8 https://$SRV_IP/ | grep -q LAB-INTERNAL-SERVER"
ok 2c "client2 -> $SRV_IP TCP/22" "allowed" c2 "nc -z -w4 $SRV_IP 22"
ok 2d "client1 ping $SRV_IP" "allowed" c1 "ping -c2 -W2 $SRV_IP"
c1 "traceroute -n -m4 -w1 $SRV_IP" 40 | tee -a "$RAW" >/dev/null

# ------------------------------------------------------------------ 3: other remote IPs
say "3. LAN -> other remote hosts / ports (denied)"
deny 3a "client1 -> $SRV_IP TCP/3389" "denied" c1 "nc -z -w3 $SRV_IP 3389"
deny 3b "client1 -> $DECOY_IP TCP/22 (other host, same subnet)" "denied" c1 "nc -z -w3 $DECOY_IP 22"
deny 3c "client1 ping $DECOY_IP" "denied" c1 "ping -c2 -W2 $DECOY_IP"
deny 3d "client1 ping remote gateway $RGW_LAN_IP" "denied" c1 "ping -c2 -W2 $RGW_LAN_IP"
c1 "nmap -Pn -n -p 22,443,3389 $SRV_IP" 60 | tee -a "$RAW" | grep -E '^(22|443|3389)/' >/dev/null
ok 3e "nmap from client1: 22,443 open and 3389 filtered" "exact port policy" bash -c "out=\$(source '$ROOT/scripts/lib.sh'; vm_exec client1 'nmap -Pn -n -p 22,443,3389 $SRV_IP' 60); echo \"\$out\"; echo \"\$out\" | grep -Eq '^22/tcp +open' && echo \"\$out\" | grep -Eq '^443/tcp +open' && echo \"\$out\" | grep -Eq '^3389/tcp +filtered'"
ok 3f "CHR counted the denies (rule hit counters)" "counters > 0" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ip firewall filter print stats terse where comment~\"DENY LAN\"' | awk '/^ *[0-9]+ /{s+=\$NF} END{exit !(s>0)}'"

# ------------------------------------------------------------------ 4/5: WAN side
say "4/5. WAN -> LAN and WAN -> CHR management"
ns_add outside "$WAN_BR" 192.168.100.50/24 02:aa:00:00:00:50
ns outside ip route add "$LAN_NET" via "$CHR_WAN_IP"
ns outside ip route add "$REMOTE_NET" via "$CHR_WAN_IP"
deny 4a "WAN host -> client1 via CHR WAN address (routed)" "denied" ns outside ping -c2 -W2 "$C1_IP"
deny 4b "WAN host -> LAN gateway $CHR_LAN_IP" "denied" ns outside ping -c2 -W2 "$CHR_LAN_IP"
ns outside ip route replace "$LAN_NET" via "$HOST_WAN_IP"
deny 4c "WAN host -> LAN via the Linux host (bypass attempt)" "denied" ns outside ping -c2 -W2 "$C1_IP"
ok 5a "nmap WAN side of CHR: no open ports" "all filtered" bash -c "out=\$($SUDO ip netns exec outside nmap -Pn -n -p 21,22,23,80,443,2000,8291,8728,8729 $CHR_WAN_IP); echo \"\$out\"; ! echo \"\$out\" | grep -Eq ' open | closed '"
ok 5b "CHR WAN input drops were logged" "log lines present" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/log print where message~\"INPUT-DROP\"' | grep -q INPUT-DROP"
deny 5c "WAN host -> CHR mgmt address $CHR_MGMT_IP (routed)" "denied" ns outside nc -z -w3 "$CHR_MGMT_IP" 22
ns_del outside
ns_add mgmtrogue "$MGMT_BR" 172.31.0.99/24 02:aa:00:00:00:99
deny 5d "Foreign host on br-mgmt (not the admin address) -> CHR SSH" "denied" ns mgmtrogue nc -z -w3 "$CHR_MGMT_IP" 22
deny 5e "Foreign host on br-mgmt -> CHR WinBox 8291" "denied" ns mgmtrogue nc -z -w3 "$CHR_MGMT_IP" 8291
ns_del mgmtrogue
ok 5f "Admin host ($HOST_MGMT_IP) -> CHR SSH works" "allowed" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/system identity print' | grep -q chr-lab"
ok 5g "No unneeded services enabled on CHR" "only ssh+winbox" bash -c "source '$ROOT/scripts/lib.sh'; ! chr_ssh '/ip service print terse where disabled=no' | grep -Eq 'name=(telnet|ftp|www|www-ssl|api|api-ssl)'"

# ------------------------------------------------------------------ 6: Host -> LAN
say "6. Host -> LAN (no L3 path; only admin access to CHR mgmt)"
deny 6a "Host ping CHR LAN address $CHR_LAN_IP" "denied" ping -c2 -W2 "$CHR_LAN_IP"
deny 6b "Host ping client1 $C1_IP" "denied" ping -c2 -W2 "$C1_IP"
deny 6c "Host SSH probe client1 $C1_IP:22" "denied" nc -z -w3 "$C1_IP" 22
ok 6d "br-lan has no IPv4 address on the host" "no address" bash -c "! ip -4 addr show dev $LAN_BR | grep -q inet"

# ------------------------------------------------------------------ 7: unauthorized VM -> LAN
say "7. Unauthorized VM (rogue port on br-lan) -> LAN"
before="$(nft_pkts)"
ns_add rogue "$LAN_BR" 10.50.0.222/24 02:de:ad:be:ef:01
deny 7a "Rogue with static IP in the LAN pings gateway" "denied" ns rogue ping -c3 -W2 "$CHR_LAN_IP"
deny 7b "Rogue ARPs for gateway" "denied" ns rogue arping -c3 -w4 -I "p-rogue" "$CHR_LAN_IP"
deny 7c "Rogue reaches client1" "denied" ns rogue ping -c2 -W2 "$C1_IP"
after="$(nft_pkts)"; echo "bridge drop counters: before=$before after=$after"
[[ "$after" -gt "$before" ]] && record 7d "L2 allow-list counters on the host increased" "frames dropped at bridge" PASS "packets $before -> $after" || record 7d "L2 allow-list counters on the host increased" "frames dropped at bridge" FAIL "packets $before -> $after"
ns_del rogue

# ------------------------------------------------------------------ 10: unauthorized server access (+ anti-spoofing)
say "10. Unauthorized access to the server / spoofing"
deny 10a "LAN address not in lan-authorized list (10.50.0.66) -> server 22" "denied" c1 "ip addr add 10.50.0.66/24 dev lan 2>/dev/null; nc -s 10.50.0.66 -z -w3 $SRV_IP 22; rc=\$?; ip addr del 10.50.0.66/24 dev lan 2>/dev/null; exit \$rc"
deny 10b "Spoofed source 10.99.9.9 from LAN -> Internet" "dropped by anti-spoof" c1 "ip addr add 10.99.9.9/32 dev lan 2>/dev/null; curl -s -m5 --interface 10.99.9.9 http://example.com >/dev/null; rc=\$?; ip addr del 10.99.9.9/32 dev lan 2>/dev/null; exit \$rc"
ok 10c "Anti-spoof raw rule hit counter" "packets > 0" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ip firewall raw print stats terse where comment~\"anti-spoof: LAN source\"' | awk '/^ *[0-9]+ /{s+=\$NF} END{exit !(s>0)}'"
deny 10d "Client1 -> client2 directly at L2 (isolated ports)" "denied (CLIENT_ISOLATION=yes)" bash -c "[[ '$CLIENT_ISOLATION' == yes ]] || exit 1; source '$ROOT/scripts/lib.sh'; vm_exec client1 'ping -c2 -W2 $C2_IP' 20"

# ------------------------------------------------------------------ 8/9: VPN disconnect / reconnect
say "8. VPN disconnect: fail closed, no bypass through WAN"
CAP="$VAR/leakcheck.pcap"; rm -f "$CAP"
$SUDO timeout 40 tcpdump -ni "$WAN_BR" -w "$CAP" "ip dst $SRV_IP or ip dst $DECOY_IP or ip dst $REMOTE_NET" >/dev/null 2>&1 &
TCPD=$!
sleep 2
rgw 'systemctl stop wg-quick@wg0' >/dev/null
log "VPN stopped on the remote gateway; waiting for netwatch (<= 25 s)"
for _ in $(seq 25); do
  chr_down="$(source "$ROOT/scripts/lib.sh"; chr_ssh '/ip route print terse where comment=vpn-route' 2>/dev/null)"
  echo "$chr_down" | grep -Eq '^ *[0-9]+ +X' && break
  sleep 1
done
echo "route state: $chr_down" >> "$RAW"
ok 8a "CHR disabled the tunnel route after VPN loss" "route disabled" bash -c "echo '$chr_down' | grep -Eq '^ *[0-9]+ +X'"
deny 8b "client1 -> $SRV_IP:22 while VPN is down" "denied (fail closed)" c1 "nc -z -w4 $SRV_IP 22"
deny 8c "client1 -> $SRV_IP:443 while VPN is down" "denied (fail closed)" c1 "curl -sk -m5 https://$SRV_IP/"
ok 8d "client1 still has Internet (only the remote subnet is cut)" "allowed" c1 "curl -sS -m10 -o /dev/null https://example.com"
ok 8e "blackhole route for the remote subnet is present" "failclosed route" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/ip route print terse where comment=failclosed-blackhole' | grep -q blackhole || chr_ssh '/ip route print terse where comment=failclosed-blackhole' | grep -q failclosed"
wait "$TCPD" 2>/dev/null; $SUDO pkill -f "tcpdump -ni $WAN_BR -w $CAP" 2>/dev/null; sleep 1
leaked="$($SUDO tcpdump -nr "$CAP" 2>/dev/null | wc -l)"
echo "packets towards the remote subnet seen on br-wan while VPN was down: $leaked" >> "$RAW"
[[ "$leaked" -eq 0 ]] && record 8f "Packet capture on br-wan: no remote-subnet traffic leaked" "0 packets" PASS "leaked=0" || record 8f "Packet capture on br-wan: no remote-subnet traffic leaked" "0 packets" FAIL "leaked=$leaked"

say "9. VPN reconnect"
rgw 'systemctl start wg-quick@wg0' >/dev/null
up=no
for _ in $(seq 60); do
  vm_exec client1 "nc -z -w2 $SRV_IP 22" 8 >/dev/null 2>&1 && { up=yes; break; }
  sleep 2
done
[[ $up == yes ]] && record 9a "Automatic recovery after the VPN returns" "server reachable again" PASS "reconnected" || record 9a "Automatic recovery after the VPN returns" "server reachable again" FAIL "not restored in 120 s"
ok 9b "WireGuard handshake is recent on the CHR" "handshake seen" bash -c "source '$ROOT/scripts/lib.sh'; chr_ssh '/interface wireguard peers print detail' | grep -q last-handshake"

# ------------------------------------------------------------------ extras
say "Extras - encryption, DNS, IPv6"
$SUDO timeout 12 tcpdump -ni "$WAN_BR" -c 6 'udp port 51820 or udp port 13231' -w "$VAR/wg.pcap" >/dev/null 2>&1 &
sleep 1; c1 "curl -sk -m6 https://$SRV_IP/ >/dev/null" 15 >/dev/null; wait 2>/dev/null
ok E1 "Tunnel traffic on br-wan is WireGuard only (no plaintext marker)" "marker absent" bash -c "! $SUDO tcpdump -nAr '$VAR/wg.pcap' 2>/dev/null | grep -q LAB-INTERNAL-SERVER"
deny E2 "IPv6: client1 has no default route / cannot reach IPv6 Internet" "no v6 bypass" c1 "ip -6 route show default | grep -q . && ping -6 -c2 -W2 2606:4700:4700::1111"
ok E3 "DNS leak check: only the CHR answers (resolver is $CHR_LAN_IP)" "resolver = CHR" c1 "grep -q 'nameserver $CHR_LAN_IP' /etc/resolv.conf"

# ------------------------------------------------------------------ report
{
  echo "# Test results"
  echo
  echo "Run: $TS - **$PASS passed, $FAIL failed**"
  echo
  echo "| ID | Check | Expected | Result | Evidence |"
  echo "|----|-------|----------|--------|----------|"
  while IFS=$'\t' read -r id t e v ev; do echo "| $id | $t | $e | $v | $ev |"; done < "$RESULTS"
  echo
  echo "Sanitised raw log: \`evidence/sanitized-logs/tests-$TS.log\`"
} > "$ROOT/reports/test-results.md"
"$ROOT/scripts/sanitize.sh" < "$RAW" > "$ROOT/evidence/sanitized-logs/tests-$TS.log"
echo
log "Summary: $PASS passed, $FAIL failed -> reports/test-results.md"
[[ $FAIL -eq 0 ]]
