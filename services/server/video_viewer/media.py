import hashlib
import json
import math
import os
import subprocess
import uuid


class MediaInspectionError(ValueError):
    """A bounded diagnostic code; never serialize subprocess stderr or paths."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


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
    try:
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
    except subprocess.TimeoutExpired as error:
        raise MediaInspectionError("probe_timeout") from error
    except subprocess.CalledProcessError as error:
        raise MediaInspectionError("probe_failed") from error
    except OSError as error:
        raise MediaInspectionError("probe_unavailable") from error
    info = json.loads(probe.stdout)
    video = next(
        (
            s
            for s in info.get("streams", [])
            if s.get("codec_type") == "video" and not s.get("disposition", {}).get("attached_pic")
        ),
        None,
    )
    if video is None:
        raise MediaInspectionError("no_video_stream")
    audio = next((s for s in info["streams"] if s.get("codec_type") == "audio"), {})
    duration = float(info.get("format", {}).get("duration", video.get("duration", 0)))
    if not math.isfinite(duration) or duration <= 0:
        raise MediaInspectionError("invalid_duration")
    rotation = int(float(video.get("tags", {}).get("rotate", 0)))
    for side in video.get("side_data_list", []):
        if "rotation" in side:
            rotation = int(side["rotation"])
    width, height = int(video["width"]), int(video["height"])
    if width <= 0 or height <= 0:
        raise MediaInspectionError("invalid_dimensions")
    if abs(rotation) % 180 == 90:
        width, height = height, width
    warning = None
    try:
        filename = make_thumbnail(fd, cache_dir, timeout)
    except MediaInspectionError as error:
        # A poster is optional. Metadata and the original remain usable even
        # if a constrained NAS cannot decode a preview within the budget.
        filename, warning = None, error.code
    return {
        "duration": duration,
        "width": width,
        "height": height,
        "rotation": rotation,
        "video_codec": video.get("codec_name", "unknown"),
        "audio_codec": audio.get("codec_name"),
        "container": info.get("format", {}).get("format_name", "unknown"),
        "thumbnail": filename,
        "thumbnail_warning": warning,
    }


def make_thumbnail(fd, cache_dir, timeout):
    source = f"/proc/self/fd/{fd}"
    filename = f"{uuid.uuid4()}.jpg"
    temporary = cache_dir / f"{filename}.tmp.jpg"
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
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
                # Decode the first keyframe, rather than all 4K HEVC frames
                # leading up to an accurate one-second seek on a small ARM CPU.
                "-skip_frame",
                "nokey",
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
        if not temporary.is_file() or temporary.stat().st_size <= 0:
            raise MediaInspectionError("thumbnail_empty")
        temporary.replace(cache_dir / filename)
    except subprocess.TimeoutExpired as error:
        raise MediaInspectionError("thumbnail_timeout") from error
    except subprocess.CalledProcessError as error:
        raise MediaInspectionError("thumbnail_decode_failed") from error
    except OSError as error:
        raise MediaInspectionError("thumbnail_cache_unavailable") from error
    finally:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            # Cache cleanup must not discard otherwise verified media metadata.
            pass
    return filename
