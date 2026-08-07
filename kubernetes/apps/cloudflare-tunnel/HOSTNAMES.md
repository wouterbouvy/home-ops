# Cloudflare Tunnel + public DNS

**Pattern:** onedr0p/cluster-template style — tunnel is a pipe to the Cilium **external** Gateway; HTTPRoutes (and Authentik) own app routing; **external-dns** (`cloudflare-dns`) owns public DNS.

```text
Internet → Cloudflare (proxied CNAME) → cloudflared (*.home-ops.nl)
        → https://cilium-gateway-external.kube-system.svc:443 (SNI external.home-ops.nl)
        → HTTPRoute → Authentik proxy or OIDC app
```

LAN still uses Gateway VIP `10.0.8.120` (split DNS). WAN 80/443 stay closed.

| Public hostname | Backend (via Gateway HTTPRoute) |
|-----------------|----------------------------------|
| `authentik.home-ops.nl` | Authentik IdP |
| `argocd.home-ops.nl` | Argo CD (OIDC) |
| `grafana.home-ops.nl` | Grafana (OIDC) |
| `hubble.home-ops.nl` | Authentik proxy → Hubble |
| `longhorn.home-ops.nl` | Authentik proxy → Longhorn |
| `headlamp.home-ops.nl` | Authentik proxy → Headlamp |

**Git sources of truth**

- Tunnel ingress: [`config.yaml`](config.yaml) (wildcard → Gateway). Remotely-managed tunnels **ignore** local ingress at runtime — after changing `config.yaml`, run `mise run cloudflare-tunnel-config-sync` (needs `ACCOUNT_ID` + `TUNNEL_ID` on the `cloudflare-tunnel` 1Password item and Tunnel Edit on `CLOUDFLARE_DNS_TOKEN`).
- Public DNS target for the tunnel: [`dnsendpoint.yaml`](dnsendpoint.yaml) (`external.home-ops.nl` → `<TUNNEL_ID>.cfargotunnel.com`)
- Per-app DNS: HTTPRoutes + Gateway annotation `external-dns.alpha.kubernetes.io/target: external.home-ops.nl`
- Auth: existing Authentik blueprints / OIDC — unchanged

**1Password:** item `cloudflare-tunnel` / `TUNNEL_TOKEN` (connector). For config sync also `ACCOUNT_ID`, `TUNNEL_ID`. DNS uses item `cloudflare` / `CLOUDFLARE_DNS_TOKEN` via the `cloudflare-dns` app (Zone DNS Edit; Tunnel Edit if using config-sync).
