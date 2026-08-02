#!/usr/bin/env bash
# Load Cursor Omni SA from 1Password, then exec the given command.
# Used by mise omni-* / omnictl tasks — not sourced on every mise activation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=omni-sa-env.sh
source "${SCRIPT_DIR}/omni-sa-env.sh"
exec "$@"
