#!/usr/bin/env bash
# Push kubernetes/apps/cloudflare-tunnel/config.yaml ingress to Cloudflare (remote config).
# Remotely-managed tunnels ignore local ingress; this keeps git as source of truth.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-${ROOT}/kubernetes/apps/cloudflare-tunnel/config.yaml}"
OP_VAULT="${OP_VAULT:-k8s-secrets}"

need() { command -v "$1" >/dev/null || { echo "missing $1" >&2; exit 1; }; }
need curl; need jq; need yq; need op

ACCOUNT_ID="${ACCOUNT_ID:-$(op read "op://${OP_VAULT}/cloudflare-tunnel/ACCOUNT_ID")}"
TUNNEL_ID="${TUNNEL_ID:-$(op read "op://${OP_VAULT}/cloudflare-tunnel/TUNNEL_ID")}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(op read "op://${OP_VAULT}/cloudflare/CLOUDFLARE_DNS_TOKEN")}"

ingress="$(yq -o=json '.' "${CONFIG}" | jq '
  .ingress | map(
    if .hostname then
      {hostname, service, originRequest: (.originRequest // {})}
    else
      {service}
    end
  )
')"
payload="$(jq -nc --argjson ingress "${ingress}" '{config:{ingress:$ingress}}')"

resp="$(curl -sS -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "${payload}")"

if ! echo "${resp}" | jq -e '.success == true' >/dev/null; then
  echo "cloudflare-tunnel-config-sync: API failure" >&2
  echo "${resp}" | jq -c '{success,errors,messages}' >&2
  exit 1
fi
echo "cloudflare-tunnel-config-sync: ok (tunnel ${TUNNEL_ID})" >&2
