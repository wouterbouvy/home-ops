# home-ops

Talos + Omni bootstrap and Argo CD GitOps for `home-ops` and (scaffold) `management`.

## Workflow

- Work on a branch and open a PR; **do not push straight to `main`**.
- CI (`kubeconform` + Omni template validate) must stay green before merge.
- Argo on each cluster syncs from `main` after merge.

## Layout

```text
kubernetes/
  bootstrap/                 Omni templates + root apps Applications
  argo/
    common/                  Shared Argo Applications (platform)
    clusters/home-ops/       home-ops extras (e.g. Longhorn) + kustomize
    clusters/mgmt/           management extras (none yet) + kustomize
  apps/                      Helm values and extra manifests
  versions.env               Shared chart/CRD pins for Omni bootstrap render
```

Each cluster runs **its own Argo CD** (no hub/spoke). Shared apps live in `argo/common/`; per-cluster workloads live under `argo/clusters/<name>/`.

```mermaid
flowchart TD
  git[Git main]
  subgraph homeOps [home-ops]
    argoHO[Argo]
    appsHO[common + home-ops extras]
    argoHO --> appsHO
  end
  subgraph mgmt [management later]
    argoMgmt[Argo]
    appsMgmt[common + mgmt extras]
    argoMgmt --> appsMgmt
  end
  git --> argoHO
  git --> argoMgmt
```

## Prerequisites

- [mise](https://mise.jdx.dev/) (`mise install` from [`.mise.toml`](.mise.toml))
- Local-only files (gitignored): `omniconfig`, `kubeconfig`, `talosconfig`, `HWIDs.md`

## Bootstrap (home-ops)

```bash
mise run omni-sync       # render manifests, sync Omni template, merge kube/talos contexts
mise run omni-bootstrap  # wait for nodes, seed 1Password token, apply root apps Application
```

Omni installs Gateway API CRDs, Cilium, CoreDNS, Spegel, and Argo CD once (`mode: one-time`). Day-2 is owned by Argo from `kubernetes/argo/clusters/home-ops`.

Root Application: [`kubernetes/bootstrap/argo-apps.yaml`](kubernetes/bootstrap/argo-apps.yaml).

Chart/CRD versions for bootstrap: [`kubernetes/versions.env`](kubernetes/versions.env). Keep Argo Application `targetRevision` values aligned when merging Renovate bumps.

### kubectl / talosctl contexts

Sync tasks **merge** contexts into the shared `kubeconfig` and `talosconfig` files:

| Context | Cluster |
|---------|---------|
| `home-ops` (default) | home-ops |
| `management` | management (after `omni-mgmt-sync`) |

After any sync, the default kubectl/talos context is reset to **home-ops**.

## Management cluster (scaffold)

```bash
mise run omni-mgmt-validate
mise run omni-mgmt-sync    # merges management contexts; keeps home-ops as default
# mise run omni-mgmt-reset
```

Full mgmt bootstrap and testing still need Omni machine wiring later. When ready, apply [`kubernetes/bootstrap/argo-apps-mgmt.yaml`](kubernetes/bootstrap/argo-apps-mgmt.yaml) on that cluster’s Argo.

## Ingress and TLS

| Item | Value |
|------|--------|
| Public domain | `home-ops.nl` |
| External Gateway VIP | `10.0.8.120` |
| Internal Gateway VIP | `10.0.8.110` |
| Example hosts | `argocd.home-ops.nl`, `longhorn.home-ops.nl` |

**TLS uses Let's Encrypt staging on purpose** while the lab is under active change:

- ClusterIssuer: `letsencrypt-staging`
- Certificate / secret: `home-ops-nl-staging` → `home-ops-nl-staging-tls`
- Browsers will show a trust warning (staging CA). That is expected.
- Production issuer stays commented until a deliberate cutover.

Point Cloudflare DNS for `*.home-ops.nl` at `10.0.8.120`. Only the Gateway **https** listener accepts routes from all namespaces.

### Cert bootstrap order

1. External Secrets (`sync-wave: -2`) + `1password-token`
2. cert-manager chart (`-1`)
3. Cloudflare ExternalSecret then ClusterIssuer (`cert-manager-config` wave `0`, issuer resource wave `1`)
4. Gateway Certificate → HTTPS routes

## SecureBoot / TPM

Talos TPM disk encryption needs a **SecureBoot UKI** (`/.extra/tpm2-pcr-public-key.pem`). Non-SecureBoot images cannot enroll TPM LUKS keys.

| Item | Value |
|------|--------|
| Omni media preset | `home-ops-sb-1.13.7` (SecureBoot, Talos **v1.13.7**, same extensions as [`omni-home-ops.yaml`](kubernetes/bootstrap/talos/omni-home-ops.yaml)) |
| Image Factory schematic | `8b2c893977a01cb1fe2aa938ed38c989c89f51c4db5102d149b55550d12a2372` |
| ISO (preferred) | `omnictl media download home-ops-sb-1.13.7 --format iso --talos-version v1.13.7 --output secureboot-media/` |
| Install disk (template) | `/dev/sda` on each Machine in [`omni-home-ops.yaml`](kubernetes/bootstrap/talos/omni-home-ops.yaml) |

Signing keys stay in Omni / Image Factory — do not commit private SecureBoot/PCR keys. Downloaded ISOs live under `secureboot-media/` (gitignored).

**Prerequisites (firmware, per node):** TPM 2.0 on; clear/reset SecureBoot keys so UEFI is in **Setup Mode**; boot from USB written with the SecureBoot ISO. On bare metal, enroll keys from the ISO boot menu (`Enroll Secure Boot keys: auto`) — auto-enroll is VM-only by default.

**Fresh SecureBoot install:** tear down with `mise run omni-reset`, boot all nodes from the SecureBoot ISO (maintenance + `secureBoot: true`), then `mise run omni-sync`. Omni selects `metal-installer-secureboot` from the machine security state — there is no template `secureboot:` flag. STATE, EPHEMERAL, and `u-longhorn` encrypt with **TPM** at install.

**Cutover order:** SecureBoot ISO → `omni-sync` with TPM LUKS on STATE / EPHEMERAL / `u-longhorn`. Full steps: [`kubernetes/bootstrap/talos/SECUREBOOT-TPM.md`](kubernetes/bootstrap/talos/SECUREBOOT-TPM.md).

**Ongoing:** Talos upgrades must use SecureBoot installer/UKI assets for the same schematic. Firmware dbx changes can break PCR 7 unlock — then set `tpm.options.pcrs: []` (PCR 11 only). Lost SecureBoot keys → TPM volumes will not unlock; recovery is wipe + re-encrypt.
