#!/usr/bin/env bash
# Sourced by mise ([env] _.source). Loads the Cursor Omni service account from 1Password.
# Requires: `op` signed in; item "Omni Cursor service account" in vault k8s-secrets.
# OMNI_* env vars replace personal omniconfig auth — do not set OMNICONFIG alongside them.

OMNI_SA_OP_REF="${OMNI_SA_OP_REF:-op://k8s-secrets/dfmszcq3udnskcc4cvrzrr4hai}"

if ! command -v op >/dev/null 2>&1; then
  echo "omni-sa-env: op CLI not found; skipping Omni service account load" >&2
  return 0 2>/dev/null || exit 0
fi

export OMNI_ENDPOINT
export OMNI_SERVICE_ACCOUNT_KEY
OMNI_ENDPOINT="$(op read "${OMNI_SA_OP_REF}/OMNI_ENDPOINT")"
OMNI_SERVICE_ACCOUNT_KEY="$(op read "${OMNI_SA_OP_REF}/OMNI_SERVICE_ACCOUNT_KEY")"
unset OMNICONFIG
