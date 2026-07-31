# Omni bootstrap manifests

Raw Kubernetes YAML synced by Omni from the cluster template
(`omni-home-ops.yaml` → `kubernetes.manifests`). Omni does not support Helm,
Kustomize, or remote URLs.

Generated YAML in this directory is **gitignored**. Always render locally before
sync (`omni-sync` runs `manifests-render` automatically).

Versions come from [`kubernetes/versions.env`](../../../versions.env).

| File | Purpose |
| --- | --- |
| `gateway-api.yaml` | Gateway API standard CRDs |
| `cilium.yaml` | Cilium rendered from Helm |
| `coredns.yaml` | CoreDNS rendered from Helm |
| `spegel.yaml` | Spegel rendered from Helm |
| `argo-cd.yaml` | Argo CD rendered from Helm (includes `argo-system` Namespace + CRDs) |

All chart manifests use `mode: one-time` so Argo can take over after bootstrap.

## Generate manifests

```bash
mise run manifests-render
```

Sources of truth:

| Manifest | Values | Version pin |
| --- | --- | --- |
| `gateway-api.yaml` | GitHub release URL | `GATEWAY_API_VERSION` |
| `cilium.yaml` | `kubernetes/apps/kube-system/cilium/values.yaml` | `CILIUM_CHART_VERSION` |
| `coredns.yaml` | `kubernetes/apps/kube-system/coredns/values.yaml` | `COREDNS_CHART_VERSION` |
| `spegel.yaml` | `kubernetes/apps/kube-system/spegel/values.yaml` | `SPEGEL_CHART_VERSION` |
| `argo-cd.yaml` | `kubernetes/apps/argo-system/values.yaml` | `ARGOCD_CHART_VERSION` |

Keep pins aligned with the corresponding Argo Applications. Bootstrap Argo uses
`values.yaml` only; HA values are applied later by the Argo CD Application.

## Verify after sync

```bash
mise run omni-sync
omnictl get clusterkubernetesmanifestsstatuses home-ops
kubectl get nodes
kubectl -n kube-system get pods -l app.kubernetes.io/part-of=cilium
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get pods -l app.kubernetes.io/name=spegel
kubectl -n argo-system get pods -l app.kubernetes.io/part-of=argocd
```

Then finish bootstrap (`mise run omni-bootstrap`) to create the 1Password ESO token and apply the root `apps` Application.
