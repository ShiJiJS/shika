#!/usr/bin/env python3
"""Generate disposable LF fixtures with stdlib PNG encoding; no private media."""

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path

MARKER = "video-viewer-lf0-synthetic-v1"


def png(path, width, height, color):
    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data))
        )

    compressor = zlib.compressobj(6)
    row = b"\0" + bytes(color) * width
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        stream.write(b"\x89PNG\r\n\x1a\n")
        stream.write(
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        )
        for _ in range(height):
            block = compressor.compress(row)
            if block:
                stream.write(chunk(b"IDAT", block))
        stream.write(chunk(b"IDAT", compressor.flush()))
        stream.write(chunk(b"IEND", b""))


def generate(output):
    output = output.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit(
            "Output must be a new or empty directory; existing files are never replaced."
        )
    output.mkdir(parents=True, exist_ok=True)
    pages = []

    def add(relative, width=240, height=360, color=(110, 140, 100)):
        path = output / relative
        png(path, width, height, color)
        pages.append(
            {
                "path": relative,
                "width": width,
                "height": height,
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
        )

    for name in ["1.png", "2.png", "10.png", "chapter2/3.png"]:
        add("01-natural/" + name)
    add("02-large/1-portrait.png", 4000, 6000)
    add("02-large/2-landscape.png", 6000, 4000, (150, 140, 100))
    add("02-large/3-8k.png", 8000, 8000, (100, 130, 150))
    add("03-invalid/1-good.png")
    (output / "03-invalid/2-broken.jpg").write_bytes(
        b"LF0 deliberately invalid image\n"
    )
    (output / "03-invalid/notes.txt").write_text(
        "Non-image attachment: must survive image purge.\n"
    )
    (output / "03-invalid/empty").mkdir()
    for i in range(1, 501):
        add(f"04-long/{i}.png", color=(80 + i % 80, 110, 130))
    manifest = {
        "generator": MARKER,
        "private_media": False,
        "pack_count": 4,
        "valid_image_count": len(pages),
        "pages": pages,
        "natural_order": ["1.png", "2.png", "10.png", "chapter2/3.png"],
        "invalid_images": ["03-invalid/2-broken.jpg"],
        "preserved_attachments": ["03-invalid/notes.txt"],
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    result = generate(parser.parse_args().output)
    print(
        f"Generated {result['pack_count']} packs / {result['valid_image_count']} valid images."
    )
