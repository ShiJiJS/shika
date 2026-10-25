"""配置与凭据持久化的单元测试。"""

import os
import stat

from rv.config import (
    Config,
    TokenRecord,
    config_dir,
    load_config,
    load_token,
    save_config,
    save_token,
)


def test_config_dir_env_override(tmp_path, monkeypatch):
    monkeypatch.setenv("RV_CONFIG_DIR", str(tmp_path / "custom"))
    assert config_dir() == tmp_path / "custom"
    monkeypatch.delenv("RV_CONFIG_DIR")
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "xdg"))
    assert config_dir() == tmp_path / "xdg" / "rv"


def test_config_roundtrip_and_env_precedence(tmp_path, monkeypatch):
    monkeypatch.delenv("RV_BASE_URL", raising=False)
    monkeypatch.delenv("RV_TIMEOUT", raising=False)
    save_config(tmp_path, Config(base_url="http://nas:8760", timeout=15.0))
    loaded = load_config(tmp_path)
    assert loaded.base_url == "http://nas:8760"
    assert loaded.timeout == 15.0
    monkeypatch.setenv("RV_BASE_URL", "http://override:1")
    assert load_config(tmp_path).base_url == "http://override:1"


def test_token_roundtrip_and_private_permissions(tmp_path):
    save_token(tmp_path, TokenRecord("http://nas:8760", "secret-token", 1_000_000.0))
    path = tmp_path / "token.json"
    mode = stat.S_IMODE(os.stat(path).st_mode)
    assert mode == 0o600
    record = load_token(tmp_path)
    assert record is not None
    assert (record.base_url, record.access_token, record.expires_at) == (
        "http://nas:8760",
        "secret-token",
        1_000_000.0,
    )


def test_load_token_tolerates_garbage(tmp_path):
    (tmp_path / "token.json").write_text("{ not json", encoding="utf-8")
    assert load_token(tmp_path) is None
