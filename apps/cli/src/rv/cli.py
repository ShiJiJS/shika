"""rv 命令行入口。

与主程序代码分目录维护（仓库内 apps/cli）：本包只消费服务端 HTTP API，
不 import 服务端代码，也不读写其数据库。
"""

from __future__ import annotations

import argparse
import getpass
import os
import posixpath
import sys
import time
from pathlib import Path

from . import __version__
from .client import ApiError, RvClient, TransportError, WaitTimeout, new_request_id
from .config import (
    Config,
    TokenRecord,
    clear_token,
    load_config,
    load_token,
    save_config,
    save_token,
)
from .config import (
    config_dir as resolve_config_dir,
)
from .output import human_size, print_json, tag_line, task_line, video_line, warn

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_TRANSPORT = 3
EXIT_AUTH = 4
EXIT_NOT_FOUND = 5
EXIT_CONFLICT = 6
EXIT_API = 7
EXIT_WAIT = 8


class Context:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.directory = resolve_config_dir(args.config_dir)
        self.config = load_config(self.directory)
        self.json = args.json
        self.quiet = args.quiet
        base_url = args.base_url or self.config.base_url
        if not base_url:
            raise ApiError(401, "no_base_url", "未配置服务地址，请 rv login --base-url URL")
        self.base_url = base_url.rstrip("/")
        self.timeout = args.timeout or self.config.timeout

        token = args.token or os.environ.get("RV_TOKEN")
        if not token:
            record = load_token(self.directory)
            if record and record.base_url.rstrip("/") == self.base_url:
                token = record.access_token
        self.passphrase = args.passphrase or os.environ.get("RV_PASSPHRASE")
        self.client = RvClient(
            self.base_url, token=token, timeout=self.timeout, passphrase=self.passphrase
        )
        self.client.token_listener = self._persist_token

    def _persist_token(self, access_token: str, expires_at: float) -> None:
        save_token(self.directory, TokenRecord(self.base_url, access_token, expires_at))

    def say(self, message: str) -> None:
        if not self.quiet and not self.json:
            print(message)

    def emit(self, payload) -> None:
        if self.json:
            print_json(payload)
        elif not self.quiet:
            if isinstance(payload, list):
                for item in payload:
                    print(item)
            else:
                print(payload)


# ----------------------------------------------------------------------
# 命令实现


def cmd_login(ctx: Context) -> int:
    passphrase = ctx.passphrase
    if not passphrase:
        if sys.stdin.isatty():
            passphrase = getpass.getpass("口令: ")
        else:
            raise ApiError(401, "no_passphrase", "非交互环境请用 RV_PASSPHRASE 或 --passphrase")
    result = ctx.client.login(passphrase)
    ctx.client.token = result["access_token"]
    save_config(ctx.directory, Config(base_url=ctx.base_url, timeout=ctx.timeout))
    ctx._persist_token(result["access_token"], float(result["expires_at"]))
    info = ctx.client.info()
    ctx.say(f"已登录 {ctx.base_url}（server_id={info.get('server_id')}，"
            f"schema={info.get('schema_version')}）")
    return EXIT_OK


def cmd_logout(ctx: Context) -> int:
    try:
        ctx.client.revoke()
        ctx.say("已在服务端撤销会话")
    except ApiError as error:
        if error.status != 401:
            raise
        ctx.say("token 已失效，直接清除本地记录")
    clear_token(ctx.directory)
    return EXIT_OK


def cmd_info(ctx: Context) -> int:
    info = ctx.client.info()
    if ctx.json:
        print_json({"base_url": ctx.base_url, **info})
    else:
        ctx.say(f"base_url  {ctx.base_url}")
        for key in ("server_id", "api_version", "schema_version", "sqlite_version"):
            if key in info:
                ctx.say(f"{key}  {info[key]}")
        record = load_token(ctx.directory)
        if record:
            remaining = record.expires_at - time.time()
            if remaining > 0:
                ctx.say(f"token    约 {int(remaining // 3600)} 小时后过期")
            else:
                ctx.say("token    已过期（重新 rv login）")
    return EXIT_OK


def cmd_scan(ctx: Context) -> int:
    task = ctx.client.submit_scan()
    if ctx.args.no_wait:
        ctx.emit(task_line(task))
        if ctx.json:
            print_json(task)
        return EXIT_OK
    task = ctx.client.wait_task(task["id"], timeout=ctx.args.wait_timeout)
    _report_task(ctx, task)
    if task["status"] != "completed":
        return EXIT_API
    return EXIT_OK


def _report_task(ctx: Context, task: dict) -> None:
    if ctx.json:
        print_json(task)
        return
    ctx.say(task_line(task))
    result = task.get("result")
    if isinstance(result, dict):
        for key, value in result.items():
            if isinstance(value, (int, float, str)):
                ctx.say(f"  {key}  {value}")
    if task.get("error"):
        warn(f"任务错误：{task['error']}")


def cmd_tasks(ctx: Context) -> int:
    items = ctx.client.tasks(limit=ctx.args.limit)
    if ctx.json:
        print_json({"items": items})
    else:
        for task in items:
            print(task_line(task))
    return EXIT_OK


def cmd_task(ctx: Context) -> int:
    task = ctx.client.wait_task(ctx.args.task_id, timeout=ctx.args.wait_timeout)
    _report_task(ctx, task)
    return EXIT_OK if task["status"] == "completed" else EXIT_API


def cmd_dirs(ctx: Context) -> int:
    page = ctx.client.directories(
        parent_id=ctx.args.parent_id, kind=ctx.args.kind, limit=ctx.args.limit
    )
    if ctx.json:
        print_json(page)
    else:
        for item in page["items"]:
            mark = "" if item.get("available", True) else "  [不可用]"
            print(f"{item['id']}  {item['path']}{mark}")
    return EXIT_OK


def cmd_resolve(ctx: Context) -> int:
    directory = ctx.client.resolve_directory(ctx.args.path, kind=ctx.args.kind)
    if ctx.json:
        print_json(directory)
    else:
        ctx.say(
            f"{directory['id']}  {directory['path']}"
            f"  root={directory['root_id']}"
            f"  {'可用' if directory['available'] else '不可用：' + str(directory['error'])}"
        )
    return EXIT_OK


def cmd_videos(ctx: Context) -> int:
    filters = {
        "directory_id": ctx.args.directory_id,
        "search": ctx.args.search,
        "status": ctx.args.status,
        "source": ctx.args.source,
        "sort": ctx.args.sort,
    }
    page = ctx.client.videos(
        offset=ctx.args.offset, limit=ctx.args.limit, tag_ids=ctx.args.tag_id, **filters
    )
    if ctx.json:
        print_json(page)
    else:
        for video in page["items"]:
            print(video_line(video))
        print(f"共 {page['total']} 条（offset={page['offset']}，limit={page['limit']}）")
    return EXIT_OK


def cmd_find(ctx: Context) -> int:
    target = posixpath.normpath(ctx.args.path.strip())
    parent, name = posixpath.split(target)
    if not name:
        raise ApiError(404, "invalid_path", f"路径不像一个文件：{ctx.args.path}")
    try:
        directory = ctx.client.resolve_directory(parent or "/")
    except ApiError as error:
        if error.status == 404:
            raise ApiError(
                404,
                "directory_not_found",
                f"目录尚未被扫描收录：{parent}。先运行 rv scan 等扫描完成后再试。",
            ) from error
        raise
    matches = []
    for video in ctx.client.iter_videos(directory_id=directory["id"], search=name):
        root_path = _root_path(ctx, video["root_id"])
        absolute = posixpath.normpath(posixpath.join(root_path, video["path"]))
        if absolute == target:
            matches.append(video)
    if not matches:
        raise ApiError(
            404,
            "video_not_found",
            f"扫描范围内没有这个文件：{target}。可先 rv scan，或用 rv videos --search 查名称。",
        )
    if ctx.json:
        print_json({"matches": matches})
    else:
        for video in matches:
            print(video_line(video))
    if len(matches) > 1:
        warn(f"同名文件有 {len(matches)} 个，请用 id 精确指定")
        return EXIT_CONFLICT
    return EXIT_OK


def _root_path(ctx: Context, root_id: str) -> str:
    roots = getattr(ctx, "_roots", None)
    if roots is None:
        roots = {root["id"]: root["path"] for root in ctx.client.roots()}
        ctx._roots = roots
    return roots.get(root_id, "")


def cmd_show(ctx: Context) -> int:
    video = None
    for status in ("available", "missing", "trash"):
        page = ctx.client.videos(
            limit=1, status=status, anchor_ids=[ctx.args.video_id]
        )
        for item in page["items"]:
            if item["id"] == ctx.args.video_id:
                video = item
                break
        if video:
            break
    if not video:
        raise ApiError(404, "video_not_found", f"没有这个视频：{ctx.args.video_id}")
    names = {tag["id"]: tag["name"] for tag in ctx.client.iter_tags()}
    payload = {**video, "tags": sorted(names.get(t, t) for t in video["tag_ids"])}
    if ctx.json:
        print_json(payload)
    else:
        for key in ("id", "root_id", "path", "status", "size", "duration", "type",
                    "video_codec", "audio_codec", "container"):
            ctx.say(f"{key}  {payload.get(key)}")
        ctx.say(f"大小    {human_size(payload.get('size'))}")
        ctx.say(f"标签    {'、'.join(payload['tags']) or '（无）'}")
    return EXIT_OK


def cmd_tags(ctx: Context) -> int:
    page = ctx.client.tags(search=ctx.args.search, limit=ctx.args.limit)
    if ctx.json:
        print_json(page)
    else:
        for tag in page["items"]:
            print(tag_line(tag))
        print(f"共 {page['total']} 条")
    return EXIT_OK


def _resolve_tag_spec(ctx: Context, spec: str) -> tuple[str, str]:
    if spec.startswith("@"):
        return spec[1:], spec
    tag = ctx.client.ensure_tag(spec)
    if tag.get("created"):
        ctx.say(f"新建标签 {tag['name']}（{tag['id']}）")
    return tag["id"], tag["name"]


MODE_VERBS = {"add": "追加", "remove": "移除", "replace": "替换"}


def cmd_tag_assign(ctx: Context) -> int:
    args = ctx.args
    video_ids = [args.video_id, *args.video]
    resolved = [_resolve_tag_spec(ctx, spec) for spec in args.tags]
    tag_ids = sorted({tag_id for tag_id, _ in resolved})
    result = ctx.client.assign_tags(
        video_ids, tag_ids, args.mode, args.request_id or new_request_id(f"tags-{args.mode}")
    )
    if ctx.json:
        print_json(result)
    else:
        names = "、".join(name for _, name in resolved)
        verb = MODE_VERBS.get(args.mode, args.mode)
        ctx.say(f"已对 {len(video_ids)} 个视频{verb}标签：{names}")
    return EXIT_OK


def cmd_tag_rename(ctx: Context) -> int:
    result = ctx.client.request(
        "PATCH",
        f"/api/v1/tags/{ctx.args.tag_id}",
        json_body={
            "request_id": ctx.args.request_id or new_request_id("tag-rename"),
            "name": ctx.args.name,
        },
    ).json()
    if ctx.json:
        print_json(result)
    else:
        ctx.say(f"已改名 {result['id']} → {result['name']}")
    return EXIT_OK


def cmd_tag_delete(ctx: Context) -> int:
    ctx.client.request(
        "DELETE",
        f"/api/v1/tags/{ctx.args.tag_id}",
        json_body={"request_id": ctx.args.request_id or new_request_id("tag-delete")},
    )
    ctx.say(f"已删除标签 {ctx.args.tag_id}（原视频文件保留）")
    return EXIT_OK


def cmd_backup(ctx: Context) -> int:
    task = ctx.client.create_backup(
        ctx.args.request_id or new_request_id("backup")
    )
    task = ctx.client.wait_task(task["id"], timeout=ctx.args.wait_timeout)
    if ctx.json:
        print_json(task)
    else:
        ctx.say(task_line(task))
    if task["status"] != "completed":
        return EXIT_API
    if ctx.args.download:
        data = ctx.client.download_backup(task["id"])
        path = Path(ctx.args.download).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        os.chmod(path, 0o600)
        ctx.say(f"备份已写入 {path}（{human_size(len(data))}）")
    else:
        ctx.say(f"备份 ID {task['id']}；需要文件时用 --download 下载")
    return EXIT_OK


# ----------------------------------------------------------------------
# 参数解析


def _common_parser(sub: bool) -> argparse.ArgumentParser:
    # 子命令版本的默认值全部 SUPPRESS：否则子解析器会用自己的默认值
    # 覆盖用户在全局位置已经传入的 --json / --base-url 等选项。
    default = argparse.SUPPRESS if sub else None
    store_true = {"action": "store_true", "default": argparse.SUPPRESS if sub else False}
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--base-url", default=default, metavar="URL",
                        help="服务地址（默认取 RV_BASE_URL 或配置文件）")
    parser.add_argument("--config-dir", default=default, metavar="DIR",
                        help="配置目录（默认 ~/.config/rv）")
    parser.add_argument("--timeout", type=float, default=default, metavar="SEC",
                        help="单次 HTTP 请求超时秒数")
    parser.add_argument("--token", default=default, metavar="TOKEN",
                        help="直接提供 Bearer token（默认取 RV_TOKEN 或缓存）")
    parser.add_argument("--passphrase", default=default, metavar="PASS",
                        help="口令（默认取 RV_PASSPHRASE；token 失效时自动重登录）")
    parser.add_argument("--json", **store_true,
                        help="以 JSON 输出结果（适合脚本）")
    parser.add_argument("--quiet", **store_true,
                        help="减少说明性输出")
    return parser


def build_parser() -> argparse.ArgumentParser:
    common = _common_parser(sub=False)
    common_sub = _common_parser(sub=True)
    parser = argparse.ArgumentParser(
        prog="rv",
        parents=[common],
        description="video-viewer NAS 媒体库命令行客户端",
    )
    parser.add_argument("--version", action="version", version=f"rv {__version__}")
    sub = parser.add_subparsers(dest="command", required=True, metavar="<命令>")

    def command(name: str, help_text: str, handler):
        child = sub.add_parser(name, parents=[common_sub], help=help_text)
        child.set_defaults(handler=handler)
        return child

    command("login", "登录并缓存 token", cmd_login)
    command("logout", "撤销会话并清除本地 token", cmd_logout)
    command("info", "显示服务与连接信息", cmd_info)

    scan = command("scan", "触发媒体扫描并等待完成", cmd_scan)
    scan.add_argument("--no-wait", action="store_true", help="只提交，不等待完成")
    scan.add_argument("--wait-timeout", type=float, default=600.0, metavar="SEC")

    command("tasks", "最近任务列表", cmd_tasks).add_argument("--limit", type=int, default=20)
    task_cmd = command("task", "查看/等待一个任务", cmd_task)
    task_cmd.add_argument("task_id")
    task_cmd.add_argument("--wait-timeout", type=float, default=600.0, metavar="SEC")

    dirs = command("dirs", "列出目录（默认顶层）", cmd_dirs)
    dirs.add_argument("--parent-id", metavar="ID")
    dirs.add_argument("--kind", choices=["video", "pack"], default="video")
    dirs.add_argument("--limit", type=int, default=200)

    resolve = command("resolve", "按服务端路径解析目录 ID", cmd_resolve)
    resolve.add_argument("path")
    resolve.add_argument("--kind", choices=["video", "pack"], default="video")

    videos = command("videos", "分页查询视频", cmd_videos)
    videos.add_argument("--directory-id", metavar="ID")
    videos.add_argument("--search", default="")
    videos.add_argument("--status", choices=["available", "missing", "trash"],
                        default="available")
    videos.add_argument("--tag-id", action="append", metavar="ID",
                        help="按标签过滤，可重复表示 AND")
    videos.add_argument("--source", choices=["library", "tags", "recent"], default="library")
    videos.add_argument("--sort", choices=["path", "name", "newest", "recent"], default="path")
    videos.add_argument("--offset", type=int, default=0)
    videos.add_argument("--limit", type=int, default=50)

    command("find", "按服务端文件路径定位视频", cmd_find).add_argument("path")
    command("show", "查看单个视频详情（含标签名）", cmd_show).add_argument("video_id")

    tags_cmd = command("tags", "标签列表", cmd_tags)
    tags_cmd.add_argument("--search", default="")
    tags_cmd.add_argument("--limit", type=int, default=200)

    tag_cmd = sub.add_parser("tag", parents=[common_sub], help="标签写操作")
    tag_sub = tag_cmd.add_subparsers(dest="tag_action", required=True, metavar="<动作>")
    for name, mode, help_text in (
        ("add", "add", "给视频追加标签（标签按名称自动 ensure）"),
        ("remove", "remove", "移除视频的指定标签"),
        ("replace", "replace", "精确替换视频全部标签（谨慎）"),
    ):
        assign = tag_sub.add_parser(name, parents=[common_sub], help=help_text)
        assign.add_argument("video_id", metavar="VIDEO_ID")
        assign.add_argument("tags", nargs="+", metavar="TAG",
                            help="标签名或 @id")
        assign.add_argument("--video", action="append", default=[], metavar="ID",
                            help="追加更多视频 ID（批量）")
        assign.add_argument("--request-id", help="重试时复用同一 request_id")
        assign.set_defaults(handler=cmd_tag_assign, mode=mode)

    rename = tag_sub.add_parser("rename", parents=[common_sub], help="标签改名")
    rename.add_argument("tag_id")
    rename.add_argument("--name", required=True)
    rename.add_argument("--request-id")
    rename.set_defaults(handler=cmd_tag_rename)
    delete = tag_sub.add_parser("delete", parents=[common_sub], help="删除标签（文件保留）")
    delete.add_argument("tag_id")
    delete.add_argument("--request-id")
    delete.set_defaults(handler=cmd_tag_delete)

    backup = command("backup", "创建管理备份（可下载）", cmd_backup)
    backup.add_argument("--download", metavar="FILE", help="下载备份到本地文件")
    backup.add_argument("--wait-timeout", type=float, default=600.0, metavar="SEC")
    backup.add_argument("--request-id")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        ctx = Context(args)
        return args.handler(ctx)
    except ApiError as error:
        message = f"错误 {error.code}：{error.message}"
        if error.fields:
            message += f"（字段：{'、'.join(error.fields)}）"
        if error.status == 401:
            message += "；请先 rv login"
        warn(message)
        return {
            401: EXIT_AUTH,
            404: EXIT_NOT_FOUND,
            409: EXIT_CONFLICT,
        }.get(error.status, EXIT_API)
    except TransportError as error:
        warn(f"连接失败：{error}")
        return EXIT_TRANSPORT
    except WaitTimeout as error:
        warn(str(error))
        return EXIT_WAIT
    except KeyboardInterrupt:
        warn("已中断")
        return 130


if __name__ == "__main__":
    sys.exit(main())
