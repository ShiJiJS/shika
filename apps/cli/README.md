[项目首页](../../README.md) · [文档导航](../../docs/README.md) · [部署手册](../../docs/deployment.md)

# 拾刻 · shika 命令行客户端

`shika` 与兼容命令 `rv` 使用同一入口，版本和 Python 要求见 [pyproject.toml](pyproject.toml)。CLI 支持登录、扫描、视频查询、视频标签及旧视频管理备份；图包阅读和完整管理备份使用 App。

修改命令（包括标签名称查询等前置读取）遇401即停止；先显式 `rv login`，核对当前数据后再执行。只读命令可自动重登录一次，不会把旧修改命令自动带入恢复后的管理数据。

与主程序代码**分目录维护**（`apps/cli`，与 `apps/mobile`、`services/server`
并列）：这里只有 HTTP API 的消费代码，不 import 服务端代码、不读写其数据库，
也不感知部署形态。接口契约以服务端 `/openapi.json` 为准，本目录不复制契约定义。

主要用途有两个：手动排查库状态，以及作为自动流水线（Telegram 收集 → 下载 →
打标 → 落 NAS → 标签同步）的执行入口。`--json` 输出专为脚本消费设计。

## 安装

Python 版本要求以 `pyproject.toml` 为准。

```bash
uv tool install "git+ssh://git@github.com/ShiJiJS/shika.git#subdirectory=apps/cli"
# 或
pipx install "git+ssh://git@github.com/ShiJiJS/shika.git#subdirectory=apps/cli"
# 本地开发（在 apps/cli 目录内）
python3 -m venv .venv && . .venv/bin/activate && pip install -e '.[dev]'
```

## 配套 Skill（选装）

[video-tagging](../../skills/video-tagging/SKILL.md) 可生成标准标签文件，并在要求同步时通过本 CLI 或服务端 API 写入视频标签。安装 Skill 时可同时配置隔离 CLI，命令与依赖说明见[视频打标指南](../../docs/video-tagging.md)。CLI 也可按上面的方式独立安装，App 与 NAS 服务不依赖这些选装工具。

## 快速开始

```bash
rv login --base-url http://192.168.1.10:8760     # 口令走 RV_PASSPHRASE 或交互输入
rv scan                                           # 触发扫描并等待完成
rv find /media/shorts/真人/abc.mp4                # 服务端路径 → 视频 ID
rv tag add <VIDEO_ID> 真人 黑发                    # 标签名不存在会自动创建
rv show <VIDEO_ID>                                # 读回核对标签
rv backup --download backup.json                  # 视频管理备份，不包含图包
```

注意 `find` / `resolve` 用的是**服务端容器内路径**（mounts.json 声明的范围，
如 `/media/shorts/...`），不是 NAS 的 SMB 挂载路径；两者映射关系由部署配置决定。

## 命令一览

| 命令 | 作用 |
| --- | --- |
| `rv login` / `rv logout` | 登录缓存 token / 撤销会话并清除本地记录 |
| `rv info` | 服务信息与当前连接、token 有效期 |
| `rv scan` | 触发媒体扫描并等待完成（`--no-wait` 只提交） |
| `rv tasks` / `rv task <ID>` | 最近任务 / 查看或等待单个任务 |
| `rv dirs` / `rv resolve <PATH>` | 目录树 / 按服务端路径解析目录 ID |
| `rv videos` | 分页查询（`--search`、`--directory-id`、`--tag-id` 可重复表示 AND） |
| `rv find <PATH>` | 服务端文件路径精确定位视频；同名多个时列全部并返回冲突码 |
| `rv show <VIDEO_ID>` | 单视频详情，标签解析为名称，用于读回核对 |
| `rv tags [--search]` | 标签列表 |
| `rv tag add/remove/replace <VIDEO_ID> <TAG>...` | 打标；标签写名称（自动 ensure）或 `@id`；`--video` 可重复追加批量视频 |
| `rv tag-rename <TAG_ID> --name` / `rv tag-delete <TAG_ID>` | 标签维护 |
| `rv backup [--download FILE]` | 创建旧 v1 视频管理备份并等待，可选下载（文件写 0600）；完整视频/图包备份请使用 App |

全局选项（子命令前后都可以）：`--base-url`、`--config-dir`、`--timeout`、
`--token`、`--passphrase`、`--json`、`--quiet`。

## 配置与凭据

优先级：命令行参数 > 环境变量 > 配置文件（`~/.config/rv/config.json`，可用
`RV_CONFIG_DIR` 改位置）。

| 环境变量 | 作用 |
| --- | --- |
| `RV_BASE_URL` | 服务地址 |
| `RV_TOKEN` | 直接提供 Bearer token（CI / 一次性调用） |
| `RV_PASSPHRASE` | 口令。只读命令遇401时可自动重登录一次；修改命令须先显式登录 |
| `RV_TIMEOUT` | 单次请求超时秒数 |
| `RV_CONFIG_DIR` | 配置目录 |

token 缓存在 `~/.config/rv/token.json`，权限 0600，并绑定 base_url：换服务地址
不会把 token 发给别的地址。口令永远不落盘。

## 幂等与重试

自动重登录仅适用于`info/tasks/task/dirs/resolve/videos/find/show/tags`等只读命令。扫描、备份、标签修改和退出登录不会自动重新登录；修改流程中的前置GET也遵守同一限制。底层HTTP客户端不自动重放POST/PATCH/DELETE。

服务端写操作使用 `request_id`。`rv` 未指定时会生成新 ID；需要可核对的重试时，事先通过 `--request-id` 指定并保留该值，在同一服务和相同内容下复用。响应不确定时先读回标签或任务结果，不把重新执行命令当作查询；401后仍须先显式登录并核对数据。

## 退出码

| 码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 2 | 用法错误（argparse） |
| 3 | 连接失败 |
| 4 | 未登录 / token 失效 |
| 5 | 资源不存在 |
| 6 | 冲突（同名多文件、409 等） |
| 7 | 其他服务端错误，或任务终态为 failed/interrupted |
| 8 | 等待任务超时 |

## 开发

在仓库根目录使用独立环境及 `uv.lock` 运行（客户端和服务端环境见[开发指南](../../docs/development.md)）：

```bash
UV_PROJECT_ENVIRONMENT="$PWD/.dev/cli" uv --directory apps/cli run --locked --extra dev rv --help
UV_PROJECT_ENVIRONMENT="$PWD/.dev/cli" uv --directory apps/cli run --locked --extra dev pytest -q
```

测试只连接本机临时HTTP样本服务，并使用临时凭据目录，不连接NAS。也可在 `apps/cli` 目录使用 pip 开发环境：

```bash
pip install -e '.[dev]'
pytest            # 含对本地 stub 服务端的端到端测试
ruff check src tests
```
