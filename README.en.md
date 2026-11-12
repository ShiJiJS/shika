<div align="center">

[简体中文](README.md) · **English**

<img src="assets/branding/shika-icon.png" width="200" alt="Shika icon">

<h1>拾刻 · shika</h1>
<p><strong>Your private media library. Browse and organize as you go.</strong></p>

![Android](https://img.shields.io/badge/App-Android-3DDC84?logo=android&logoColor=white)
![Docker](https://img.shields.io/badge/Server-Docker-2496ED?logo=docker&logoColor=white)
![Status](https://img.shields.io/badge/Version-1.0.1-526B52)

[Getting started](#getting-started) · [Deployment guide](docs/deployment.en.md) · [Documentation](docs/README.en.md) · [Report an issue](https://github.com/ShiJiJS/shika/issues)

</div>

---

## About

Shika is a media browser and organizer for collections stored on your NAS. It combines an **Android app** with a **Docker service hosted on your own NAS**. Add videos and image packs to the library, choose content by folder, tag, or keyword, then start watching or reading. Keep browsing while tagging items and moving unwanted content to the recycle bin.

An **image pack is a folder of images**, treated as one item. Its reader offers comic-style vertical scrolling, horizontal paging, zoom, and reading progress. Videos and image packs have separate tags and recent history, so each collection stays easy to browse and organize.

The current stable version is **1.0.1**. The app UI currently uses Simplified Chinese; the README and deployment guide are available in Chinese and English through the links at the top of each page.

## Features

| Feature | What it does |
| --- | --- |
| Media library | Browse videos and image packs separately; filter by folder, keyword, and tags |
| Video playback | Start from a selected browsing scope, switch between items, and return to the original library view |
| Image pack reader | Continuous vertical scrolling, horizontal paging, zoom, page overview, saved progress, and reading preferences |
| Quick cleanup | Browse a selected scope, move items to the recycle bin, and undo; use multi-select in the library |
| Separate tags | Maintain independent tag sets for videos and image packs; tag an image pack as one item |
| Scanning and maintenance | Manage media roots, per-root scan progress, tasks, missing items, and the recycle bin |
| Management backups | Back up and restore tags, roots, reading progress, preferences, and other management records |

Moving an item to the recycle bin preserves its source files. Permanent deletion removes the selected media; deleting an image pack removes its folder. Management backups do not include source videos or images, which need their own backup.

## Getting started

Version **1.0.1** is the stable release. Build the server image for your NAS CPU, configure the Compose mounts and LAN address, and install the Android APK. Follow the [deployment guide](docs/deployment.en.md) for commands. On first use, tap 连接我的媒体库, enter the server address and port, then tap 连接服务器. The app detects a new server and asks you to enter and confirm a personal passphrase (8–1024 characters); fresh installations have no default passphrase. Existing servers use their current passphrase. Change it later in Settings → 修改个人口令; this device remains connected and other devices must sign in again. No container recreation is needed.

1. **Deploy the service**: prepare your NAS media folders, then follow the [deployment guide](docs/deployment.en.md) to build an image, configure persistent storage, and start the Docker service.
2. **Install the Android app**: download the APK from the [1.0.1 release](https://github.com/ShiJiJS/shika/releases/tag/v1.0.1), or [build it from source](docs/development.md) (Chinese). Keep the same signing key when installing updates over an existing app.
3. **Connect the library**: complete the connection guide with the NAS LAN address and port (`8760` by default), then set or enter the personal passphrase. Add video or image pack roots after authentication. Later launches verify the saved session before opening the library; connection failures offer retry or another server. Logging out preserves the address and requires the passphrase again.
4. **Browse and organize**: check scan progress, select content in the library or tags view, and start playback, reading, or quick cleanup.

Build the service image for `linux/amd64` or `linux/arm64` to match your NAS CPU. Videos stream directly from the NAS without live transcoding; playback support depends on the formats your Android device can decode.

## Deployment and maintenance

The [deployment guide](docs/deployment.en.md) covers initial setup, image builds, permissions, video and image pack mounts, fnOS deployment, app connection, backups, updates, migration, and troubleshooting.

- Templates: [Compose](deploy/fnos/compose.yaml) · [Environment variables](deploy/fnos/.env.example) · [Allowed media paths](deploy/fnos/mounts.json.example)
- Storage: persistent `data/` holds the database and management records, `config/` holds configuration. Passphrases set in the app are stored only as hashes in the database; existing seed-file mounts remain supported.
- Existing libraries: preserve the full management data, root IDs, and container-side mount paths during updates or migration to keep tags and reading records.

## Optional: video tagging Skill and CLI

The [video-tagging Skill](skills/video-tagging/SKILL.md) extracts frames, generates Chinese tag files, and synchronizes them to Shika when requested. The [shika CLI](apps/cli/README.md) supports video queries and batch tag operations. Both are optional; the app and NAS service work independently.

From a source checkout, install the Skill and its isolated CLI together (Python 3.10+ and configured Skillshare):

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
```

See the [video tagging guide](docs/video-tagging.en.md) for other assistants, model dependencies, and the workflow.

## Documentation and development

| Document | Contents |
| --- | --- |
| [Documentation index](docs/README.en.md) | Find the right guide for setup, use, maintenance, or development |
| [Deployment guide](docs/deployment.en.md) | Initial NAS setup, app connection, and routine maintenance |
| [Development guide](docs/development.md) (Chinese) | Flutter, VS Code, local service, APK builds, and tests |
| [Server guide](services/server/README.md) (Chinese) | Configuration, APIs, scanning, file operations, and backup behavior |
| [Command-line client](apps/cli/README.md) (Chinese) | Login, scanning, video queries, and video tag automation |
| [Video tagging Skill (optional)](docs/video-tagging.en.md) | Install the Skill and CLI, generate tag files, and synchronize |

The client lives in `apps/mobile`, the server in `services/server`, and the CLI in `apps/cli`. The app version is defined in [pubspec.yaml](apps/mobile/pubspec.yaml). Remaining work and device validation are tracked in [GitHub Issues](https://github.com/ShiJiJS/shika/issues).

When reporting an issue, include reproduction steps, app version, phone model, and NAS deployment method.
