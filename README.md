# Video Viewer

部署在 NAS 上的私人短视频库，配套 Android 优先的跨平台 App，用于随机浏览、标签筛选与快速整理。

P2 HTML 原型与 [Flutter Android 客户端演示版](apps/mobile/README.md) 已获用户确认，客户端沿用 B 风格。S1–S3 服务端认证、扫描、列表、授权播放、轮次及标签管理已在 WSL2 Docker 实现并验证；后续服务端和 Flutter 真实联调继续推进，当前 App 仍使用演示数据。具体完成项与证据见 [服务端验证记录](docs/server-validation.md)。

服务端技术栈已确认：Python / FastAPI / Uvicorn、SQLite / SQLAlchemy / Alembic、FFmpeg / ffprobe；通过 Docker Compose 单服务、单端口部署。按 S1–S6 实现服务端，再按 I1–I6 接入 Flutter 并在模拟器联调，最后进行 NAS 验收。NAS 资源与预加载的评估范围见 [服务端方案](docs/server-plan.md)。

## 第一版范围

- NAS Docker 服务，个人局域网使用。
- 多媒体目录接入，保留原有目录结构，接受外部文件变化。
- 随机 / 顺序播放和缩略图列表，支持挂载目录层级选择、横竖屏、倍速与拖进度。
- 平铺多标签、批量打标和标签交集筛选。
- 快速整理模式：限定范围后连续查看、打标签、移入回收站与撤销；回收站支持恢复和确认后永久删除。
- 管理数据持久化、备份与恢复。

按标签一键调整文件夹留待后续，规则未定，不设独立归档分类。图包、AI 打标、外网、多用户及离线缓存也不进入第一版。

## 项目文档

- [Flutter 客户端演示：运行、试用与复位](apps/mobile/README.md)
- [客户端数据接口与阶段边界](docs/client-data-contract.md)
- [客户端验证和模拟器画面](docs/client-validation.md)

- [P2 HTML 原型：启动、试用路径与验证记录](prototypes/p2/README.md)
- [当前 UI 设计基线](prototypes/p2/DESIGN.md)
- [Android 开发环境、模拟器和 VS Code 使用](docs/android-development.md)
- [服务端开发环境：WSL2、Docker 与模拟器连接](docs/server-development.md)
- [服务端技术方案、联调计划与 NAS 资源约束](docs/server-plan.md)
- [服务端运行、配置与 API](services/server/README.md)
- [服务端完成项、格式样本和验证证据](docs/server-validation.md)
- [第一版规格 Issue #1](https://github.com/ShiJiJS/video_viewer/issues/1)（ready-for-agent）
- [第一版完整规格](docs/v1-spec.md)
- [已确认需求与验收场景](docs/requirements.md)
- [领域术语](GLOSSARY.md)
- [后续事项：目录整理、AI 打标与 NAS 预加载优化](docs/backlog.md)

## 验证方向

在 VS Code 打开仓库根目录，选择 **Video Viewer (Android)** 并按 **F5**。启动前任务会准备模拟器，随后启动 Flutter 调试。具体配置和命令见 Android 开发文档。

在模拟器中验收完整 App 流程；服务端公开 API 集成测试补充验证文件操作及异常恢复。NAS 和真实 Android 设备在后续验证实际媒体兼容性与性能。

仓库保存源码、文档及注明来源的公开演示素材，不保存个人视频、运行数据、备份或访问凭据。
