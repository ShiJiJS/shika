[Project home](../README.en.md) · [Deployment](deployment.en.md) · [简体中文](media-layout.md) · **English**

# Organizing videos and image packs

Each video file is one item; each image pack is a folder. Names are unrestricted. You do not need a manifest, tag file, cover, or special numbering scheme. Mount the media in Docker, then add the container path as a video or image-pack root in app settings.

## Recommended layout

```text
NAS media/
├── videos/                   → /media inside Docker; add as a video root
│   ├── Travel/Beach.mp4
│   └── Clips/Example.mkv
└── packs/                    → /packs-cos inside Docker; add as an image-pack root
    ├── Pack A/               → one image pack
    │   ├── 001.jpg
    │   ├── 002.jpg
    │   └── 010.jpg
    └── Pack B/               → another image pack
        ├── 01.png
        └── 02.webp
```

For example, set `SHIKA_PACK_DIR=/srv/media/packs` in `.env`; Compose mounts it at `/packs-cos`. Add **`/packs-cos`** in the app, rather than `/srv/media/packs` or a computer's SMB path. Allow the container path in `mounts.json` as described in [deployment configuration](deployment.en.md#3-set-paths).

## Pack boundaries and reading order

- Every **immediate child folder** of an image-pack root becomes one pack. Adding `/packs-cos` above produces Pack A and Pack B.
- Images in nested folders belong to that same pack: `Pack A/Part 1/01.jpg` and `Pack A/Part 2/01.jpg` are read together.
- Loose images directly inside the root do not become a pack. If a folder already represents one pack, add its parent as the root.
- Pages use natural sorting of their relative paths: `1.jpg`, `2.jpg`, `10.jpg`. Subfolder names also affect ordering; use numbered folders and filenames for a predictable sequence.
- The folder name supplies the default pack title. Tags and reading progress are stored in the server database; no sidecar metadata file is required.

For collections organized as `author/pack/images`, add each author directory as its own image-pack root. For example, add `/packs-cos/Author A` and `/packs-cos/Author B` to keep their child packs separate. Adding only `/packs-cos` instead makes each author directory a single pack and combines all its descendant images.

Naming is optional. To display a separate author, number, and title automatically, the current parser recognizes folder names such as `Author NO.001 - Title`. Ordinary names are displayed intact; parent folders, brackets, or dashes alone do not identify an author. Tags embedded in names are not imported automatically; maintain tags through the app or corresponding API.

## Supported files

| Type | Scanned formats |
| --- | --- |
| Pack images | JPG, JPEG, PNG, WebP; extensions are case-insensitive |
| Videos | MP4, MOV, M4V, MKV, WebM, AVI, MPG, MPEG, TS, MTS, M2TS, 3GP |
| Compressed packs | ZIP, RAR, 7z, CBZ, etc. are not extracted or read automatically; extract them into folders first |

GIF, BMP, HEIC, and PDF are outside the current image-pack formats. Animated images cannot be used as ordinary static pages. Video indexing does not guarantee that a phone supports its codecs; the server does not transcode in real time.

A child folder without readable images can appear as a pack with no readable pages; inspect scan issues for details. Symbolic links are skipped, along with excluded NAS recycle/cache directories. A readable page with a generated thumbnail supplies the cover automatically.

## Tags, deletion, and migration

- Assign tags in the app. Video and image-pack tags are separate; individual images do not have tags.
- Moving to the recycle bin changes records only. **Permanently deleting a pack removes its folder, including other attachments inside it.** Store unrelated files elsewhere.
- Keep `data/` for tags, progress, and other management records; back up source media separately. Preserve root IDs and container paths when upgrading or migrating. Rescanning does not guess that ambiguous replacements are the same original item.

The supported formats are defined by the [image](../services/server/shika/images.py) and [video](../services/server/shika/paths.py) scanners.
