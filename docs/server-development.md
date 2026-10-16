# 服务端开发环境

2026-10-16 环境检查结论：本机 WSL2 中的 Docker 可以用于服务端开发，Windows 和 Android 模拟器均可访问容器发布的端口。当次环境探针不代表业务实现；后续服务端 API 的实际完成情况见 [服务端验证记录](server-validation.md)。

## 当前任务进度

- P1、P2、D1、C1–C6 已完成。用户在播放手势、控件与暗黑模式调整后明确确认“目前大概差不多了。可以开始服务端了”，C6 的用户验收关口通过。
- [S1：认证、多目录扫描与视频列表](https://github.com/ShiJiJS/video_viewer/issues/11) 已实现并通过 API、实际 Compose、Windows 和模拟器认证网络验证；随后按依赖推进 S2–S6。
- I1–I6 负责把客户端接入真实 API 并在模拟器逐项联调；V1 负责最终 NAS 和真实 Android 设备验收。它们尚未开始。
- 快速整理仍是筛选、连续查看、打标签、删除与撤销；按标签一键调整物理目录继续留在后续事项，不增加归档分类。

## 已确认的环境

| 项目 | 实测结果 |
| --- | --- |
| WSL 发行版 | Ubuntu-24.04，WSL 版本 2，Ubuntu 24.04.5 LTS |
| Linux 内核 | 6.18.54.1-microsoft-standard-WSL2 |
| Docker Engine / CLI | 29.9.1，Linux amd64，默认 context |
| Docker Compose | v5.6.0 |
| Docker 服务 | systemd active、enabled；当前 WSL 用户可直接调用 |
| 存储 | overlayfs，cgroup v2，Docker 数据位于 `/var/lib/docker` |
| 项目挂载 | Windows `C:\Project\video_viewer` 对应 `/mnt/c/Project/video_viewer`，WSL 用户可读写 |
| 调试设备 | Android 16 / API 36 模拟器 `emulator-5554` |
| WSL 网络 | NAT；本轮无需新增端口转发或修改防火墙即可访问 |

Windows 的 `docker` 不在 PATH，使用 WSL 内已有 Docker 即可，不需要另外安装 Docker Desktop。VS Code 继续编辑现有 Windows 项目，PowerShell 中通过以下方式调用 Linux 工具：

```powershell
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker version
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker compose version
```

用户已确认服务端使用 Python / FastAPI / Uvicorn、SQLite / SQLAlchemy / Alembic、FFmpeg / ffprobe；后台任务状态持久化，使用受控的服务内执行器。技术与联调计划见 [服务端方案](server-plan.md)。S1 负责锁定依赖版本、建立镜像和正式 Compose 文件，并实现首批真实 API。WSL 中没有预装 FFmpeg，不影响当前环境检查；所需运行依赖随服务镜像配置。

## 容器、目录和连接实测

使用固定摘要的 BusyBox 镜像建立一次性 HTTP 容器。该镜像只是环境探针，不代表服务端语言或框架的选择。检查内容与结果见 [原始结果摘要](server-evidence/environment-2026-10-16.txt)。

1. `docker pull` 成功查询镜像仓库，`docker build` 成功生成本地测试镜像。
2. 非 root 容器读取只读的项目目录和独立测试媒体目录；实际写入测试媒体目录返回只读文件系统错误。
3. 数据写入 WSL 原生目录的 bind mount。删除并重建容器后，同一目录中的启动计数从 1 增加为 2，数据未丢失。
4. 容器将 8080 发布为 WSL 的 8760 端口。WSL 内 `curl`、Windows `Invoke-WebRequest`、模拟器中的 HTTP 请求均读取到相同探针标记与 `starts=2`。
5. 测试容器、专用镜像及 WSL 测试数据已清理，8760 不再由探针占用。没有修改已有 Docker 服务配置或其他项目容器。

| 调用位置 | 本次验证地址 | 结果 |
| --- | --- | --- |
| WSL | `http://127.0.0.1:8760/health.txt` | HTTP 200 |
| Windows | `http://127.0.0.1:8760/health.txt` | HTTP 200 |
| Android 模拟器 | `http://10.0.2.2:8760/health.txt` | HTTP 200 |

8760 是本轮验证端口，正式服务仍需在 S1 明确配置。模拟器中的 `127.0.0.1` 指向模拟器自身，连接本机服务使用上表中的 `10.0.2.2`。这次请求来自模拟器 shell；Flutter 网络提供方及 Android 应用网络配置仍需在 I1 实际验证。

## 后续开发约定与验证边界

源码保持在当前仓库，开发数据库、缓存和事务数据使用专属的 WSL 原生目录或 Docker volume。真实媒体通过显式配置的挂载目录接入；扫描和文件操作先使用隔离的测试素材，不对个人收藏运行删除或移动测试。

本轮没有测试真实视频探测、缩略图、数据库事务、授权播放、文件身份识别、回收站或备份恢复，也没有验证真实 NAS 挂载、ARM 镜像、手机或局域网性能。上述工作分别由 S1–S6、I1–I6 和 V1 完成，不能以本次 HTTP 环境探针替代。
