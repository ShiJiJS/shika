#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dev-env.sh"
if [[ $# -eq 0 ]]; then
  printf 'Usage: bash scripts/dev.sh <command> [args...]\n' >&2
  exit 2
fi
exec "$@"
