"""对本地 stub 服务端的端到端测试：走真实 HTTP，覆盖 CLI 主要命令。

stub 只实现 video-viewer 契约中被 rv 用到的端点；行为按服务端代码核对
（错误信封、分页字段、幂等写要求的 request_id 等）。
"""

import json
import socketserver
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import pytest

from rv.cli import (
    EXIT_AUTH,
    EXIT_NOT_FOUND,
    EXIT_OK,
    main,
)

PASSPHRASE = "stub-passphrase"
NOW = time.time()


def make_state():
    return {
        "tokens": set(),
        "next_task": 0,
        "roots": [
            {
                "id": "r1",
                "name": "短视频",
                "path": "/media/shorts",
                "directory_id": "d0",
                "kind": "video",
                "enabled": True,
                "available": True,
                "error": None,
                "last_scan": None,
            }
        ],
        "directories": {
            "d0": {"id": "d0", "root_id": "r1", "path": "/media/shorts",
                   "name": "shorts", "available": True, "error": None},
            "d1": {"id": "d1", "root_id": "r1", "path": "/media/shorts/真人",
                   "name": "真人", "available": True, "error": None},
            "d2": {"id": "d2", "root_id": "r1", "path": "/media/shorts/动漫",
                   "name": "动漫", "available": True, "error": None},
        },
        "videos": [
            {"id": "v1", "root_id": "r1", "path": "真人/abc.mp4", "name": "abc.mp4",
             "status": "available", "error": None, "size": 123, "duration": 61.0,
             "type": "video", "tag_ids": ["t1"]},
            {"id": "v2", "root_id": "r1", "path": "真人/子/abc.mp4", "name": "abc.mp4",
             "status": "available", "error": None, "size": 456, "duration": 12.0,
             "type": "video", "tag_ids": []},
            {"id": "v3", "root_id": "r1", "path": "动漫/def.mp4", "name": "def.mp4",
             "status": "available", "error": None, "size": 789, "duration": 5.0,
             "type": "video", "tag_ids": []},
        ],
        "tags": [{"id": "t1", "name": "真人"}],
        "tasks": {},
        "backup_downloads": 0,
    }


class StubHandler(BaseHTTPRequestHandler):
    state = None  # 由 fixture 注入

    def log_message(self, *args):  # 静音访问日志
        pass

    # ------------------------------------------------------------- 工具

    def _send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status, code, message):
        self._send_json({"error": {"code": code, "message": message}}, status=status)

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        if header.startswith("Bearer ") and header[7:] in self.state["tokens"]:
            return True
        self._error(401, "unauthorized", "请先登录")
        return False

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def _query(self):
        return {k: v[-1] for k, v in parse_qs(urlparse(self.path).query).items()}

    def _task_json(self, task_id):
        task = self.state["tasks"][task_id]
        if task["status"] == "running":  # 第一次轮询后完成
            task["status"] = "completed"
            task["phase"] = "done"
            task["finished_at"] = time.time()
            task["result"] = {"added": 1, "processed": 3}
        return task

    # ------------------------------------------------------------- 路由

    def do_POST(self):
        state = self.state
        path = urlparse(self.path).path
        if path == "/api/v1/auth/login":
            if self._body().get("passphrase") != PASSPHRASE:
                return self._error(401, "invalid_credentials", "口令不正确")
            token = f"tok-{len(state['tokens']) + 1}"
            state["tokens"].add(token)
            return self._send_json(
                {"access_token": token, "token_type": "bearer",
                 "expires_at": time.time() + 3600}
            )
        if not self._authorized():
            return
        if path == "/api/v1/scans":
            state["next_task"] += 1
            task_id = f"scan-{state['next_task']}"
            state["tasks"][task_id] = {
                "id": task_id, "kind": "scan", "status": "running", "phase": "queued",
                "created_at": time.time(), "finished_at": None, "result": {},
                "error": None,
            }
            return self._send_json(state["tasks"][task_id], status=202)
        if path == "/api/v1/tags":
            body = self._body()
            name = (body.get("name") or "").strip()
            if not name or "request_id" not in body:
                return self._error(422, "invalid_request", "参数不完整")
            if any(tag["name"] == name for tag in state["tags"]):
                return self._error(409, "duplicate_tag", "已有同名标签")
            tag = {"id": f"t{len(state['tags']) + 1}", "name": name}
            state["tags"].append(tag)
            return self._send_json(tag, status=201)
        if path == "/api/v1/backups":
            body = self._body()
            if "request_id" not in body:
                return self._error(422, "invalid_request", "参数不完整")
            task_id = f"backup-{body['request_id']}"
            state["tasks"][task_id] = {
                "id": task_id, "kind": "backup_export", "status": "completed",
                "phase": "done", "created_at": time.time(),
                "finished_at": time.time(), "result": {"entries": 3}, "error": None,
            }
            return self._send_json(state["tasks"][task_id], status=202)
        return self._error(404, "not_found", "没有这个端点")

    def do_GET(self):
        state = self.state
        parsed = urlparse(self.path)
        path = parsed.path
        query = self._query()
        if path == "/health":
            return self._send_json({"status": "ok", "api_version": 1})
        if not self._authorized():
            return
        if path == "/api/v1/info":
            return self._send_json(
                {"server_id": "stub-server", "api_version": 1, "schema_version": "0012",
                 "sqlite_version": "3.0.0"}
            )
        if path == "/api/v1/roots":
            return self._send_json({"items": state["roots"]})
        if path == "/api/v1/tasks":
            return self._send_json({"items": list(state["tasks"].values())})
        if path.startswith("/api/v1/tasks/"):
            task_id = path.rsplit("/", 1)[1]
            if task_id not in state["tasks"]:
                return self._error(404, "task_not_found", "任务不存在")
            return self._send_json(self._task_json(task_id))
        if path == "/api/v1/directories/resolve":
            target = query.get("path")
            for directory in state["directories"].values():
                if directory["path"] == target:
                    return self._send_json(directory)
            return self._error(404, "directory_not_found", "目录不存在")
        if path == "/api/v1/videos":
            return self._videos(query)
        if path == "/api/v1/tags":
            search = query.get("search", "")
            items = [
                {**tag, "video_count": sum(
                    1 for video in state["videos"] if tag["id"] in video["tag_ids"]
                )}
                for tag in state["tags"] if search in tag["name"]
            ]
            items.sort(key=lambda tag: tag["name"])
            return self._send_json(
                {"items": items, "total": len(items), "offset": 0, "limit": 200}
            )
        if path.startswith("/api/v1/backups/") and path.endswith("/download"):
            task_id = path[len("/api/v1/backups/"):-len("/download")]
            if task_id not in state["tasks"]:
                return self._error(404, "backup_not_found", "备份不存在")
            state["backup_downloads"] += 1
            body = json.dumps({"payload": {"videos": 3}}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        return self._error(404, "not_found", "没有这个端点")

    def do_PATCH(self):
        state = self.state
        path = urlparse(self.path).path
        if not self._authorized():
            return
        if path == "/api/v1/video-tags":
            body = self._body()
            if "request_id" not in body:
                return self._error(422, "invalid_request", "参数不完整")
            videos = {v["id"]: v for v in state["videos"]}
            tags = {t["id"] for t in state["tags"]}
            if not set(body["video_ids"]) <= set(videos):
                return self._error(404, "video_not_found", "部分视频已不可用")
            if not set(body["tag_ids"]) <= tags:
                return self._error(404, "tag_not_found", "部分标签已不存在")
            mode = body.get("mode", "add")
            changed = 0
            for video_id in body["video_ids"]:
                before = set(videos[video_id]["tag_ids"])
                after = (
                    set(body["tag_ids"]) if mode == "replace"
                    else before | set(body["tag_ids"]) if mode == "add"
                    else before - set(body["tag_ids"])
                )
                videos[video_id]["tag_ids"] = sorted(after)
                changed += 1 if before != after else 0
            return self._send_json({"changed": changed})
        return self._error(404, "not_found", "没有这个端点")

    def do_DELETE(self):
        self._error(404, "not_found", "没有这个端点")

    def _videos(self, query):
        state = self.state
        items = [v for v in state["videos"] if v["status"] == query.get("status", "available")]
        directory_id = query.get("directory_id")
        if directory_id:
            directory = state["directories"].get(directory_id)
            if not directory:
                return self._error(404, "directory_not_found", "目录不存在")
            prefix = directory["path"].rstrip("/") + "/"
            items = [
                v for v in items if ("/media/shorts/" + v["path"]).startswith(prefix)
            ]
        search = query.get("search", "")
        if search:
            items = [
                v for v in items
                if search in v["name"] or search in v["path"]
            ]
        anchor = query.get("anchor_ids")
        if anchor:
            items = [v for v in items if v["id"] == anchor] or items[:1]
        offset = int(query.get("offset", 0))
        limit = int(query.get("limit", 50))
        page = items[offset:offset + limit]
        return self._send_json(
            {"items": page, "total": len(items), "offset": offset, "limit": limit}
        )


class FastHTTPServer(ThreadingHTTPServer):
    """跳过 HTTPServer.server_bind 里的 getfqdn 反向解析（部分环境会卡到超时）。"""

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = host
        self.server_port = port


@pytest.fixture(scope="module")
def server():
    handler = type("BoundStubHandler", (StubHandler,), {"state": make_state()})
    httpd = FastHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{httpd.server_address[1]}", handler.state
    httpd.shutdown()


@pytest.fixture(autouse=True)
def clean_env(monkeypatch):
    for key in ("RV_BASE_URL", "RV_TOKEN", "RV_PASSPHRASE", "RV_CONFIG_DIR",
                "RV_TIMEOUT", "XDG_CONFIG_HOME"):
        monkeypatch.delenv(key, raising=False)


@pytest.fixture
def env(server, tmp_path, monkeypatch):
    base_url, state = server
    monkeypatch.setenv("RV_BASE_URL", base_url)
    monkeypatch.setenv("RV_CONFIG_DIR", str(tmp_path / "rv"))
    monkeypatch.setenv("RV_PASSPHRASE", PASSPHRASE)
    return {"base_url": base_url, "state": state, "home": tmp_path}


def run_cli(argv):
    return main(argv)


def test_commands_need_login_first(env):
    assert run_cli(["videos"]) == EXIT_AUTH


def test_login_find_show_tag_roundtrip(env, capsys):
    assert run_cli(["login"]) == EXIT_OK
    assert "stub-server" in capsys.readouterr().out

    # find：子目录里有同名 abc.mp4，但绝对路径精确匹配只命中 v1
    assert run_cli(["find", "/media/shorts/真人/abc.mp4"]) == EXIT_OK
    assert "v1" in capsys.readouterr().out

    assert run_cli(["find", "/media/shorts/真人/missing.mp4"]) == EXIT_NOT_FOUND

    # tag add：名称自动 ensure，@id 直达；show 读回核对
    assert run_cli(["tag", "add", "v1", "黑发", "@t1"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["show", "v1"]) == EXIT_OK
    out = capsys.readouterr().out
    assert "真人" in out and "黑发" in out

    # 幂等：重复 add 不报错也不产生重复标签
    assert run_cli(["tag", "add", "v1", "黑发"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["tags"]) == EXIT_OK
    assert capsys.readouterr().out.count("黑发") == 1

    # remove
    assert run_cli(["tag", "remove", "v1", "黑发"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["show", "v1"]) == EXIT_OK
    assert "黑发" not in capsys.readouterr().out


def test_tag_add_unknown_tag_id_fails(env, capsys):
    assert run_cli(["login"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["tag", "add", "v1", "@nope"]) == EXIT_NOT_FOUND
    assert "tag_not_found" in capsys.readouterr().err


def test_scan_waits_until_completed(env, capsys):
    assert run_cli(["login"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["scan"]) == EXIT_OK
    out = capsys.readouterr().out
    assert "completed" in out


def test_backup_download(env, capsys, tmp_path):
    assert run_cli(["login"]) == EXIT_OK
    capsys.readouterr()
    target = tmp_path / "backup.json"
    assert run_cli(["backup", "--download", str(target)]) == EXIT_OK
    assert json.loads(target.read_text()) == {"payload": {"videos": 3}}
    assert env["state"]["backup_downloads"] == 1


def test_json_flag_before_subcommand(env, capsys):
    assert run_cli(["login"]) == EXIT_OK
    capsys.readouterr()
    assert run_cli(["--json", "find", "/media/shorts/动漫/def.mp4"]) == EXIT_OK
    payload = json.loads(capsys.readouterr().out)
    assert payload["matches"][0]["id"] == "v3"


def test_auto_relogin_on_stale_token(env, capsys):
    assert run_cli(["login"]) == EXIT_OK
    env["state"]["tokens"].clear()  # 服务端 token 全部失效
    capsys.readouterr()
    assert run_cli(["videos"]) == EXIT_OK  # RV_PASSPHRASE 触发自动重登录
    assert "v1" in capsys.readouterr().out
