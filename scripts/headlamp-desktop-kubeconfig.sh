#!/usr/bin/env bash
# Mint a gitignored kubeconfig for desktop Headlamp using the headlamp-desktop SA token.
#
# Omni's public kube-apiserver proxy (omni.k5s.dev) expects Omni OIDC, not Kubernetes SA
# tokens. This kubeconfig therefore targets a control-plane kube-apiserver on the LAN
# (default https://10.0.8.3:6443). Override with HEADLAMP_DESKTOP_SERVER if needed.
#
# Requires: existing cluster access via $KUBECONFIG (repo kubeconfig), SA already present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${HEADLAMP_DESKTOP_KUBECONFIG:-${ROOT}/kubeconfig-headlamp-desktop}"
NS=headlamp
SA=headlamp-desktop
SECRET=headlamp-desktop-token
CONTEXT_NAME="${HEADLAMP_DESKTOP_CONTEXT:-headlamp-desktop}"
# Direct kube-apiserver (LAN). Not the Omni proxy URL from the repo kubeconfig.
SERVER="${HEADLAMP_DESKTOP_SERVER:-https://10.0.8.3:6443}"

export KUBECONFIG="${KUBECONFIG:-${ROOT}/kubeconfig}"

if [[ ! -f "${KUBECONFIG}" ]]; then
  echo "headlamp-desktop-kubeconfig: missing ${KUBECONFIG} (run mise run omni-sync first)" >&2
  exit 1
fi

if ! kubectl get secret -n "${NS}" "${SECRET}" >/dev/null 2>&1; then
  echo "headlamp-desktop-kubeconfig: secret ${NS}/${SECRET} not found — wait for Argo to sync headlamp" >&2
  exit 1
fi

echo "Waiting for token in ${NS}/${SECRET}..."
TOKEN=""
CA=""
for _ in $(seq 1 60); do
  TOKEN="$(kubectl get secret -n "${NS}" "${SECRET}" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  CA="$(kubectl get secret -n "${NS}" "${SECRET}" -o jsonpath='{.data.ca\.crt}' 2>/dev/null || true)"
  if [[ -n "${TOKEN}" && -n "${CA}" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "${TOKEN}" || -z "${CA}" ]]; then
  echo "headlamp-desktop-kubeconfig: timed out waiting for SA token/CA" >&2
  exit 1
fi

TOKEN_PLAIN="$(printf '%s' "${TOKEN}" | base64 --decode)"
CA_PLAIN="$(printf '%s' "${CA}" | base64 --decode)"

umask 077
rm -f "${OUT}"
touch "${OUT}"
chmod 600 "${OUT}"

kubectl config --kubeconfig="${OUT}" set-cluster home-ops \
  --server="${SERVER}" \
  --certificate-authority=<(printf '%s' "${CA_PLAIN}") \
  --embed-certs=true
kubectl config --kubeconfig="${OUT}" set-credentials "${SA}" --token="${TOKEN_PLAIN}"
kubectl config --kubeconfig="${OUT}" set-context "${CONTEXT_NAME}" --cluster=home-ops --user="${SA}"
kubectl config --kubeconfig="${OUT}" use-context "${CONTEXT_NAME}"

echo "Wrote ${OUT} (context ${CONTEXT_NAME}, server ${SERVER}). Point desktop Headlamp at this kubeconfig."
