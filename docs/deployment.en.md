[Project home](../README.en.md) · [Documentation](README.en.md) · [简体中文](deployment.md) · **English**

# Deployment and everyday use

Shika consists of an Android app and one Docker service. The service runs on your NAS; the app connects using its LAN address, port, and a personal passphrase. This guide uses the [existing Compose template](../deploy/fnos/compose.yaml) and covers initial setup through backups and migration. Local development is covered in the [development guide](development.md) (Chinese).

## Prerequisites

- **NAS**: Docker Engine, Compose v2, and persistent local storage. Build the image for the NAS architecture: `linux/amd64` or `linux/arm64`.
- **Media**: existing video and image pack folders. An image pack is organized as a folder. Video playback depends on formats supported by the Android device; the service does not transcode in real time.
- **Network**: the phone can reach the NAS LAN address. The default service port is `8760`; the template binds to the specified NAS address.
- **Permissions**: choose a container UID/GID, `1000:1000` by default. It must read and write management data, read configuration and the passphrase, and have media write access when needed.

`/srv/shika`, `/srv/media/videos`, `/srv/media/packs`, and `192.168.1.100` are examples. fnOS normally uses actual paths such as `/vol1/1000/...`; other NAS systems use their own volume paths. Keep private paths and the personal passphrase in local configuration.

## Initial deployment

For an existing library, read [Backups, updates, and migration](#backups-updates-and-migration) first. Do not replace existing root IDs or the passphrase with sample values.

### 1. Build an image for the NAS CPU

On a machine with Git and Docker, get the source:

```bash
git clone https://github.com/ShiJiJS/shika.git
cd shika
```

When building directly on the target NAS, Docker uses that machine's architecture by default:

```bash
docker build --target runtime -t shika-server:1.0.1 services/server
```

When building on another computer for transfer to the NAS, specify the architecture explicitly. For an x86 NAS:

```bash
mkdir -p tmp/releases
docker buildx build --platform linux/amd64 --target runtime \
  -t shika-server:1.0.1-amd64 \
  --output type=docker,dest=tmp/releases/server-amd64.tar services/server
```

For an ARM NAS, use `linux/arm64` and change the tag and archive filename accordingly. Import the archive on the NAS and inspect the architecture. With Docker CLI access:

```bash
docker load -i /path/to/server-amd64.tar
docker image inspect shika-server:1.0.1-amd64 --format '{{.Os}}/{{.Architecture}}'
```

Set `SHIKA_IMAGE` to the **tag you actually built or imported**. The template's default tag does not indicate a published public registry image. On fnOS, importing is also possible through its Docker interface or an authorized CLI, as described below.

### 2. Prepare persistent storage

Create the following layout on the NAS using its file manager or a terminal. The Bash example is for a fresh installation; replace paths with your own:

```text
shika/
├── compose.yaml
├── .env
├── data/                 # SQLite, tasks, cache, exports, pre-restore snapshots
└── config/
    └── mounts.json       # Allowed container-side media paths
```

Copy the templates from the source checkout without replacing existing files:

```bash
mkdir -p /srv/shika/data /srv/shika/config
cp -n deploy/fnos/compose.yaml /srv/shika/compose.yaml
cp -n deploy/fnos/.env.example /srv/shika/.env
cp -n deploy/fnos/mounts.json.example /srv/shika/config/mounts.json
```

Store `data/` on a NAS-local filesystem supporting SQLite WAL, rather than an SMB/NFS client mount on another computer. Grant access to the directories the service needs; avoid recursively changing ownership of the entire media collection.

### 3. Set paths

Edit `.env` in the NAS application directory. For an image built natively on the NAS:

```dotenv
SHIKA_IMAGE=shika-server:1.0.1
SHIKA_BIND_ADDRESS=192.168.1.100
SHIKA_PORT=8760
SHIKA_UID=1000
SHIKA_GID=1000
SHIKA_DEPLOY_DIR=/srv/shika
SHIKA_VIDEO_DIR=/srv/media/videos
SHIKA_PACK_DIR=/srv/media/packs
```

For the cross-built image above, use `SHIKA_IMAGE=shika-server:1.0.1-amd64`. Both media source directories must already exist. The configuration maps to the running container as follows:

| NAS path or setting | Container path / purpose |
| --- | --- |
| `SHIKA_DEPLOY_DIR/data` | `/data`: complete persistent management data |
| `SHIKA_DEPLOY_DIR/config` | `/config`: read-only configuration |
| `SHIKA_VIDEO_DIR` | `/media`: allowed video scope |
| `SHIKA_PACK_DIR` | `/packs-cos`: allowed image pack scope |
| `SHIKA_BIND_ADDRESS`, `SHIKA_PORT` | NAS LAN address and port used by the phone |
| `SHIKA_UID`, `SHIKA_GID` | Identity used to read files and write management data |

Fresh installations do not need a passphrase file. Set the passphrase in the app on first connection; the database stores only an Argon2 hash. Keep existing deployments’ seed files and mounts: unchanged seeds will not undo later in-app changes after a restart.

The copied `config/mounts.json` example is:

```json
[
  {"id": "main", "name": "视频", "path": "/media"},
  {"id": "cos-packs", "name": "图包", "path": "/packs-cos"}
]
```

These entries define **allowed scopes**, not every media root. In the app, add one or more roots within those scopes and select their video or image pack type. To expose another scope, add both a Compose bind mount and an entry here. The service cannot access unmounted paths and does not follow symbolic links.

The template mounts media read/write to support permanent deletion. Moving an item to the recycle bin and ordinary restoration only change management records. Read-only media mounts support browsing and marking items, but cannot perform operations that write files. Keep the read-only root filesystem, dropped capabilities, and `no-new-privileges`; do not mount the Docker socket.

### 4. Start and verify

Run in the NAS application directory. Adjust the health-check address to match `.env`:

```bash
cd /srv/shika
docker compose --env-file .env -f compose.yaml config --quiet
docker compose --env-file .env -f compose.yaml up -d --no-build --wait --wait-timeout 120
docker compose ps
curl --fail http://192.168.1.100:8760/health
```

After the health check returns `{"status":"ok","api_version":1}`, log in through the app and check the media roots. A healthy process does not mean every media file has finished scanning. Run one service process; do not add Uvicorn workers.

## fnOS deployment

An application directory can be `/vol1/1000/docker/shika`; media paths must reflect their current location. Place `compose.yaml`, `.env`, and configuration there. **Import the matching architecture image first**, then select the existing Compose file in the Docker interface, create the project, and start it. For updates, recreate the existing project instead of creating another one.

An authorized `fnos-cli` can also perform these operations. The following profile, paths, and tag are examples. Verify the target device and authorization, upload the archive and configuration, then run:

```bash
fnos-cli --profile home-fnos --allow-insecure-http docker image ls
fnos-cli --profile home-fnos --allow-insecure-http docker container ls --all
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.imageLoad --json '{"filePath":"/vol1/1000/docker/shika/image-archives/server-amd64.tar"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker image inspect shika-server:1.0.1-amd64
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeCreate --json '{"auto_build":false,"file":"compose.yaml","folder":"/vol1/1000/docker/shika","project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeBuild --json '{"project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker container inspect shika-server
```

`--allow-insecure-http` is needed only for a saved connection using LAN HTTP; use the appropriate connection options for HTTPS. After a timeout, inspect the actual image, project, or container state before continuing, rather than repeating an import or creation request. Deployment does not require enabling SSH.

## Install and connect the app

Use an APK supplied by the maintainer, or configure Flutter / Android and [build the client](development.md) (Chinese). Run the following in `apps/mobile`:

```bash
flutter build apk --release \
  --target-platform android-arm64 --dart-define=LIBRARY_MODE=server
```

The output is `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`. The first installation uses your own build's signing key or the supplied APK's key. Every later in-place update must use the same key. The version is defined in [pubspec.yaml](../apps/mobile/pubspec.yaml).

Open the app and enter:

| Field | Example |
| --- | --- |
| Server address | `192.168.1.100` |
| Port | `8760` |
| Personal passphrase | Set on first connection, or the existing server’s passphrase |

The phone must be able to reach that NAS address. `10.0.2.2:8760` is only for an Android emulator reaching a local development service, not a physical phone reaching a NAS. After login, the app saves access credentials, not the personal passphrase.

In settings, add media roots, choose video or image pack type, and check enabled status and scan progress. The allowed scopes, added roots, and Docker mounts must correspond.

### Set, change, or recover the passphrase

For a fresh server, enter the NAS address and port and tap Connect. The app displays first-time setup: enter and confirm an **8–1024 character** passphrase and tap 设置口令并连接. Keep the unclaimed service accessible only from your trusted LAN.

Existing servers keep their passphrase. Use Settings → 修改个人口令, enter the current passphrase and confirm the new one. This device automatically adopts a replacement access token; all old tokens are revoked and other devices must sign in again. The app stores access credentials, not the plain text passphrase. Management backups exclude authentication secrets.

For administrator recovery, create or change `secrets/passphrase` to a new value different from the original seed. Restrict access but allow the container UID to read it. Add a read-only bind mount to `/run/secrets/passphrase` (or set `VV_PASSPHRASE_FILE` to its container path), then recreate the existing container. A changed seed resets the passphrase and revokes old sessions. An unchanged seed does not undo later app changes. Never delete the database to reset authentication.

## Everyday use

- **Library and tags**: query and filter videos and image packs separately. Select content to start playback or reading, then return to the original view. An empty result does not expand to the entire library.
- **Image pack reading**: continuous vertical scrolling is the default. Horizontal paging, zoom, overview, and resume are supported; saved preferences remain in effect.
- **Quick cleanup**: browse a selected scope, move items to the recycle bin, and undo; multi-select is available in the library.
- **Scanning**: scan manually after file copying finishes, or wait for a scheduled scan. Per-root progress comes from the server, and closing the app does not stop background work. The template's scan interval is 900 seconds.
- **Recycle bin**: moving an item preserves source files. Permanent deletion removes media; an image pack is deleted as its selected folder and contents in the background. Check task results for failed items.
- **Thumbnail cache**: the service checks for cleanup at startup and after scans, with hourly idle checks. Unreferenced previews, and previews referenced only by permanently deleted records, are removed in small batches once both their modification time and filesystem change time are over an hour old. References from active, recycled, missing, and unpublished scan records remain protected; source media and management backups are excluded. Cleanup runs serially with thumbnail generation, pauses during management restore, and reports results in service logs.

## Backups, updates, and migration

### Management and media backups

In the app's backup and restore settings, create a management backup and save it outside the app through the phone's file picker. A full backup includes video and image pack identities, tags, roots, reading progress, preferences, and history. It **does not include source videos, images, cache, the personal passphrase, or local app appearance settings**. Back up media and legacy physically moved recycle-bin files separately on the NAS.

Full backups use v2 NDJSON; legacy v1 files can still be validated and converted. The CLI's legacy video backup is not a full backup containing image packs. The service reports size limits; see the [server guide](../services/server/README.md#完整备份与兼容) (Chinese) for details.

To restore, select and validate a backup, review root mappings, then confirm replacement. The service saves a pre-restore snapshot. Restoration does not replay historical deletion or recover permanently deleted media. After a disconnect, query the original task instead of resubmitting it.

### Updates and rollback

1. Export a management backup and save the current Compose file, environment configuration, and image information.
2. For a full instance rollback, stop the service before backing up all of `data/` and `config/`, and securely retain the passphrase and original image. Do not copy only the live SQLite main file while omitting its WAL.
3. Build or import the new image, change `SHIKA_IMAGE`, and recreate the **existing** Compose project while preserving bind mounts.
4. Check container health, app login, root availability, and task results. Keep the same signing key when updating the app in place.

Rollback requires a compatible pair of the original image and stopped-instance snapshot; an old image may not read a newer database. In-app passphrase changes do not require container recreation; other devices must log in with the new value.

### Moving to another NAS or storage location

- Preserve complete management data, the passphrase, stable root IDs, and container paths such as `/media` and `/packs-cos`; change only the external bind-mount sources.
- Build or import an image matching the new CPU. Retagging an ARM image does not turn it into an x86 image.
- Only one service instance may access the same management data. Verify the new deployment before retiring the original; do not let two services write the same database.
- Changed file identities trigger revalidation after migration. Content not yet revalidated must wait for its root's scan.
- Legacy `.video-viewer-trash`, `.video-viewer-tmp`, or custom recycle-bin volumes may hold old physically moved files. Do not delete or rename them merely because the product name changed.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Phone cannot connect | NAS address, port, firewall, phone network, and container health |
| 401 / reconnect required | Changed passphrase or expired credentials; enter the passphrase again |
| New content is missing | Bind mounts, allowed scopes, root type/enabled status, finished copies, and scan tasks |
| Images temporarily fail after migration | Revalidation progress for that image pack root; preserved root IDs and container paths |
| Deletion fails | Directory write permission, free space, moved/replaced paths, and the original task's failure result |
| Video will not play | Codecs, audio, and resolution supported by the phone; the service does not transcode live |
| Scanning or switching is slow | Network, NAS load, and adjacent-video preparation settings; tune resources using measurements |
| Backup import fails | Format, version, integrity, published size limits, and original task results |

For unresolved problems, include reproduction steps, app version, phone model, and deployment method in [GitHub Issues](https://github.com/ShiJiJS/shika/issues). More development and API guides are linked from the [documentation index](README.en.md).
