"""拾刻 · shika 服务端 HTTP API 的薄封装。

只做三件事：携带 Bearer token、把 ``{"error": {code, message}}`` 错误信封翻译成
ApiError、在只读查询 token 失效且环境提供了口令时自动重新登录一次。业务参数与响应
原样透传，不做字段改名——契约以服务端 openapi.json 为准。
"""

from __future__ import annotations

import secrets
import time
from collections.abc import Callable, Iterator
from typing import Any

import requests

TERMINAL_TASK_STATUSES = {"completed", "failed", "interrupted"}


class ApiError(Exception):
    """服务端返回的业务错误（含 401/404/409/422 等）。"""

    def __init__(
        self, status: int, code: str, message: str, fields: list[str] | None = None
    ) -> None:
        super().__init__(f"HTTP {status} {code}: {message}")
        self.status = status
        self.code = code
        self.message = message
        self.fields = fields or []


class TransportError(Exception):
    """网络层失败：连不上、超时、非 JSON 响应。"""


class WaitTimeout(Exception):
    """任务在给定时限内没有进入终态。"""


def new_request_id(prefix: str) -> str:
    """生成服务端写操作要求的 request_id（1-128 字符）。"""
    return f"rv-{prefix}-{secrets.token_urlsafe(12)}"


class RvClient:
    def __init__(
        self,
        base_url: str,
        token: str | None = None,
        timeout: float = 30.0,
        passphrase: str | None = None,
        auto_relogin: bool = True,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.token = token
        self.passphrase = passphrase
        self.auto_relogin = auto_relogin
        # 自动重登录成功后回调（CLI 用它把新 token 写回 0600 文件）
        self.token_listener: Callable[[str, float], None] | None = None
        self._session = requests.Session()

    # ------------------------------------------------------------------
    # 低层请求

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict | list | None = None,
        json_body: dict | None = None,
        auth: bool = True,
        stream: bool = False,
    ) -> requests.Response:
        response = self._send(method, path, params, json_body, auth, stream)
        if (response.status_code == 401 and auth and self.passphrase
                and self.auto_relogin and method.upper() in {"GET", "HEAD"}):
            refreshed = self._relogin()
            if refreshed:
                response = self._send(method, path, params, json_body, auth, stream)
        self._raise_for_error(response)
        return response

    def _send(
        self,
        method: str,
        path: str,
        params: dict | list | None,
        json_body: dict | None,
        auth: bool,
        stream: bool,
    ) -> requests.Response:
        headers = {"Accept": "application/json"}
        if auth:
            if not self.token:
                raise ApiError(401, "no_token", "尚未登录，请先运行 rv login")
            headers["Authorization"] = f"Bearer {self.token}"
        try:
            return self._session.request(
                method,
                self.base_url + path,
                params=params,
                json=json_body,
                headers=headers,
                timeout=self.timeout,
                stream=stream,
            )
        except requests.RequestException as error:
            raise TransportError(f"无法连接 {self.base_url}：{error}") from error

    def _relogin(self) -> bool:
        try:
            result = self.login(self.passphrase or "")
        except (ApiError, TransportError):
            return False
        self.token = result["access_token"]
        if self.token_listener:
            self.token_listener(self.token, float(result["expires_at"]))
        return True

    @staticmethod
    def _raise_for_error(response: requests.Response) -> None:
        if response.status_code < 400:
            return
        try:
            payload = response.json()
        except ValueError:
            payload = None
        error = payload.get("error") if isinstance(payload, dict) else None
        if isinstance(error, dict):
            raise ApiError(
                response.status_code,
                str(error.get("code", "unknown")),
                str(error.get("message", "")),
                error.get("fields"),
            )
        raise ApiError(
            response.status_code,
            "http_error",
            response.text[:200] or response.reason,
        )

    # ------------------------------------------------------------------
    # 认证与服务信息

    def login(self, passphrase: str) -> dict:
        response = self.request(
            "POST", "/api/v1/auth/login", json_body={"passphrase": passphrase}, auth=False
        )
        return response.json()

    def revoke(self) -> None:
        self.request("DELETE", "/api/v1/auth/session")

    def info(self) -> dict:
        return self.request("GET", "/api/v1/info").json()

    def roots(self) -> list[dict]:
        return self.request("GET", "/api/v1/roots").json()["items"]

    # ------------------------------------------------------------------
    # 扫描与任务

    def submit_scan(self) -> dict:
        return self.request("POST", "/api/v1/scans").json()

    def task(self, task_id: str) -> dict:
        return self.request("GET", f"/api/v1/tasks/{task_id}").json()

    def tasks(self, limit: int = 20) -> list[dict]:
        return self.request("GET", "/api/v1/tasks", params={"limit": limit}).json()["items"]

    def wait_task(self, task_id: str, timeout: float = 600.0, poll: float = 1.0) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            task = self.task(task_id)
            if task.get("status") in TERMINAL_TASK_STATUSES:
                return task
            if time.monotonic() >= deadline:
                raise WaitTimeout(
                    f"任务 {task_id} 在 {timeout:.0f}s 内未完成（当前状态 {task.get('status')}）"
                )
            time.sleep(poll)

    # ------------------------------------------------------------------
    # 目录

    def resolve_directory(self, path: str, kind: str = "video") -> dict:
        return self.request(
            "GET",
            "/api/v1/directories/resolve",
            params={"path": path, "kind": kind},
        ).json()

    def directories(
        self, parent_id: str | None = None, kind: str = "video", limit: int = 200
    ) -> dict:
        params: dict[str, Any] = {"kind": kind, "limit": limit}
        if parent_id:
            params["parent_id"] = parent_id
        return self.request("GET", "/api/v1/directories", params=params).json()

    # ------------------------------------------------------------------
    # 视频

    VIDEO_FILTERS = (
        "directory_id",
        "status",
        "search",
        "orientation",
        "duration",
        "file_type",
        "source",
        "sort",
        "anchor_ids",
    )

    def videos(self, *, offset: int = 0, limit: int = 50, tag_ids: list[str] | None = None,
               **filters: Any) -> dict:
        params: list[tuple[str, Any]] = [("offset", offset), ("limit", limit)]
        for key, value in filters.items():
            if key not in self.VIDEO_FILTERS:
                raise TypeError(f"不支持的查询参数：{key}")
            if value is not None and value != "":
                params.append((key, value))
        for tag_id in tag_ids or ():
            params.append(("tag_ids", tag_id))
        return self.request("GET", "/api/v1/videos", params=params).json()

    def iter_videos(self, page: int = 200, **filters: Any) -> Iterator[dict]:
        offset = 0
        while True:
            result = self.videos(offset=offset, limit=page, **filters)
            yield from result["items"]
            offset += len(result["items"])
            if offset >= result["total"] or not result["items"]:
                return

    # ------------------------------------------------------------------
    # 标签

    def tags(self, search: str = "", offset: int = 0, limit: int = 200) -> dict:
        return self.request(
            "GET",
            "/api/v1/tags",
            params={"search": search, "offset": offset, "limit": limit},
        ).json()

    def iter_tags(self, search: str = "") -> Iterator[dict]:
        offset = 0
        while True:
            result = self.tags(search=search, offset=offset)
            yield from result["items"]
            offset += len(result["items"])
            if offset >= result["total"] or not result["items"]:
                return

    def create_tag(self, name: str, request_id: str) -> dict:
        return self.request(
            "POST", "/api/v1/tags", json_body={"request_id": request_id, "name": name}
        ).json()

    def assign_tags(
        self, video_ids: list[str], tag_ids: list[str], mode: str, request_id: str
    ) -> dict:
        return self.request(
            "PATCH",
            "/api/v1/video-tags",
            json_body={
                "request_id": request_id,
                "video_ids": video_ids,
                "tag_ids": tag_ids,
                "mode": mode,
            },
        ).json()

    def ensure_tag(self, name: str, request_id: str | None = None) -> dict:
        """按精确名称查重，不存在则创建；返回 {id, name, created}。"""
        for tag in self.iter_tags(search=name):
            if tag["name"] == name:
                return {**tag, "created": False}
        try:
            tag = self.create_tag(name, request_id or new_request_id("tag"))
            return {**tag, "created": True}
        except ApiError as error:
            if error.status == 409 and error.code == "duplicate_tag":
                for tag in self.iter_tags(search=name):
                    if tag["name"] == name:
                        return {**tag, "created": False}
            raise

    # ------------------------------------------------------------------
    # 备份

    def create_backup(self, request_id: str) -> dict:
        return self.request(
            "POST", "/api/v1/backups", json_body={"request_id": request_id}
        ).json()

    def download_backup(self, backup_id: str) -> bytes:
        response = self.request(
            "GET", f"/api/v1/backups/{backup_id}/download", stream=True
        )
        return response.content
