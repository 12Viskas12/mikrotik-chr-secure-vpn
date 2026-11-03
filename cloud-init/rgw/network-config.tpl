version: 1
config:
  - type: physical
    name: wan
    mac_address: "@@RGW_MAC_WAN@@"
    subnets:
      - type: static
        address: @@RGW_WAN_IP@@/24
        gateway: @@HOST_WAN_IP@@
  - type: physical
    name: remote
    mac_address: "@@RGW_MAC_REMOTE@@"
    subnets:
      - type: static
        address: @@RGW_LAN_IP@@/24
  - type: nameserver
    address: [@@HOST_WAN_IP@@]
