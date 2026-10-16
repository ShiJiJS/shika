import hashlib
import json
import math
import os
import subprocess
import uuid


def fingerprint(fd, stop):
    size = os.fstat(fd).st_size
    os.lseek(fd, 0, os.SEEK_SET)
    full = hashlib.sha256()
    while chunk := os.read(fd, 1024 * 1024):
        if stop.is_set():
            raise InterruptedError("scan_stopped")
        full.update(chunk)
    os.lseek(fd, 0, os.SEEK_SET)
    quick = hashlib.sha256(str(size).encode() + os.read(fd, 65536))
    os.lseek(fd, max(0, size - 65536), os.SEEK_SET)
    quick.update(os.read(fd, 65536))
    os.lseek(fd, 0, os.SEEK_SET)
    return full.hexdigest(), quick.hexdigest()


def inspect_media(fd, cache_dir, timeout):
    source = f"/proc/self/fd/{fd}"
    probe = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-protocol_whitelist",
            "file,pipe",
            "-show_format",
            "-show_streams",
            "-of",
            "json",
            source,
        ],
        pass_fds=(fd,),
        capture_output=True,
        timeout=timeout,
        check=True,
    )
    info = json.loads(probe.stdout)
    video = next(
        s
        for s in info.get("streams", [])
        if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")
    )
    audio = next((s for s in info["streams"] if s.get("codec_type") == "audio"), {})
    duration = float(info.get("format", {}).get("duration", video.get("duration", 0)))
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("invalid_duration")
    rotation = int(float(video.get("tags", {}).get("rotate", 0)))
    for side in video.get("side_data_list", []):
        if "rotation" in side:
            rotation = int(side["rotation"])
    width, height = int(video["width"]), int(video["height"])
    if width <= 0 or height <= 0:
        raise ValueError("invalid_dimensions")
    if abs(rotation) % 180 == 90:
        width, height = height, width
    cache_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{uuid.uuid4()}.jpg"
    temporary = cache_dir / f"{filename}.tmp.jpg"
    try:
        subprocess.run(
            [
                "ffmpeg",
                "-nostdin",
                "-v",
                "error",
                "-threads",
                "1",
                "-protocol_whitelist",
                "file,pipe",
                "-ss",
                str(min(1, duration / 2)),
                "-i",
                source,
                "-frames:v",
                "1",
                "-vf",
                "scale=320:320:force_original_aspect_ratio=decrease",
                "-threads",
                "1",
                "-y",
                str(temporary),
            ],
            pass_fds=(fd,),
            capture_output=True,
            timeout=timeout,
            check=True,
        )
        if temporary.stat().st_size <= 0:
            raise ValueError("empty_thumbnail")
        temporary.replace(cache_dir / filename)
    finally:
        temporary.unlink(missing_ok=True)
    return {
        "duration": duration,
        "width": width,
        "height": height,
        "rotation": rotation,
        "video_codec": video.get("codec_name", "unknown"),
        "audio_codec": audio.get("codec_name"),
        "container": info.get("format", {}).get("format_name", "unknown"),
        "thumbnail": filename,
    }
