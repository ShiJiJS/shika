"""Extract bounded, uniformly sampled frames with FFmpeg and Pillow."""

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def extract(source, output, *, interval=2.0, maximum=200, cols=3, cells=12, width=1600):
    from PIL import Image, ImageDraw, ImageOps

    source, output = Path(source).resolve(), Path(output).resolve()
    if not source.is_file():
        raise ValueError("Source video is missing")
    if not math.isfinite(interval) or interval <= 0 or not 1 <= maximum <= 200:
        raise ValueError("Use a positive interval and 1–200 frames")
    if not 1 <= cols <= 12 or not cols <= cells <= 48 or not 320 <= width <= 3200:
        raise ValueError("Invalid contact sheet dimensions")
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise ValueError("Install FFmpeg and ffprobe first")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError("Choose an empty output directory")
    probe = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "format=duration:stream=duration",
            "-of",
            "json",
            str(source),
        ],
        capture_output=True,
        check=True,
        timeout=30,
    )
    info = json.loads(probe.stdout)
    streams = info.get("streams", [])
    if not streams:
        raise ValueError("No video stream")
    duration = float(info.get("format", {}).get("duration") or streams[0].get("duration", 0))
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("Video duration is unavailable")
    count = min(maximum, max(1, math.ceil(duration / interval)))
    spacing = duration / count
    output.parent.mkdir(parents=True, exist_ok=True)
    # Publish only a completed extraction. Failed FFmpeg runs leave no frames
    # that could be mistaken for a complete task on the next attempt.
    with tempfile.TemporaryDirectory(prefix=".shika-keyframes-", dir=output.parent) as temporary:
        staged = Path(temporary)
        subprocess.run(
            [
                "ffmpeg",
                "-nostdin",
                "-v",
                "error",
                "-i",
                str(source),
                "-map",
                "0:v:0",
                "-an",
                "-vf",
                f"fps={count / duration:.12f}:start_time=0,scale='min(960,iw)':-2",
                "-frames:v",
                str(count),
                "-q:v",
                "3",
                str(staged / "frame-%06d.jpg"),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            check=True,
            timeout=max(60, min(1800, duration * 2 + 30)),
        )
        images = sorted(staged.glob("frame-*.jpg"))
        if not images:
            raise ValueError("No frames extracted")
        frames = [
            {"n": index + 1, "time": round(index * spacing, 3), "path": str(output / image.name)}
            for index, image in enumerate(images)
        ]
        overviews = []
        margin, label_height = 12, 24
        cell_width = (width - margin * (cols + 1)) // cols
        cell_height = max(1, round(cell_width * 9 / 16))
        for start in range(0, len(images), cells):
            batch = images[start : start + cells]
            rows = math.ceil(len(batch) / cols)
            sheet = Image.new(
                "RGB", (width, margin + rows * (cell_height + label_height + margin)), "white"
            )
            draw = ImageDraw.Draw(sheet)
            for local, path in enumerate(batch):
                x = margin + local % cols * (cell_width + margin)
                y = margin + local // cols * (cell_height + label_height + margin)
                with Image.open(path) as image:
                    tile = ImageOps.contain(image.convert("RGB"), (cell_width, cell_height))
                    sheet.paste(tile, (x + (cell_width - tile.width) // 2, y))
                page = frames[start + local]
                draw.text(
                    (x, y + cell_height + 4), f"#{page['n']}  ~{page['time']:.2f}s", fill="black"
                )
            name = f"overview-{len(overviews) + 1:03d}.jpg"
            sheet.save(staged / name, quality=90)
            sheet.close()
            overviews.append(str(output / name))
        metadata = {
            "sampling": "uniform",
            "duration": duration,
            "time_precision": "approximate",
            "frames": frames,
            "overviews": overviews,
        }
        (staged / "keyframes.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        output.mkdir(parents=True, exist_ok=True)
        if any(output.iterdir()):
            raise ValueError("Output changed while extracting")
        for path in staged.iterdir():
            path.rename(output / path.name)
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--max-frames", type=int, default=200)
    parser.add_argument("--cols", type=int, default=3)
    parser.add_argument("--sheet-max-cells", type=int, default=12)
    parser.add_argument("--sheet-width", type=int, default=1600)
    parser.add_argument("-q", "--quiet", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = extract(
        args.source,
        args.output,
        interval=args.interval,
        maximum=args.max_frames,
        cols=args.cols,
        cells=args.sheet_max_cells,
        width=args.sheet_width,
    )
    print(
        json.dumps(
            {
                "status": "ready",
                "frames": len(result["frames"]),
                "overviews": len(result["overviews"]),
            }
        )
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, ImportError, MemoryError, subprocess.SubprocessError) as error:
        # Paths and media details remain in the caller's private workspace.
        print(json.dumps({"status": "error", "error_type": type(error).__name__}), file=sys.stderr)
        sys.exit(1)
