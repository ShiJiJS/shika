"""本地配置与凭据的持久化。

配置和 token 保存在 RV_CONFIG_DIR（默认 ~/.config/rv）。token 文件以 0600
权限写入，只保存 Bearer token 与过期时间；口令一律不落盘。
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

CONFIG_NAME = "config.json"
TOKEN_NAME = "token.json"


def config_dir(explicit: str | None = None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    env = os.environ.get("RV_CONFIG_DIR")
    if env:
        return Path(env).expanduser()
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg).expanduser() if xdg else Path.home() / ".config"
    return base / "rv"


@dataclass
class Config:
    base_url: str | None = None
    timeout: float = 30.0


def load_config(directory: Path) -> Config:
    data: dict = {}
    path = directory / CONFIG_NAME
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            data = {}
    env_url = os.environ.get("RV_BASE_URL")
    env_timeout = os.environ.get("RV_TIMEOUT")
    return Config(
        base_url=env_url or data.get("base_url"),
        timeout=float(env_timeout or data.get("timeout") or 30.0),
    )


def save_config(directory: Path, config: Config) -> None:
    payload: dict = {}
    if config.base_url:
        payload["base_url"] = config.base_url
    if config.timeout != 30.0:
        payload["timeout"] = config.timeout
    directory.mkdir(parents=True, exist_ok=True)
    _write_private(
        directory / CONFIG_NAME, json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    )


@dataclass
class TokenRecord:
    base_url: str
    access_token: str
    expires_at: float


def load_token(directory: Path) -> TokenRecord | None:
    path = directory / TOKEN_NAME
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return TokenRecord(
            base_url=str(data["base_url"]),
            access_token=str(data["access_token"]),
            expires_at=float(data["expires_at"]),
        )
    except (KeyError, TypeError, ValueError):
        return None


def save_token(directory: Path, record: TokenRecord) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    payload = {
        "base_url": record.base_url,
        "access_token": record.access_token,
        "expires_at": record.expires_at,
    }
    _write_private(directory / TOKEN_NAME, json.dumps(payload) + "\n")


def clear_token(directory: Path) -> None:
    path = directory / TOKEN_NAME
    if path.exists():
        path.unlink()


def _write_private(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    handle = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(handle, "w", encoding="utf-8") as stream:
        stream.write(text)
