[Project home](../README.en.md) · [Documentation](README.en.md) · [简体中文](video-tagging.md) · **English**

# Video tagging Skill and CLI (optional)

The app and NAS service provide browsing, playback, reading, and manual tags. The CLI lives in this repository at `apps/cli` and supports login, scanning, video queries, and video tag operations. [Install it independently](../apps/cli/README.md#安装) (Chinese). It requires neither Skills nor AI models and is not installed by the app or Docker.

The Skill lives at `skills/video-tagging`. In a compatible assistant, it extracts frames, uses a user-selected model, prepares Chinese tags, and synchronizes them to the same service through the CLI when requested. **Skillshare is not a prerequisite.**

## Install the Skill and isolated CLI

With Python 3.10+, run from a source checkout and choose the actual skill parent directory used by your assistant:

```bash
python3 skills/video-tagging/scripts/install.py --skills-dir /path/to/agent/skills
```

Replace the example path. The installer creates an isolated Python environment from this checkout's `apps/cli` and copies the Skill. On Windows, use an appropriate `python` executable. An existing skill stops direct installation; after reviewing it, add `--update` to back up and replace a manual copy. Use the owning manager for managed directories.

The installer does not modify shell PATH, system Python, app, or Docker settings. The CLI environment, logs, and manual backups live under `shika/video-tagging` in the user data directory, or `%LOCALAPPDATA%/shika/video-tagging` on Windows. Set `SHIKA_TAGGING_HOME` to customize it consistently for installation and execution.

## Use your assistant's Skill installer

Point the assistant's installer at `skills/video-tagging`, or copy the complete directory. After obtaining only the Skill files, configure its CLI:

```bash
python3 <skill-directory>/scripts/install.py --cli-only
python3 <skill-directory>/scripts/install.py --check
python3 <skill-directory>/scripts/shika.py --help
```

A standalone Skill fetches the CLI over HTTPS Git, requiring Git and dependency downloads. Add `--cli-source <checkout>/apps/cli` for local source. If repository access is restricted, use your own GitHub authentication; keep credentials out of URLs. Setup does not read a passphrase, log in to a NAS, download models, or process videos.

## Optional integration for existing Skillshare users

If you already use and have configured Skillshare, choose this instead of direct directory installation:

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
python3 skills/video-tagging/scripts/install.py --skillshare --update
```

This uses the manager's installation, audit, and synchronization. `--skill-source` selects a new installation's source; updates preserve the registered source. Handle conflicting registrations through the manager.

## Use the Skill

Example requests:

- “Use video-tagging on the videos in this folder and only generate tag files.”
- “Synchronize these existing standard tags to Shika, preserving my manual tags.”
- “Identify this batch with local models, then synchronize its tags to Shika.”

The workflow prepares a manifest, selects local or online inference, retains raw answers, generates `standard.json` / `standard.md`, and optionally matches videos, plans changes, and writes them to Shika. Existing results can be normalized or synchronized without repeating inference.

New inference uses the bundled extractor and requires FFmpeg/ffprobe and Pillow, with no other Skill dependency. Local inference also requires Ollama, ONNX Runtime, and user-selected model weights. Online inference needs a vision service selected by the user. These are separate from CLI installation; see the [dependency declaration](../skills/video-tagging/assets/dependencies.json). The online entry currently prepares tasks and imports answers; the assistant supplies the authorized service call. Long videos still require segmentation appropriate for the model.

### Frame extraction environment

Skip this when only normalizing or synchronizing existing tags. For new inference, install system FFmpeg (including ffprobe), then create your own Python environment from the repository root:

```bash
python3 -m venv .venv-tagging
.venv-tagging/bin/python -m pip install -r skills/video-tagging/assets/requirements-extract.txt
.venv-tagging/bin/python skills/video-tagging/scripts/extract_keyframes.py --help
```

On Windows, use `.venv-tagging\Scripts\python.exe`. Execute `infer.py` in the same environment. Sampling covers the video uniformly at approximately one frame per two seconds, capped at 200 frames, with multiple contact sheets. It does not analyze every frame or detect scene changes. An explicit compatible `extractor` overrides this default. Source media stays read-only and output uses a separate empty directory. Local inference additionally needs numpy/onnxruntime in this environment, Ollama, and configured model weights; choose your own online model.

## Connection and data

Log in through the bundled CLI entry:

```bash
python3 <skill-directory>/scripts/shika.py login --base-url http://NAS_ADDRESS:8760
```

Replace `NAS_ADDRESS` and the port with your own deployment. Enter the passphrase interactively or provide your own `RV_PASSPHRASE` environment variable; the CLI does not save the passphrase. Address, access token, and configuration locations follow the [CLI configuration guide](../apps/cli/README.md#配置与凭据) (Chinese).

Frame extraction also requires access to the original files from the computer. Explicitly map local media roots to server directories; a container path is not a local SMB path.

Keep raw answers, tags, progress, and synchronization receipts in a private workspace. The published package contains generic code, documentation, and empty configuration, without media, model weights, connection credentials, or personal run results. Source videos stay read-only. Synchronization applies tag differences and preserves existing tags whose ownership is unproven. Image and tag-text permissions are handled separately as described in the Skill.

Video and image pack tags are independent in the app; this Skill synchronizes video tags only. Prefer the v2 API for full management backups. The CLI's `backup` command remains a legacy video-only management backup and does not include image packs.
