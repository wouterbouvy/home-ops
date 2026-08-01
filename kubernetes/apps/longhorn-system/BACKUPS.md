# Longhorn PVC backups (NFS)

Longhorn uploads volume backups to a **NAS NFSv4 export**. This covers every Longhorn volume in the `default` recurring-job group (the default for volumes from the `longhorn` StorageClass), including Prometheus, Loki, and the CNPG Postgres PVC today.

**Postgres note:** a Longhorn backup of the CNPG volume is **crash-consistent only**. Prefer CloudNativePG object-store / PITR backups for database recovery (follow-up). Use these PVC backups as a last resort for the data directory.

Config lives in:

| File | Role |
|------|------|
| [`values.yaml`](values.yaml) | `defaultBackupStore.backupTarget` (NFS URL), `allowRecurringJobWhileVolumeDetached` |
| [`recurringjob-backup-daily.yaml`](recurringjob-backup-daily.yaml) | Daily schedule + retention |

## NAS setup

| Item | Value |
|------|--------|
| Host | `datadoos.im25.nl` |
| NFS export | `/mnt/ssd_z2/kubernetes` (`showmount -e`) |
| home-ops folder | `/mnt/ssd_z2/kubernetes/home-ops` (cluster-specific; do not share with other clusters) |
| Longhorn URL | `nfs://datadoos.im25.nl:/mnt/ssd_z2/kubernetes/home-ops` |

1. On the NAS (TrueNAS), export `/mnt/ssd_z2/kubernetes` over **NFSv4** to clients that include this workstation and the home-ops nodes (`10.0.8.0/24`). Backup mounts run on cluster nodes; ops/mkdir can be done from a Mac with the share mounted.
2. Make the share **writable** for Longhorn. If the mount is empty/`root:wheel` `755` and `mkdir` fails with *Permission denied* / *Operation not permitted*, enable **Maproot User = `root`** (or equivalent) on the NFS share, or relax dataset ACLs so clients can create directories.
3. Create the dedicated subdirectory **`home-ops`** on the export (cluster-specific; keep other clusters in sibling folders):

   ```bash
   # from a machine that can mount the share read-write
   mount_nfs -o rw,resvport datadoos.im25.nl:/mnt/ssd_z2/kubernetes /path/to/mnt
   mkdir -p /path/to/mnt/home-ops
   chmod 777 /path/to/mnt/home-ops   # or chown to the mapped UID
   ```

4. **Do not** enable NAS-side retention, scrubbing, or lifecycle rules that delete files under `home-ops`. Longhorn owns the backupstore lifecycle; external deletes corrupt it.
5. The URL is set in [`values.yaml`](values.yaml) as `defaultBackupStore.backupTarget`. Optional mount options if needed: `?nfsOptions=nolock,nfsvers=4.1` (Longhorn adds `soft` / timeouts when `nfsOptions` is set).

6. Merge / sync the Longhorn Argo app, then verify (below).

## Verify the backup target

UI: [longhorn.home-ops.nl](https://longhorn.home-ops.nl) → **Setting** → **Backup Target** (default). Status should be available.

CLI (Longhorn 1.12 uses a `BackupTarget` CR, not the old `backup-target` Setting):

```bash
kubectl -n longhorn-system get backuptargets.longhorn.io default -o wide
kubectl -n longhorn-system get backuptargets.longhorn.io default -o jsonpath='{.spec.backupTargetURL}{" avail="}{.status.available}{"\n"}'
```

List remote backup volumes after the first successful backup:

```bash
kubectl -n longhorn-system get backupvolumes.longhorn.io
kubectl -n longhorn-system get backups.longhorn.io
```

## Create backups

### Automatic (default)

RecurringJob `backup-daily` in `longhorn-system`:

| Field | Value |
|-------|--------|
| Schedule | `0 3 * * *` (daily 03:00 UTC) |
| Retain | `14` (last 14 backups **per volume** for this job) |
| Group | `default` (all default StorageClass volumes) |
| Full backup | every 7 incrementals (`full-backup-interval: "7"`) |

Confirm the job and that volumes are in group `default`:

```bash
kubectl -n longhorn-system get recurringjobs.longhorn.io
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=NAME:.metadata.name,PVC:.status.kubernetesStatus.pvcName,GROUPS:.spec.recurringJobSelector
```

Volumes without an explicit selector use the `default` group and pick up `backup-daily`.

### Manual (UI)

1. Open Longhorn UI → **Volume**.
2. Select the volume → **Create Backup** (optionally add labels).
3. Watch **Backup** until the backup is completed; confirm files appear on the NAS export.

### Manual (CLI)

Create an on-demand snapshot, then a Backup CR that references it (UI is simpler). Example pattern after you have a snapshot name from the volume:

```bash
# List snapshots for a volume
kubectl -n longhorn-system get snapshots.longhorn.io -l longhornvolume=<volume-name>

# Create a backup from a snapshot (name/labels as needed)
kubectl -n longhorn-system apply -f - <<'EOF'
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: ondemand-example
  namespace: longhorn-system
  labels:
    backup-target: default
spec:
  snapshotName: <snapshot-name>
  backupMode: full
EOF
```

Prefer the UI for one-off backups unless you are automating.

## Restore a backup

Restores create a **new** Longhorn volume from the backupstore. They do not overwrite an in-use volume in place.

### UI (recommended)

1. Longhorn UI → **Backup**.
2. Find the volume / backup → **Restore**.
3. Choose a new volume name and size (≥ backup size). Attach later or create a PV/PVC.

### Swap an app PVC onto a restored volume

High-level flow for a generic Deployment/StatefulSet PVC:

1. Scale the workload to `0` (or delete the pod) so the old volume detaches.
2. Restore the backup to a **new** Longhorn volume (UI or API).
3. Create a PV that references the restored Longhorn volume name (`volumeHandle` / CSI volumeHandle = Longhorn volume name), and a PVC bound to that PV (same name/namespace the app expects), **or** use Longhorn’s “Create PersistentVolume/PersistentVolumeClaim” helpers in the UI when restoring.
4. Scale the workload back up.
5. Delete the old unused volume only after you confirm the app is healthy.

Exact PV YAML depends on the CSI driver parameters Longhorn uses in your cluster; the UI restore wizard avoids hand-writing them.

### CNPG / Postgres

Do **not** treat a restored Postgres PVC as a supported HA recovery path. Prefer CNPG `Backup` / `ScheduledBackup` to an object store and CNPG restore procedures. A Longhorn PVC restore may bring the data directory back after a disaster, but expect recovery/WAL issues and plan for `pg_resetwal`-class pain—or rebuild the cluster from a proper DB backup.

## Retention

| Mechanism | Behavior |
|-----------|----------|
| RecurringJob `retain: 14` | Keep the newest **14** successful backups **per volume** for `backup-daily`. Older ones are deleted from the NFS store by Longhorn. |
| NAS lifecycle rules | **Forbidden** on this export. |
| Failed backups | Longhorn `failed-backup-ttl` (minutes) cleans failed backup CRs; see Settings. |

### Change retention

Edit `spec.retain` in [`recurringjob-backup-daily.yaml`](recurringjob-backup-daily.yaml), merge to `main`, let Argo sync.

### Add a longer weekly job (optional)

Add a second RecurringJob (e.g. `backup-weekly`, `cron: "0 4 * * 0"`, `retain: 8`, same `groups: [default]`). Retention counts are **per job**; daily and weekly keep separate chains.

## Failure modes

| Symptom | Likely cause |
|---------|----------------|
| BackupTarget `available: false`, empty URL | `defaultBackupStore.backupTarget` not set / not synced |
| Target unavailable, mount errors | NAS down, wrong path, missing `home-ops` dir, NFSv3-only export, firewall |
| `Permission denied` / `Operation not permitted` on mount or mkdir | Share not writable; set NFS **Maproot User = root** (or relax ACLs) and recreate `home-ops` |
| Longhorn BackupTarget: `mount.nfs4: Operation not permitted` (but a privileged test pod can mount) | TrueNAS NFS share requires privileged source ports. Enable **Allow non-privileged ports** (`insecure`) on the share, or equivalent. See [Longhorn #6114](https://github.com/longhorn/longhorn/issues/6114). |
| Soft timeout / hung backups | Unstable NFS; tune `nfsOptions` (`timeo`, `nfsvers=4.1`) |
| Backup CRs disappear after NFS blip | Upstream behavior: empty NFS responses can clear backup CRs on resync—fix NFS and re-backup |
| Recurring job skipped on detached volume | Ensure `allowRecurringJobWhileVolumeDetached: true` is synced |

Debug:

```bash
kubectl -n longhorn-system get backuptargets.longhorn.io default -o yaml
kubectl -n longhorn-system get backups.longhorn.io -o wide
kubectl -n longhorn-system logs -l app=longhorn-manager --tail=100 | rg -i 'backup|nfs|error'
```

## Summary of defaults

- **Target:** `nfs://datadoos.im25.nl:/mnt/ssd_z2/kubernetes/home-ops`
- **Schedule:** daily 03:00 UTC, full every 7 incrementals.
- **Retention:** 14 backups per volume for `backup-daily`.
- **Scope:** Longhorn volumes in group `default`.
