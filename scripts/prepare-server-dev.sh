#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dev_dir="$HOME/.local/share/video-viewer-dev"
umask 077
mkdir -p "$dev_dir/data" "$dev_dir/media" "$dev_dir/config"
if [[ ! -e "$dev_dir/passphrase" ]]; then
  python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > "$dev_dir/passphrase"
fi
if [[ ! -e "$dev_dir/config/mounts.json" ]]; then
  printf '[{"id":"main","name":"开发测试媒体","path":"/media"}]\n' > "$dev_dir/config/mounts.json"
fi
if [[ ! -e "$repo_dir/.env" ]]; then
  cat > "$repo_dir/.env" <<EOF
VV_DATA_PATH=$dev_dir/data
VV_MEDIA_PATH=$dev_dir/media
VV_CONFIG_PATH=$dev_dir/config
VV_SECRET_PATH=$dev_dir/passphrase
VV_UID=$(id -u)
VV_GID=$(id -g)
VV_PORT=8760
VV_BIND_ADDRESS=0.0.0.0
VV_SCAN_INTERVAL=300
VV_STABILITY_SECONDS=2
EOF
fi
printf 'Development directories and ignored .env are ready. Passphrase is in %s/passphrase (not printed).\n' "$dev_dir"
