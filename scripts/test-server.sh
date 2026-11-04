#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker build --target test -t shika-server:test "$repo_dir/services/server"
status=0
docker run --rm --read-only --shm-size=64m --tmpfs /tmp:mode=1777 shika-server:test ruff check . || status=1
docker run --rm --read-only --shm-size=64m --tmpfs /tmp:mode=1777 shika-server:test ruff format --check . || status=1
docker run --rm --read-only --shm-size=64m --tmpfs /tmp:mode=1777 shika-server:test || status=1
exit "$status"
