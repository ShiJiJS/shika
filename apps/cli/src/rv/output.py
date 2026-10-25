"""输出辅助：--json 原样输出，人类模式用简单的定宽行。"""

from __future__ import annotations

import json
import sys


def print_json(payload) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def human_size(size: float | None) -> str:
    if size is None:
        return "-"
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.0f}{unit}" if unit == "B" else f"{value:.1f}{unit}"
        value /= 1024
    return f"{value:.1f}TiB"


def video_line(video: dict) -> str:
    duration = video.get("duration")
    minutes = f"{int(duration // 60):02d}:{int(duration % 60):02d}" if duration else "-"
    return (
        f"{video['id']}  {video.get('path') or video.get('name')}"
        f"  {human_size(video.get('size'))}  {minutes}"
        f"  tags={len(video.get('tag_ids') or [])}"
    )


def tag_line(tag: dict) -> str:
    return f"{tag['id']}  {tag['name']}  videos={tag.get('video_count', '-')}"


def task_line(task: dict) -> str:
    finished = task.get("finished_at") or "-"
    return f"{task['id']}  {task['kind']}  {task['status']}  {task.get('phase')}  {finished}"


def warn(message: str) -> None:
    print(message, file=sys.stderr)
