#cloud-config
# Simulated protected internal server 10.60.0.10 (SSH + HTTPS) plus a "decoy" neighbour 10.60.0.20
# and a TCP/3389 listener, so the deny rules can be proven against real open ports.
hostname: rsrv
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
packages: [nginx, openssl, qemu-guest-agent, tcpdump, iputils-ping]
write_files:
  - path: /root/lab-nginx.conf
    content: |
      server {
        listen 443 ssl default_server;
        ssl_certificate /etc/ssl/lab.crt;
        ssl_certificate_key /etc/ssl/lab.key;
        root /var/www/lab;
        index index.html;
      }
  - path: /etc/systemd/system/fake-rdp.service
    content: |
      [Unit]
      Description=Lab listener on TCP/3389 (to prove firewall denies it)
      After=network.target
      [Service]
      ExecStart=/usr/bin/python3 -m http.server 3389 --directory /var/www/lab
      Restart=always
      [Install]
      WantedBy=multi-user.target
  - path: /etc/sysctl.d/99-lab.conf
    content: |
      net.ipv6.conf.all.disable_ipv6=1
runcmd:
  - [ systemctl, enable, --now, qemu-guest-agent ]
  - [ sysctl, --system ]
  - [ sh, -c, "ip addr show dev remote | grep -q @@DECOY_IP@@ || ip addr add @@DECOY_IP@@/24 dev remote" ]
  - [ mkdir, -p, /var/www/lab ]
  - [ sh, -c, "echo 'LAB-INTERNAL-SERVER @@SRV_IP@@' > /var/www/lab/index.html" ]
  - [ sh, -c, "openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj /CN=srv.lab -keyout /etc/ssl/lab.key -out /etc/ssl/lab.crt" ]
  - [ sh, -c, "rm -f /etc/nginx/sites-enabled/default; cp /root/lab-nginx.conf /etc/nginx/conf.d/lab.conf" ]
  - [ systemctl, restart, nginx ]
  - [ systemctl, daemon-reload ]
  - [ systemctl, enable, --now, fake-rdp ]
