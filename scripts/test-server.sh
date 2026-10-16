#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker build --target test -t video-viewer-server:test "$repo_dir/services/server"
docker run --rm --read-only --tmpfs /tmp:mode=1777 video-viewer-server:test ruff check .
docker run --rm --read-only --tmpfs /tmp:mode=1777 video-viewer-server:test ruff format --check .
docker run --rm --read-only --tmpfs /tmp:mode=1777 video-viewer-server:test
