# SecureBoot + TPM cutover (home-ops)

## Why SecureBoot first

Omni picks `factory.talos.dev/metal-installer-secureboot/<schematic>:v…` only when the machine reports `secureBoot: true` (from SecureBoot UKI / maintenance ISO). There is no cluster-template `secureboot:` flag — boot the SecureBoot ISO **before** `omni-sync`.

## Phase 0 — Media

```bash
omnictl media preset list
# home-ops-sb-1.13.7 — amd64, Talos 1.13.7, --secureboot

mkdir -p secureboot-media
omnictl media download home-ops-sb-1.13.7 --format iso --talos-version v1.13.7 \
  --output secureboot-media/
```

ISO: `secureboot-media/home-ops-sb-1.13.7-v1.13.7-8b2c89.iso`  
Schematic: `8b2c893977a01cb1fe2aa938ed38c989c89f51c4db5102d149b55550d12a2372`

Firmware per node: TPM 2.0 on; clear SecureBoot keys → **Setup Mode**; USB first. On bare metal: Esc → **Enroll Secure Boot keys: auto**.

## Phase 1 — Full cluster SecureBoot reinstall

### 1. Tear down Omni cluster

```bash
mise run omni-reset
```

### 2. Boot all three from SecureBoot ISO (maintenance + `secureBoot: true`)

Wipe **NVMe** before sync if a prior `u-longhorn` LUKS layout is present:

```bash
# from maintenance (--insecure); use each node's reachable IP
talosctl -n <ip> wipe disk nvme0n1 --insecure --drop-partition
```

Verify:

```bash
omnictl get machinestatus -o yaml | rg 'hostname:|maintenance:|secureboot:'
# all three: maintenance: true, secureboot: true
```

### 3. Sync

Template pins `install.disk: /dev/sda`. STATE / EPHEMERAL use **TPM** with `options.pcrs: []` (PCR 11 only). `u-longhorn` is commented out until NVMe wipe post-bootstrap.

If install fails with `TPM_RC_BAD_AUTH`: **Clear TPM** in UEFI on that node (required after failed seal attempts / DA lock), wipe system disk, re-boot SecureBoot ISO, then sync again.

```bash
mise run omni-sync
mise run omni-bootstrap   # after nodes Ready
```

### 4. Verify

```bash
for n in 10.0.8.3 10.0.8.4 10.0.8.5; do
  echo "=== $n ==="
  talosctl -n "$n" get securitystate -o jsonpath='{.spec.secureBoot}{"\n"}'
  talosctl -n "$n" ls /.extra
done
kubectl get nodes
omnictl cluster status home-ops
```

## Encryption patches

- [`disk-encryption.yaml`](patches/overlays/home-ops/controlplane/disk-encryption.yaml) — STATE / EPHEMERAL: `tpm: {}`
- [`longhorn-uservolume.yaml`](patches/overlays/home-ops/controlplane/longhorn-uservolume.yaml) — `tpm: {}`

## Recovery

- Lost SecureBoot keys / SB disabled → TPM volumes will not unlock → wipe + re-encrypt.
- Stale LUKS on NVMe after reset → wipe `nvme0n1` in maintenance before re-sync.
- Omni denies out-of-band `talosctl upgrade` (`PermissionDenied`); use Omni + SecureBoot installers only.
