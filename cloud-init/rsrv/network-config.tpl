version: 1
config:
  - type: physical
    name: remote
    mac_address: "@@RSRV_MAC@@"
    subnets:
      - type: static
        address: @@SRV_IP@@/24
        gateway: @@RGW_LAN_IP@@
  - type: nameserver
    address: [@@HOST_WAN_IP@@]
