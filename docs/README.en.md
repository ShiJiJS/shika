[Project home](../README.en.md) · [简体中文](README.md) · **English**

# Shika documentation

Start with [what Shika does](../README.en.md#features), then choose a guide below. The README, documentation index, and deployment guide are available in Chinese and English. Development and API reference documents are currently mainly in Chinese.

## Setup, use, and maintenance

| Task | Guide |
| --- | --- |
| Install Shika on a NAS for the first time | [Initial deployment](deployment.en.md#initial-deployment) |
| Create the service in fnOS | [fnOS deployment](deployment.en.md#fnos-deployment) |
| Install the app and connect to the service | [Install and connect the app](deployment.en.md#install-and-connect-the-app) |
| Understand browsing, reading, and cleanup | [Everyday use](deployment.en.md#everyday-use) |
| Back up, update, move to another NAS, or roll back | [Backups, updates, and migration](deployment.en.md#backups-updates-and-migration) |
| Troubleshoot connection, scanning, playback, or deletion | [Troubleshooting](deployment.en.md#troubleshooting) |
| Report a problem or check remaining work | [GitHub Issues](https://github.com/ShiJiJS/shika/issues) |

## Development and APIs

The following guides are in Chinese.

| Document | Contents |
| --- | --- |
| [Development guide](development.md) | Environment setup, debugging, APK builds, and tests |
| [Server](../services/server/README.md) | Docker development, APIs, scanning, recycle bin, and full backups |
| [Command-line client](../apps/cli/README.md) | CLI installation, video queries, and tag automation |

Deployment templates: [Compose](../deploy/fnos/compose.yaml) · [Environment variables](../deploy/fnos/.env.example) · [Allowed media paths](../deploy/fnos/mounts.json.example). The running service's `/openapi.json` is the authoritative API parameter reference.
