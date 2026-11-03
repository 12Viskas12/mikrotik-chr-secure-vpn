#cloud-config
# Authorized LAN client 2 (gets its fixed address from the CHR DHCP static lease).
hostname: client2
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
ssh_pwauth: true
package_update: true
packages: [qemu-guest-agent, nmap, traceroute, tcpdump, dnsutils, curl, netcat-openbsd, iputils-ping, iputils-arping]
runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
