[Project home](../README.en.md) · [Documentation](README.en.md) · [简体中文](video-tagging.md) · **English**

# Video tagging Skill and CLI (optional)

The app and NAS service provide browsing, playback, reading, and manual tags. Optionally install the [video-tagging Skill](../skills/video-tagging/SKILL.md) to supplement video tags with AI, or use the [shika CLI](../apps/cli/README.md) independently for scripted library queries and tag changes.

The Skill runs in an assistant that supports Skills. It extracts frames, uses the model selected by the user, organizes Chinese tags, and synchronizes them when requested. The CLI connects to the same NAS service as the app. Models run on the computer executing the Skill or a service selected by the user; imported tags become available in the app.

## Install the Skill and CLI together

Prepare Python 3.10+, Git, and an assistant supporting Skills. For Skillshare, first install it and configure its targets. Run from this repository's root:

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
```

The installer sets up an isolated CLI from the same checkout's `apps/cli`, then installs and synchronizes the Skill through Skillshare. On Windows, use `python` instead of `python3` if appropriate.

Without Skillshare, explicitly choose the skill parent directory used by your assistant:

```bash
python3 skills/video-tagging/scripts/install.py --skills-dir ~/.agents/skills
```

This directory is an example; use your assistant's configuration. Update directories maintained by Skillshare or another manager through that manager. Direct installation stops on an existing skill; after reviewing it, add `--update` to back it up and replace it. Backups remain in the private runtime directory.

If the repository requires access, use your own existing Git authentication. For example, select the SSH source for Skillshare:

```bash
python3 skills/video-tagging/scripts/install.py --skillshare \
  --skill-source git@github.com:ShiJiJS/shika.git//skills/video-tagging
```

The installer does not change shell PATH, system Python, app, or Docker settings. Its CLI environment, installation log, and manual update backups live under `shika/video-tagging` in the user data directory, or `%LOCALAPPDATA%/shika/video-tagging` on Windows. Set `SHIKA_TAGGING_HOME` to customize this location and retain that value for installation and execution.

## Use another Skill installer

Point your assistant's installer at `skills/video-tagging` in this repository. Copying Skill files alone cannot install Python tools. During installation or first use, have the assistant run the bundled setup and readiness check:

```bash
python3 <skill-directory>/scripts/install.py --cli-only
python3 <skill-directory>/scripts/install.py --check
python3 <skill-directory>/scripts/shika.py --help
```

A standalone Skill package fetches the CLI from this repository's main branch, requiring Git and dependency downloads. To use an existing checkout, add `--cli-source <checkout>/apps/cli`. Setup does not read a passphrase, log in to a NAS, download models, or process videos.

## Use the Skill

Example requests:

- “Use video-tagging on the videos in this folder and only generate tag files.”
- “Synchronize these existing standard tags to Shika, preserving my manual tags.”
- “Identify this batch with local models, then synchronize its tags to Shika.”

The workflow prepares a manifest, selects local or online inference, retains raw answers, generates `standard.json` / `standard.md`, and optionally matches videos, plans changes, and writes them to Shika. Existing results can be normalized or synchronized without repeating inference.

New inference needs FFmpeg/ffprobe, `video-understanding` for frame extraction, and its Python dependencies. Local inference also requires Ollama, ONNX Runtime, and user-selected model weights. Online inference needs a vision service selected by the user. These are separate from CLI installation; see the [dependency declaration](../skills/video-tagging/assets/dependencies.json). The online entry currently prepares tasks and imports answers; the assistant supplies the authorized service call. Long videos still require segmentation appropriate for the model.

## Connection and data

Log in through the bundled CLI entry:

```bash
python3 <skill-directory>/scripts/shika.py login --base-url http://NAS_ADDRESS:8760
```

Replace `NAS_ADDRESS` and the port with your own deployment. Enter the passphrase interactively or provide your own `RV_PASSPHRASE` environment variable; the CLI does not save the passphrase. Address, access token, and configuration locations follow the [CLI configuration guide](../apps/cli/README.md#配置与凭据) (Chinese).

Frame extraction also requires access to the original files from the computer. Explicitly map local media roots to server directories; a container path is not a local SMB path.

Keep raw answers, tags, progress, and synchronization receipts in a private workspace. The published package contains generic code, documentation, and empty configuration, without media, model weights, connection credentials, or personal run results. Source videos stay read-only. Synchronization applies tag differences and preserves existing tags whose ownership is unproven. Image and tag-text permissions are handled separately as described in the Skill.

Video and image pack tags are independent in the app; this Skill synchronizes video tags only. Prefer the v2 API for full management backups. The CLI's `backup` command remains a legacy video-only management backup and does not include image packs.
