# SecureBoot + TPM (home-ops)

Long-term ops notes for home-ops. SecureBoot and TPM LUKS are already in production on delta / echo / foxtrot.

## Why SecureBoot is required

Talos TPM encryption seals to a **PCR-11 signed UKI policy**. That public key only exists on SecureBoot UKIs (`/.extra/tpm2-pcr-public-key.pem`). Non-SecureBoot images cannot enroll or unlock TPM volumes.

Omni selects `factory.talos.dev/metal-installer-secureboot/<schematic>:v…` when the machine reports `secureBoot: true`. There is **no** cluster-template `secureboot:` flag — nodes must boot SecureBoot media (or an already-installed SecureBoot UKI) so Omni sees that state.

## Current configuration

| Item | Value |
|------|--------|
| Omni media preset | `home-ops-sb-1.13.7` (SecureBoot, same extensions as [`omni-home-ops.yaml`](omni-home-ops.yaml)) |
| Image Factory schematic | `8b2c893977a01cb1fe2aa938ed38c989c89f51c4db5102d149b55550d12a2372` |
| Install disk | `/dev/sda` (SATA system SSD) on each Machine; NVMe reserved for Longhorn |
| STATE / EPHEMERAL | LUKS2 + TPM, `options.pcrs: []` ([`disk-encryption.yaml`](patches/overlays/home-ops/controlplane/disk-encryption.yaml)) |
| `u-longhorn` | LUKS2 + TPM, `options.pcrs: []` ([`longhorn-uservolume.yaml`](patches/overlays/home-ops/controlplane/longhorn-uservolume.yaml)) |

`pcrs: []` means **PCR 11 only** (skip PCR 7). OEM firmware often changes PCR 7 across install vs reboot (`TPM_RC_BAD_AUTH`). Keep this unless you deliberately re-seal to PCR 7.

Signing keys stay in Omni / Image Factory — never commit private SecureBoot or PCR keys. Downloaded ISOs go under `secureboot-media/` (gitignored).

### Download SecureBoot ISO

```bash
omnictl media preset list
# home-ops-sb-1.13.7 — amd64, --secureboot

mkdir -p secureboot-media
omnictl media download home-ops-sb-1.13.7 --format iso --talos-version v1.13.7 \
  --output secureboot-media/
```

Bump the preset / Talos version when upgrading; keep extensions aligned with [`omni-home-ops.yaml`](omni-home-ops.yaml).

## Upgrades

- Talos upgrades **must** use SecureBoot installer/UKI assets for the **same** Omni schematic (or a new SecureBoot schematic that replaces it deliberately).
- Omni denies out-of-band `talosctl upgrade` (`PermissionDenied`); upgrade via Omni only.
- After a schematic or major UKI change, confirm volumes still unlock (rolling reboot).

## Re-provision / replace a node

Firmware: TPM 2.0 on; SecureBoot keys enrolled (Setup Mode → enroll from ISO boot menu: **Enroll Secure Boot keys: auto** on bare metal).

1. Boot the node from the SecureBoot ISO into maintenance (`secureBoot: true`).
2. If reusing disks with stale LUKS: wipe system disk and/or `nvme0n1` in maintenance (`talosctl -n <ip> wipe disk … --insecure --drop-partition`).
3. `mise run omni-sync` (and `omni-bootstrap` if the cluster was torn down).
4. If install fails with `TPM_RC_BAD_AUTH`: **Clear TPM** in UEFI, wipe system disk, re-boot SecureBoot ISO, sync again.

## Verify

```bash
omnictl cluster status home-ops

for n in 10.0.8.3 10.0.8.4 10.0.8.5; do
  echo "=== $n ==="
  talosctl -n "$n" get securitystate -o jsonpath='{.spec.secureBoot}{"\n"}'
  talosctl -n "$n" ls /.extra
  talosctl -n "$n" get volumestatus
done
```

Expect: `secureBoot: true`, `tpm2-pcr-public-key.pem` under `/.extra`, and STATE / EPHEMERAL / `u-longhorn` ready (LUKS).

## Recovery

- Lost SecureBoot keys or SecureBoot disabled → TPM volumes will not unlock → wipe + re-encrypt (re-provision path above).
- Stale Longhorn LUKS after reset → wipe `nvme0n1` in maintenance before re-syncing the UserVolumeConfig.
- Firmware SecureBoot dbx updates that break unlock: keep `pcrs: []` (PCR 11 only); if still broken, wipe and re-enroll after Clear TPM.
