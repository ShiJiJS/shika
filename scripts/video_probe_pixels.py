#!/usr/bin/env python3
"""Read-only PNG regression check for the fixed public flower video probes."""

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path


def inspect(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", data[16:24])
    rgb = subprocess.check_output(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            str(path),
            "-frames:v",
            "1",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ]
    )
    assert len(rgb) == width * height * 3
    rows = range(height // 10, height * 3 // 4, max(1, height // 200))
    columns = []
    for x in range(width):
        matched = 0
        for y in rows:
            at = (y * width + x) * 3
            matched += rgb[at] <= 4 and rgb[at + 1] >= 120 and rgb[at + 2] <= 4
        if matched >= len(rows) * 0.95:
            columns.append(x)
    longest = current = 0
    previous = -2
    for column in columns:
        current = current + 1 if column == previous + 1 else 1
        longest = max(longest, current)
        previous = column
    colors = {
        rgb[(y * width + x) * 3 : (y * width + x) * 3 + 3]
        for y in list(rows)[::3]
        for x in range(width // 10, width * 9 // 10, max(1, width // 250))
    }
    return {
        "file": path.name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "width": width,
        "height": height,
        "green_columns": len(columns),
        "longest_green_run": longest,
        "sampled_distinct_colors": len(colors),
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--expect", choices=("texture-green", "clean"), required=True)
    args = p.parse_args()
    names = [
        "flutter-textureView",
        "flutter-platformView",
        "native-surface",
        "native-texture",
    ]
    rows = [
        inspect(args.input / (name + ".png"))
        for name in names
        if (args.input / (name + ".png")).exists()
    ]
    assert rows and all(r["sampled_distinct_colors"] > 1000 for r in rows), rows
    for row in rows:
        bad = (
            args.expect == "texture-green" and row["file"] == "flutter-textureView.png"
        )
        assert (
            (row["longest_green_run"] >= 50) if bad else (row["longest_green_run"] == 0)
        ), row
    result = {
        "expectation": args.expect,
        "expectation_matched": True,
        "picture_integrity_passed": all(r["longest_green_run"] == 0 for r in rows),
        "inspector_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "images": rows,
    }
    (args.input / "png-inspection.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
