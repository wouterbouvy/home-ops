# Omni bootstrap manifests

Raw Kubernetes YAML synced by Omni from the cluster template
(`omni-home-ops.yaml` → `kubernetes.manifests`). Omni does not support Helm,
Kustomize, or remote URLs.

Generated YAML in this directory is **gitignored**. Always render locally before
sync (`omni-sync` runs `manifests-render` automatically).

| File | Purpose |
| --- | --- |
| `gateway-api.yaml` | Gateway API standard CRDs v1.6.1 (TLSRoute/TCPRoute/UDPRoute at v1) |
| `cilium.yaml` | Cilium 1.20.0 rendered from Helm |
| `coredns.yaml` | CoreDNS 1.46.2 rendered from Helm |
| `spegel.yaml` | Spegel 0.7.4 rendered from Helm |
| `argo-cd.yaml` | Argo CD 10.2.1 rendered from Helm (includes `argo-system` Namespace + CRDs) |

All chart manifests use `mode: one-time` so Argo can take over after bootstrap.

## Generate manifests

```bash
mise run manifests-render
```

Sources of truth:

| Manifest | Values | Chart / release version (in mise task) |
| --- | --- | --- |
| `gateway-api.yaml` | GitHub release URL | v1.6.1 standard-install |
| `cilium.yaml` | `kubernetes/apps/kube-system/cilium/values.yaml` | 1.20.0 |
| `coredns.yaml` | `kubernetes/apps/kube-system/coredns/values.yaml` | 1.46.2 |
| `spegel.yaml` | `kubernetes/apps/kube-system/spegel/values.yaml` | 0.7.4 |
| `argo-cd.yaml` | `kubernetes/apps/argo-system/values.yaml` | 10.2.1 |

Keep versions aligned with the corresponding Argo Applications and
`kubernetes/system/gateway-api/kustomization.yaml`. Bootstrap Argo uses
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
