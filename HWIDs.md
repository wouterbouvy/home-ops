Hotel
    Installdisk serial: SS0L68728L1TH83107TD
    Longhorn: /dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T708722V

India
    Installdisk serial: SS0L68728L1TH83107SV
    Longhorn: /dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NX0T106248F

Juliett
    Installdisk serial: SS0L68728L1TH83107TF
    Longhorn: /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_1TB_S5H9NS0N410306N

Golf:

kind: Machine
# name: b5dd64c8-53a8-be17-4fbc-1c697ad8ff08
# patches:
#   - name: NIC config
#     inline:
#       machine:
#         network:
#           hostname: golf
#           interfaces:
#             - interface: bond0
#               dhcp: false
#               vlans:
#                 - vlanId: 8
#                   addresses:
#                     - "10.0.8.40/24"
#                   routes:
#                     - network: 0.0.0.0/0
#                       gateway: 10.0.8.254
#               bond:
#                 mode: 802.3ad
#                 lacpRate: fast
#                 xmitHashPolicy: layer3+4
#                 miimon: 100
#                 deviceSelectors:
#                   - driver: mlx5_core
#             - interface: enp91s0
#               ignore: true
#           nameservers:
#             - 10.0.8.254
#   - name: installdisk
#     inline:
#       machine:
#         install:
#           diskSelector:
#             serial: "S674NF0R214511"
#   - name: longhorn
#     inline:
#       machine:
#         disks:
#         - device: /dev/disk/by-id/nvme-MZ1LB1T9HBLS-000FB_S5XANA0T103945
#           partitions:
#             - mountpoint: /var/mnt/longhorn



  # - name: longhorn
  #   inline:
  #     machine:
  #       disks:
  #       - device: /dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S649NL1T708722V
  #         partitions:
  #           - mountpoint: /var/mnt/longhorn