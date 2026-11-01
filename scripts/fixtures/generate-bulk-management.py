#!/usr/bin/env python3
"""Create disposable, reproducible pack fixtures in a new directory only."""

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path


def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )


def png(index, page):
    width, height = 64, 96
    raw = b"".join(
        b"\0"
        + bytes(
            value
            for x in range(width)
            for value in (
                (index * 23 + x * 3) % 256,
                (page * 83 + y * 2) % 256,
                ((x // 8 + y // 12) % 2) * 120 + 60,
            )
        )
        for y in range(height)
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="New fixture directory; must not exist")
    parser.add_argument("--bulk-count", type=int, default=1027)
    args = parser.parse_args()
    if not 25 <= args.bulk_count <= 50000:
        parser.error("bulk-count must be between 25 and 50000")
    destination = args.destination.resolve()
    # Never repurpose or clean an existing media directory.
    destination.mkdir(parents=True, exist_ok=False)
    media = destination / "media"
    media.mkdir()
    names = [f"Bulk-{n:04d}" for n in range(1, args.bulk_count + 1)] + [
        "Keep-available-1",
        "Keep-available-2",
        "Keep-trash-1",
        "Keep-trash-2",
    ]
    for index, name in enumerate(names, 1):
        pack = media / name
        pack.mkdir()
        for page in (1, 2):
            (pack / f"{page:02d}.png").write_bytes(png(index, page))
        (pack / "attachment.txt").write_text(
            f"Synthetic local bulk-management fixture: {name}\n"
            "Retain this attachment during image-only permanent deletion.\n",
            encoding="utf-8",
        )
    files = {
        str(path.relative_to(media)): {
            "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        for path in sorted(media.rglob("*"))
        if path.is_file()
    }
    manifest = {
        "synthetic": True,
        "real_media_used": False,
        "packs": len(names),
        "target_bulk_packs": args.bulk_count,
        "control_packs": 4,
        "files": files,
        "image_count": len(names) * 2,
        "attachment_count": len(names),
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Created {len(names)} packs and {len(files)} files in {destination}")


if __name__ == "__main__":
    main()
