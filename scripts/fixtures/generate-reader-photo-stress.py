#!/usr/bin/env python3
"""Generate a disposable 500-page photographic composite; download nothing.

Requires Pillow. Input NASA/JSC photos stay local and are never committed.
This tests complex pixels, not 500 independent photographs or real NAS traffic.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

SOURCES = {
    "iss043e000030.jpg": "a7f2ce1bf0b547d76fafe930926a874d3c48eb6025ca172c40c0d090581c4336",
    "iss043e010521.jpg": "92e96f7df3ecdd23b65418932833b2095f835609fb5276b29f2a683e592f8717",
}
MARKER = "video-viewer-photo-stress-v1"


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def generate(sources, output):
    if output.exists() and any(output.iterdir()):
        raise SystemExit("Use a new/empty disposable output; never replace files")
    photos = []
    for name, expected in SOURCES.items():
        p = sources / name
        if sha(p) != expected:
            raise SystemExit("Unexpected input SHA: " + name)
        with Image.open(p) as image:
            photos.append(image.convert("RGB"))
    output.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=64)
    pages = []

    def add(folder, number, width, height):
        canvas = Image.new("RGB", (width, height))
        # Preserve real photographic pixels at native scale; tile rather than upscale.
        for top in range(0, height, 2800):
            for left in range(0, width, 4000):
                photo = photos[(number + top // 2800 + left // 4000) % len(photos)]
                x, y = (number * 13) % 900, (number * 7) % 400
                tile = photo.crop((x, y, x + 4000, y + 2800))
                if (number + left) % 2:
                    tile = ImageOps.mirror(tile)
                canvas.paste(tile, (left, top))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, 0, width, 110), fill=(20, 40, 30))
        draw.text((28, 16), f"{folder} / {number:03d} / {width}x{height}", font=font, fill="white")
        p = output / folder / f"{number:03d}.jpg"
        p.parent.mkdir(exist_ok=True)
        canvas.save(p, quality=90, subsampling=0)
        canvas.close()
        pages.append(
            {
                "path": str(p.relative_to(output)),
                "width": width,
                "height": height,
                "bytes": p.stat().st_size,
                "sha256": sha(p),
            }
        )
        if number % 50 == 0:
            print(json.dumps({"generated": len(pages), "last": pages[-1]["path"]}), flush=True)

    for i in range(1, 501):
        add("01-photo-long", i, 8000 if i % 5 == 0 else 4000, 8000 if i % 5 == 0 else 6000)
    for i, size in enumerate([(4000, 6000), (6000, 4000), (4096, 4096)], 1):
        add("02-photo-4k", i, *size)
    for i, size in enumerate([(8000, 8000), (7680, 4320), (4320, 7680)], 1):
        add("03-photo-8k", i, *size)
    for photo in photos:
        photo.close()
    result = {
        "generator": MARKER,
        "sources": SOURCES,
        "private_media": False,
        "photographic_composite": True,
        "independent_photos": 2,
        "pages": pages,
        "pack_count": 3,
        "page_count": 506,
        "bytes": sum(p["bytes"] for p in pages),
    }
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--sources", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    r = generate(**vars(p.parse_args()))
    print(json.dumps({"pages": r["page_count"], "bytes": r["bytes"]}))
