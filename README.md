<div align="center">

**简体中文** · [English](README.en.md)

<img src="assets/branding/shika-icon.png" width="200" alt="拾刻 · shika 图标">

<h1>拾刻 · shika</h1>
<p><strong>边看边整理的私人媒体库</strong></p>

![Android](https://img.shields.io/badge/App-Android-3DDC84?logo=android&logoColor=white)
![Docker](https://img.shields.io/badge/Server-Docker-2496ED?logo=docker&logoColor=white)
![Status](https://img.shields.io/badge/Version-1.0.1-526B52)

[开始使用](#开始使用) · [部署手册](docs/deployment.md) · [文档导航](docs/README.md) · [反馈问题](https://github.com/ShiJiJS/shika/issues)

</div>

---

## 软件介绍

拾刻是一个面向 NAS 收藏的媒体浏览与整理工具，由 **Android App** 和部署在自己 NAS 上的 **Docker 服务**组成。把视频和图包接入媒体库，按目录、标签或关键词挑选内容，再进入播放或阅读；在连续浏览的同时，留下喜欢的内容、补充标签、移入回收站。

图包以**文件夹为单位**组织，提供类似漫画阅读的纵向拼接、横向翻页、缩放和续读。视频与图包各自管理标签和最近记录，适合一边看、一边整理自己的收藏。

当前正式版为 **1.0.1**，App 界面为简体中文。中文和英文 README、部署手册分别维护，语言入口位于每页顶部。

## 主要功能

| 功能 | 可以做什么 |
| --- | --- |
| 媒体库 | 分别浏览视频与图包，按目录、关键词和各自的标签筛选 |
| 视频播放 | 从选定的浏览范围进入播放，连续切换内容，返回时保留来源 |
| 图包阅读 | 纵向拼接、横向翻页、缩放、图片总览，以及阅读位置与偏好保存 |
| 快速整理 | 在选定范围连续查看，快捷移入回收站并撤销；媒体库支持多选整理 |
| 独立标签 | 视频和图包各有一套标签，为图包添加标签时以图包为单位 |
| 扫描与维护 | 管理媒体目录，查看各目录扫描进度、操作任务、缺失内容和回收站 |
| 管理备份 | 备份和恢复标签、目录、阅读进度、偏好等管理记录 |

移入回收站保留源文件；永久删除才会删除对应媒体，图包按所选文件夹删除。管理备份不包含原视频或图片，源媒体需要另外备份。

## 开始使用

1. **准备 Docker 与目录**：NAS 需要 Docker，准备视频、图包目录，以及保存数据库的本地 `data/`。按[部署手册](docs/deployment.md#首次部署)构建与 NAS CPU 匹配的 `shika-server:1.0.1` 镜像。
2. **配置并启动服务**：复制 `deploy/fnos/` 的 Compose、`.env.example` 和 `mounts.json.example`，填写实际 NAS IP、媒体路径、UID/GID。启动 Compose，访问 `http://NAS地址:8760/health`，应返回 `status: ok`。完整命令和挂载示例见[部署手册](docs/deployment.md)。
3. **安装 App**：从 [1.0.1 正式版](https://github.com/ShiJiJS/shika/releases/tag/v1.0.1)下载并安装 `shika-1.0.1-arm64.apk`，也可按[开发指南](docs/development.md)从源码构建。更新时覆盖安装并保持相同签名。
4. **首次连接并设置口令**：手机与 NAS 网络互通，在 App 输入 NAS IP 和端口 `8760`，点“连接”。新服务会显示“首次连接 · 设置个人口令”，输入两次至少 8 个字符的口令，点“设置口令并连接”。已有服务直接使用原口令登录。
5. **接入媒体目录**：在设置中添加视频或图包目录，使用容器内路径，例如 `/media`、`/packs-cos`；检查各目录扫描进度，完成后从媒体库浏览。

后续修改口令：**设置 → 修改个人口令**，填写当前口令和两次新口令。保存后本机继续连接，其他设备需重新登录，无需重建容器。App 自动管理登录凭据，不需要手动填写会话 token。初次设置前请仅开放给自己可信的局域网；忘记口令时按[口令恢复说明](docs/deployment.md#修改与找回口令)操作。

服务端支持为 `linux/amd64` 或 `linux/arm64` 构建镜像，需与 NAS 的 CPU 架构匹配。视频直接从 NAS 读取，不实时转码，播放能力取决于 Android 设备支持的格式。

## 部署与维护

[部署手册](docs/deployment.md)包含首次安装、镜像构建、目录权限、视频与图包挂载、飞牛部署、App 连接、备份、升级、迁移和常见问题。

- 服务模板：[Compose](deploy/fnos/compose.yaml) · [环境变量](deploy/fnos/.env.example) · [允许访问的媒体范围](deploy/fnos/mounts.json.example)
- 数据位置：数据库与管理记录保存在持久化的 `data/`，配置在 `config/`。App 设置的口令只在数据库保存哈希；旧版可继续挂载 `secrets/passphrase`。
- 已有媒体库：迁移或升级时保留完整管理数据、原目录 ID 和容器内挂载路径，继续使用已有标签和阅读记录。

## 选装：视频打标 Skill 与 CLI

[video-tagging Skill](skills/video-tagging/SKILL.md) 可抽帧识别视频、生成中文标签文件，并按要求同步到拾刻。[shika CLI](apps/cli/README.md) 提供视频查询和标签批量操作。两者是选装工具，普通 App 与 NAS 服务无需安装。

在源码仓库中可一次配置 Skill 和隔离的 CLI（Python 3.10+，Skillshare 已配置）：

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
```

其他助手的安装方式、模型依赖与使用流程见[视频打标指南](docs/video-tagging.md)。

## 文档与开发

| 文档 | 内容 |
| --- | --- |
| [文档导航](docs/README.md) | 根据安装、使用、维护或开发任务选择入口 |
| [部署手册](docs/deployment.md) | NAS 首次部署、App 连接和日常维护 |
| [开发指南](docs/development.md) | Flutter、VS Code、本地服务、APK 构建与测试 |
| [服务端说明](services/server/README.md) | 配置、接口、扫描、文件操作与备份规则 |
| [命令行客户端](apps/cli/README.md) | 登录、扫描、视频查询和视频标签自动化 |
| [视频打标 Skill（选装）](docs/video-tagging.md) | Skill 与 CLI 安装、生成标签文件和同步 |

客户端在 `apps/mobile`，服务端在 `services/server`，CLI 在 `apps/cli`。App 版本以 [pubspec.yaml](apps/mobile/pubspec.yaml) 为准，未完成工作与设备验收在 [GitHub Issues](https://github.com/ShiJiJS/shika/issues) 跟踪。

欢迎反馈问题，描述复现步骤，并注明 App 版本、手机型号及 NAS 部署方式。
