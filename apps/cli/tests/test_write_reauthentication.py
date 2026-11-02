"""A write command must not adopt a restored library through automatic login."""

import copy
import json
import os
import threading
import time

import pytest
from test_e2e import PASSPHRASE, FastHTTPServer, StubHandler, make_state

from rv.cli import EXIT_AUTH, EXIT_OK, main
from rv.client import ApiError, RvClient


class AuthorityHandler(StubHandler):
    def do_POST(self):
        if self.path == "/api/v1/auth/login":
            if self._body().get("passphrase") != PASSPHRASE:
                return self._error(401, "invalid_credentials", "口令不正确")
            self.state["login_count"] += 1
            token = f"authority-token-{self.state['login_count']}"
            self.state["tokens"].add(token)
            self.state["issued_epochs"][token] = self.state["epoch"]
            return self._send_json(
                {
                    "access_token": token,
                    "expires_at": time.time() + 3600,
                    "management_epoch": self.state["epoch"],
                }
            )
        return super().do_POST()

    def _authorized(self):
        if not super()._authorized():
            return False
        if self.command not in {"GET", "HEAD"}:
            token = self.headers["Authorization"][7:]
            expected = self.headers.get("X-Management-Epoch", self.state["issued_epochs"][token])
            if expected != self.state["epoch"]:
                self._error(409, "management_changed", "管理数据已恢复，请重新核对")
                return False
            self.state["admitted_writes"] += 1
        return True


@pytest.fixture
def restored_library(tmp_path, monkeypatch):
    state = make_state()
    state.update(epoch="a" * 32, issued_epochs={}, login_count=0, admitted_writes=0)
    handler = type("BoundAuthorityHandler", (AuthorityHandler,), {"state": state})
    server = FastHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    for name in ("RV_TOKEN", "RV_TIMEOUT", "XDG_CONFIG_HOME"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("RV_BASE_URL", f"http://127.0.0.1:{server.server_port}")
    monkeypatch.setenv("RV_CONFIG_DIR", str(tmp_path))
    monkeypatch.setenv("RV_PASSPHRASE", PASSPHRASE)
    try:
        assert main(["login"]) == EXIT_OK
        original_token = (tmp_path / "token.json").read_bytes()
        # Restoration changes authority; then the old credential expires.
        state["epoch"] = "b" * 32
        state["tokens"].clear()
        yield state, tmp_path, original_token
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


@pytest.mark.parametrize(
    "command",
    [
        ["scan", "--no-wait"],
        ["tag", "add", "v1", "new-tag"],
    ],
)
def test_expired_write_command_never_reauthenticates_into_restored_data(restored_library, command):
    state, directory, original_token = restored_library
    before = copy.deepcopy((state["videos"], state["tags"], state["tasks"]))
    assert main(command) == EXIT_AUTH
    assert state["login_count"] == 1
    assert state["admitted_writes"] == 0
    assert (state["videos"], state["tags"], state["tasks"]) == before
    assert (directory / "token.json").read_bytes() == original_token
    # Explicit login makes a new command possible after the user rechecks data.
    assert main(["login"]) == EXIT_OK
    assert main(command) == EXIT_OK
    assert state["admitted_writes"] > 0


def test_read_only_command_keeps_existing_automatic_login_behavior(restored_library, capsys):
    state, directory, _ = restored_library
    capsys.readouterr()
    assert main(["videos"]) == EXIT_OK
    assert "v1" in capsys.readouterr().out
    assert state["login_count"] == 2
    assert state["admitted_writes"] == 0
    assert json.loads((directory / "token.json").read_text())["access_token"] in state["tokens"]


def test_direct_client_never_reauthenticates_and_replays_a_post(restored_library):
    state, directory, original_token = restored_library
    client = RvClient(
        os.environ["RV_BASE_URL"],
        token=json.loads(original_token)["access_token"],
        passphrase=PASSPHRASE,
    )
    with pytest.raises(ApiError) as failure:
        client.submit_scan()
    assert failure.value.status == 401
    assert state["login_count"] == 1
    assert state["admitted_writes"] == 0
    assert (directory / "token.json").read_bytes() == original_token
