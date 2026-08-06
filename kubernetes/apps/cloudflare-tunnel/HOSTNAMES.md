# Cloudflare Tunnel public hostnames

Configure these in **Zero Trust → Networks → Tunnels → [home-ops] → Public Hostname**.
Type **HTTP**; enable Cloudflare DNS for each name when prompted.

| Public hostname | Origin URL |
|-----------------|------------|
| `authentik.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `argocd.home-ops.nl` | `http://argocd-server.argo-system.svc.cluster.local:80` |
| `grafana.home-ops.nl` | `http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local:80` |
| `hubble.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `longhorn.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |
| `headlamp.home-ops.nl` | `http://authentik-server.authentik.svc.cluster.local:80` |

Proxy apps (Hubble / Longhorn / Headlamp) **must** use Authentik’s Service.

DNS: proxied CNAME `*` (and apex if needed) → `<TUNNEL_ID>.cfargotunnel.com`. Remove public A/AAAA to WAN IP or `10.0.8.120` for internet access.

LAN can keep using Gateway VIP `https://10.0.8.120` via local/split DNS.
