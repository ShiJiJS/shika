"""Generate disposable multi-format media; also used by integration tests."""

import subprocess
import sys
from pathlib import Path


def encode(path, *, codec="libx264", audio="aac", size="160x96", duration=1, extra=()):
    subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            f"testsrc2=size={size}:rate=12",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:sample_rate=48000",
            "-t",
            str(duration),
            "-c:v",
            codec,
            "-threads",
            "1",
            "-c:a",
            audio,
            *extra,
            "-y",
            str(path),
        ],
        check=True,
        capture_output=True,
        timeout=30,
    )


def generate(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    # These fixed names are exclusively for explicitly chosen disposable folders.
    encode(
        directory / "portrait.mp4",
        size="96x160",
        extra=("-profile:v", "baseline", "-pix_fmt", "yuv420p", "-movflags", "+faststart"),
    )
    encode(directory / "h264.mov", extra=("-pix_fmt", "yuv420p", "-movflags", "+faststart"))
    encode(directory / "h264.mkv")
    encode(
        directory / "vp9.webm",
        codec="libvpx-vp9",
        audio="libopus",
        extra=("-deadline", "realtime", "-cpu-used", "8"),
    )
    encode(directory / "mpeg4.avi", codec="mpeg4", audio="libmp3lame")
    encode(
        directory / "prores.mov",
        codec="prores_ks",
        audio="pcm_s16le",
        extra=("-profile:v", "0", "-pix_fmt", "yuv422p10le"),
    )
    encode(
        directory / "hevc.mov",
        codec="libx265",
        extra=("-x265-params", "pools=1:frame-threads=1:log-level=error", "-tag:v", "hvc1"),
    )
    subprocess.run(
        [
            "ffmpeg",
            "-nostdin",
            "-v",
            "error",
            "-i",
            str(directory / "h264.mov"),
            "-c",
            "copy",
            "-metadata:s:v:0",
            "rotate=90",
            "-y",
            str(directory / "rotated.mov"),
        ],
        check=True,
        capture_output=True,
        timeout=10,
    )
    return directory


if __name__ == "__main__":
    generate(sys.argv[1])
    print("Generated 8 disposable media samples")
