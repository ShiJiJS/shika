import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Mount:
    id: str
    name: str
    path: Path


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    mounts: tuple[Mount, ...]
    passphrase: str
    scan_interval: float = 300
    stability_seconds: float = 2
    probe_timeout: float = 20
    startup_scan: bool = True
    token_seconds: int = 30 * 24 * 3600
    media_streams: int = 4
    trash_dir: Path | None = None
    backup_max_bytes: int = 32 * 1024 * 1024

    def __post_init__(self):
        if len(self.passphrase) < 8:
            raise ValueError("The service passphrase must contain at least 8 characters")
        if not self.data_dir.is_absolute():
            raise ValueError("data_dir must be absolute")
        if not self.mounts or len({m.id for m in self.mounts}) != len(self.mounts):
            raise ValueError("Mounts must have unique IDs")
        for mount in self.mounts:
            if not mount.id or not mount.path.is_absolute() or mount.path == Path("/"):
                raise ValueError("Mounts require an ID and an absolute non-root path")
            if ".." in mount.path.parts:
                raise ValueError("Mount paths cannot contain parent components")
        if self.stability_seconds < 0 or self.scan_interval < 0 or self.probe_timeout <= 0:
            raise ValueError("Invalid scan timings")
        if not 1 <= self.media_streams <= 32:
            raise ValueError("media_streams must be between 1 and 32")
        if not 4096 <= self.backup_max_bytes <= 256 * 1024 * 1024:
            raise ValueError("backup_max_bytes must be between 4096 and 256 MiB")
        if self.trash_dir and (not self.trash_dir.is_absolute() or self.trash_dir == Path("/")):
            raise ValueError("trash_dir must be an absolute non-root directory")
        if self.trash_dir and (
            ".." in self.trash_dir.parts
            or "\x00" in str(self.trash_dir)
            or any(
                m.path == self.trash_dir or self.trash_dir in m.path.parents for m in self.mounts
            )
        ):
            raise ValueError("trash_dir cannot contain a media mount or parent components")

    @classmethod
    def from_env(cls):
        secret_file = os.environ.get("VV_PASSPHRASE_FILE", "/run/secrets/passphrase")
        secret = Path(secret_file).read_text().strip()
        raw = json.loads(Path(os.environ.get("VV_MOUNTS_FILE", "/config/mounts.json")).read_text())
        return cls(
            data_dir=Path(os.environ.get("VV_DATA_DIR", "/data")),
            mounts=tuple(Mount(m["id"], m["name"], Path(m["path"])) for m in raw),
            passphrase=secret,
            scan_interval=float(os.environ.get("VV_SCAN_INTERVAL", "300")),
            stability_seconds=float(os.environ.get("VV_STABILITY_SECONDS", "2")),
            probe_timeout=float(os.environ.get("VV_PROBE_TIMEOUT", "20")),
            media_streams=int(os.environ.get("VV_MEDIA_STREAMS", "4")),
            trash_dir=Path(os.environ["VV_TRASH_DIR"]) if os.environ.get("VV_TRASH_DIR") else None,
            backup_max_bytes=int(os.environ.get("VV_BACKUP_MAX_BYTES", str(32 * 1024 * 1024))),
        )
