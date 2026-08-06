#!/usr/bin/env bash
# Apply Cloudflare Tunnel ingress + proxied DNS CNAMEs from ingress.yaml.
# Env (or 1Password via op when unset locally):
#   ACCOUNT_ID, TUNNEL_ID, ZONE_ID, CLOUDFLARE_API_TOKEN
# Optional:
#   INGRESS_FILE — path to ingress.yaml (default: alongside this script)
#   WILDCARD_HOSTNAME — default *.home-ops.nl
#   DRY_RUN=1 — print planned API calls without mutating
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INGRESS_FILE="${INGRESS_FILE:-${APP_DIR}/ingress.yaml}"
WILDCARD_HOSTNAME="${WILDCARD_HOSTNAME:-*.home-ops.nl}"
API_BASE="https://api.cloudflare.com/client/v4"

OP_VAULT="${OP_VAULT:-k8s-secrets}"
OP_TUNNEL_ITEM="${OP_TUNNEL_ITEM:-cloudflare-tunnel}"
OP_CF_ITEM="${OP_CF_ITEM:-cloudflare}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "cloudflare-tunnel-apply: missing required command: $1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd jq
need_cmd yq

load_from_op_if_unset() {
  local var="$1" ref="$2"
  if [[ -z "${!var:-}" ]]; then
    if command -v op >/dev/null 2>&1; then
      export "$var"="$(op read "$ref")"
    fi
  fi
}

load_from_op_if_unset ACCOUNT_ID "op://${OP_VAULT}/${OP_TUNNEL_ITEM}/ACCOUNT_ID"
# 1Password label may be "TUNNEL_ID" or "TUNNEL ID"
if [[ -z "${TUNNEL_ID:-}" ]]; then
  if command -v op >/dev/null 2>&1; then
    TUNNEL_ID="$(op read "op://${OP_VAULT}/${OP_TUNNEL_ITEM}/TUNNEL_ID" 2>/dev/null || true)"
    if [[ -z "${TUNNEL_ID}" ]]; then
      TUNNEL_ID="$(op read "op://${OP_VAULT}/${OP_TUNNEL_ITEM}/TUNNEL ID" 2>/dev/null || true)"
    fi
    export TUNNEL_ID
  fi
fi
load_from_op_if_unset ZONE_ID "op://${OP_VAULT}/${OP_TUNNEL_ITEM}/ZONE_ID"
load_from_op_if_unset CLOUDFLARE_API_TOKEN "op://${OP_VAULT}/${OP_CF_ITEM}/CLOUDFLARE_DNS_TOKEN"

: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${TUNNEL_ID:?TUNNEL_ID is required}"
: "${ZONE_ID:?ZONE_ID is required}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"

if [[ ! -f "${INGRESS_FILE}" ]]; then
  echo "cloudflare-tunnel-apply: ingress file not found: ${INGRESS_FILE}" >&2
  exit 1
fi

CNAME_TARGET="${TUNNEL_ID}.cfargotunnel.com"

cf_api() {
  local method="$1" path="$2"
  shift 2
  local url="${API_BASE}${path}"
  local response http_code body
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY_RUN ${method} ${url}" >&2
    if [[ $# -gt 0 ]]; then
      echo "DRY_RUN body: $1" >&2
    fi
    echo '{"success":true,"result":[],"dry_run":true}'
    return 0
  fi
  if [[ $# -gt 0 ]]; then
    response="$(
      curl -sS -w '\n%{http_code}' -X "${method}" "${url}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "$1"
    )"
  else
    response="$(
      curl -sS -w '\n%{http_code}' -X "${method}" "${url}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json"
    )"
  fi
  http_code="$(echo "${response}" | tail -n1)"
  body="$(echo "${response}" | sed '$d')"
  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    echo "cloudflare-tunnel-apply: HTTP ${http_code} ${method} ${path}" >&2
    echo "${body}" | jq -c '{success,errors,messages}' 2>/dev/null || echo "${body}" >&2
    exit 1
  fi
  if ! echo "${body}" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "cloudflare-tunnel-apply: API failure ${method} ${path}" >&2
    echo "${body}" | jq -c '{success,errors,messages}' 2>/dev/null || echo "${body}" >&2
    exit 1
  fi
  echo "${body}"
}

build_ingress_json() {
  yq -o=json '.' "${INGRESS_FILE}" | jq '[.hosts[] | {hostname, service}] + [{"service": "http_status:404"}]'
}

put_tunnel_config() {
  local ingress_json payload
  ingress_json="$(build_ingress_json)"
  payload="$(jq -nc --argjson ingress "${ingress_json}" '{config: {ingress: $ingress}}')"
  echo "Updating tunnel configuration (${TUNNEL_ID})..." >&2
  cf_api PUT "/accounts/${ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" "${payload}" >/dev/null
}

list_dns_records() {
  local name="$1"
  local encoded
  encoded="$(jq -rn --arg n "${name}" '$n|@uri')"
  cf_api GET "/zones/${ZONE_ID}/dns_records?name=${encoded}&per_page=100"
}

delete_dns_record() {
  local id="$1"
  cf_api DELETE "/zones/${ZONE_ID}/dns_records/${id}" >/dev/null
}

upsert_cname() {
  local name="$1"
  local records cname_id current content payload proxied rid
  echo "Upserting DNS CNAME ${name} → ${CNAME_TARGET} (proxied)..." >&2
  records="$(list_dns_records "${name}")"

  while IFS= read -r rid; do
    [[ -z "${rid}" ]] && continue
    echo "Deleting conflicting A/AAAA record ${rid} for ${name}" >&2
    delete_dns_record "${rid}"
  done < <(echo "${records}" | jq -r '.result[] | select(.type == "A" or .type == "AAAA") | .id')

  cname_id="$(echo "${records}" | jq -r '[.result[] | select(.type == "CNAME")] | first | .id // empty')"
  current="$(echo "${records}" | jq -r '[.result[] | select(.type == "CNAME")] | first | .content // empty')"

  if [[ -n "${cname_id}" ]]; then
    content="${current%.}"
    if [[ "${content}" == "${CNAME_TARGET}" ]]; then
      proxied="$(echo "${records}" | jq -r '[.result[] | select(.type == "CNAME")] | first | .proxied')"
      if [[ "${proxied}" == "true" ]]; then
        echo "CNAME ${name} already correct" >&2
        return 0
      fi
    fi
    payload="$(jq -nc --arg name "${name}" --arg content "${CNAME_TARGET}" \
      '{type:"CNAME",name:$name,content:$content,proxied:true,ttl:1}')"
    cf_api PUT "/zones/${ZONE_ID}/dns_records/${cname_id}" "${payload}" >/dev/null
    return 0
  fi

  payload="$(jq -nc --arg name "${name}" --arg content "${CNAME_TARGET}" \
    '{type:"CNAME",name:$name,content:$content,proxied:true,ttl:1}')"
  cf_api POST "/zones/${ZONE_ID}/dns_records" "${payload}" >/dev/null
}

main() {
  put_tunnel_config

  local hostnames hostname
  hostnames="$(yq -r '.hosts[].hostname' "${INGRESS_FILE}")"
  while IFS= read -r hostname; do
    [[ -z "${hostname}" ]] && continue
    upsert_cname "${hostname}"
  done <<<"${hostnames}"

  upsert_cname "${WILDCARD_HOSTNAME}"
  echo "cloudflare-tunnel-apply: done" >&2
}

main
