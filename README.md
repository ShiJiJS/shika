# Video Viewer

部署在 NAS 上的私人视频与图包媒体库，配套 Android App，用于按范围浏览、阅读、标签筛选与快速整理。

P2 HTML 原型与 [Flutter Android 客户端](apps/mobile/README.md) 沿用已确认的 B 风格。S1–S6 服务端与 I1–I6 真实服务联调已完成：认证、扫描、播放、轮次、标签、回收站、外部文件变化及备份恢复均有 WSL2 Docker 和 Android 模拟器证据。Flutter 默认连接真实服务，保留独立演示模式。V1 已部署极空间 ARM64 NAS，提供手机测试包与使用说明；首次建库、Find X8 体验及性能验收继续进行，见 [V1 状态](docs/v1-validation.md)。

服务端技术栈：Python / FastAPI / Uvicorn、SQLite / SQLAlchemy / Alembic、FFmpeg / ffprobe；通过 Docker Compose 单服务、单端口部署。NAS 资源与预加载的评估范围见 [服务端方案](docs/server-plan.md)。

## 当前可用版本

2026-11-02：按用户要求暂停后续开发，固定在下述第28版App与NAS preview.8；当前源码合并到主分支。已清理本机过程文件和旧产物，保留最新正常包、同号回退包和服务镜像，开发工具与原签名保留。

2026-11-01：**第28版 App（preview.22）与同号旧界面回退包已放入 NAS 原部署目录的 `packages/`**，服务已更新到 **preview.8**。直接覆盖安装正常包，不要卸载或清除数据；原地址、口令和签名保持。见[第28版安装说明](docs/nas-app-preview-2026-11-01-code28.md)和[NAS备份与更新记录](docs/nas-preview-2026-11-01-service8.md)。

视频与图包各有媒体库、标签和最近记录，从库或标签选定范围后进入播放/阅读。图包以文件夹为单位，支持横向翻页、默认纵向拼接与缩放、续读、打标签、快速移除和撤销。设置中提供目录独立扫描进度、回收站、操作任务和管理备份。当前NAS图包源目录只读，移入回收站不会移动原图。

主要功能已实现并交付试用，仍按[完整要求](docs/plans/library-first/ACCEPTANCE.md)验收。真实手机安装、声音/手势、系统和云文件选择及完整性能尚未全部确认，三个历史偶发问题仍开放；见[当前进度](docs/plans/library-first/PROGRESS-CURRENT.md)。参考原型独立存放、不随App发布、可单独移除。下列第一版范围保留为历史记录。

## 第一版范围

- NAS Docker 服务，个人局域网使用。
- 多媒体目录接入，保留原有目录结构，接受外部文件变化。
- 随机 / 顺序播放和缩略图列表，支持挂载目录层级选择、横竖屏、倍速与拖进度。
- 平铺多标签、批量打标和标签交集筛选。
- 快速整理模式：限定范围后连续查看、打标签、移入回收站与撤销；回收站支持恢复和确认后永久删除。
- 管理数据持久化、备份与恢复。
- 首次建库准备状态、自动扫描进度同步，以及滚动自动分页；建库完成后开放播放，日常增量扫描继续可看。

按标签一键调整文件夹留待后续，规则未定，不设独立归档分类。图包、AI 打标、外网、多用户及离线缓存也不进入第一版。

## 项目文档

- [媒体库与图包升级：整体审阅入口](docs/REVIEW-LIBRARY-FIRST.md)
- [可移除设计参考原型](design/reference/README.md)（不随 App 发布）
- [媒体库与图包升级规划：框架、实施任务与原型一致性验收](docs/plans/library-first/PLAN.md)（LF8 验收进行中）
- [当前版本、已交付功能与剩余事项](docs/plans/library-first/PROGRESS-CURRENT.md)
- [第28版安装与同号回退](docs/nas-app-preview-2026-11-01-code28.md)
- [媒体库预览包：安装、旧服务兼容与回退边界](docs/library-first-preview.md)

- [Mac 开发环境、VS Code F5、测试、打包与 NAS 维护](docs/macos-development.md)
- [部署、安装、日常使用与恢复手册](docs/deployment.md)
- [V1 本机交付、安装包校验与目标环境待验项](docs/v1-validation.md)
- [Flutter 客户端：真实服务、演示与开发](apps/mobile/README.md)
- [rv 命令行客户端：库维护与自动化流水线入口](apps/cli/README.md)
- [客户端数据接口与阶段边界](docs/client-data-contract.md)
- [客户端验证和模拟器画面](docs/client-validation.md)
- [Flutter 与真实服务联调、隔离测试实例](docs/integration-validation.md)

- [P2 HTML 原型：启动、试用路径与验证记录](prototypes/p2/README.md)
- [第一版 UI 设计基线](prototypes/p2/DESIGN.md)
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
