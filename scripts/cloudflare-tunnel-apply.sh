#!/usr/bin/env bash
# Wrapper for mise / local use. Canonical script lives next to ingress.yaml.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${ROOT}/kubernetes/apps/cloudflare-tunnel/cloudflare-tunnel-apply.sh" "$@"
