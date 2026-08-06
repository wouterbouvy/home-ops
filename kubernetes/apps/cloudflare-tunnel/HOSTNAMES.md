# Cloudflare Tunnel public hostnames

**Source of truth:** [`ingress.yaml`](ingress.yaml). An Argo CD **PostSync** Job runs [`cloudflare-tunnel-apply.sh`](cloudflare-tunnel-apply.sh) (also via `mise run cloudflare-tunnel-apply`) to:

1. PUT the tunnel ingress configuration (hostname → in-cluster HTTP Service)
2. Upsert proxied DNS CNAMEs → `<TUNNEL_ID>.cfargotunnel.com` (deletes conflicting A/AAAA)
3. Upsert wildcard `*.home-ops.nl` the same way

Dashboard edits in Zero Trust are overwritten on the next sync.

| Public hostname | Origin URL |
|-----------------|------------|
| `authentik.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `argocd.home-ops.nl` | `http://argocd-server.argo-system.svc.cluster.local:80` |
| `grafana.home-ops.nl` | `http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80` |
| `hubble.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `longhorn.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `headlamp.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |

Proxy apps (Hubble / Longhorn / Headlamp) **must** use Authentik’s Service.

**1Password**

- Item `cloudflare-tunnel`: `TUNNEL_TOKEN`, `TUNNEL ID` (or `TUNNEL_ID`), `ACCOUNT_ID`, `ZONE_ID`
- Item `cloudflare` / `CLOUDFLARE_DNS_TOKEN` (same token as cert-manager): needs **Zone DNS Edit** and **Account → Cloudflare Tunnel → Edit**

**Local apply:** `mise run cloudflare-tunnel-apply` (loads IDs/token from 1Password when env unset). `DRY_RUN=1` prints planned calls.

LAN can keep using Gateway VIP `https://10.0.8.120` via local/split DNS.
