# Omni cluster template patches

Patches referenced by Omni cluster templates
([`omni-home-ops.yaml`](../omni-home-ops.yaml), [`omni-mgmt.yaml`](../omni-mgmt.yaml)).

Layout:

- `base/` — shared across clusters (`global/` for all machines, `controlplane/` for control planes)
- `overlays/<cluster>/` — cluster-specific patches (NICs, disks, encryption, user volumes, L2 VIP)

Omni applies the listed `patches[].file` entries from each template; there is no
talhelper in this repo.
