<div align="center">

**简体中文** · [English](README.en.md)

<img src="assets/branding/shika-icon.png" width="200" alt="拾刻 · shika 图标">

<h1>拾刻 · shika</h1>
<p><strong>边看边整理的私人媒体库</strong></p>

![Android](https://img.shields.io/badge/App-Android-3DDC84?logo=android&logoColor=white)
![Docker](https://img.shields.io/badge/Server-Docker-2496ED?logo=docker&logoColor=white)
![Status](https://img.shields.io/badge/Status-开发预览-526B52)

[开始使用](#开始使用) · [部署手册](docs/deployment.md) · [文档导航](docs/README.md) · [反馈问题](https://github.com/ShiJiJS/shika/issues)

</div>

---

## 软件介绍

拾刻是一个面向 NAS 收藏的媒体浏览与整理工具，由 **Android App** 和部署在自己 NAS 上的 **Docker 服务**组成。把视频和图包接入媒体库，按目录、标签或关键词挑选内容，再进入播放或阅读；在连续浏览的同时，留下喜欢的内容、补充标签、移入回收站。

图包以**文件夹为单位**组织，提供类似漫画阅读的纵向拼接、横向翻页、缩放和续读。视频与图包各自管理标签和最近记录，适合一边看、一边整理自己的收藏。

当前为开发预览，App 界面为简体中文。中文和英文 README、部署手册分别维护，语言入口位于每页顶部。

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

1. **部署服务端**：准备 NAS 媒体目录，按[部署手册](docs/deployment.md)构建镜像、配置持久化目录并启动 Docker 服务。
2. **安装 Android App**：使用维护者提供的 APK，或按[客户端开发说明](docs/development.md)从源码构建。升级时保持相同签名并覆盖安装。
3. **连接媒体库**：填写 NAS 局域网 IP、端口（默认 `8760`）和自己设置的个人口令，在 App 中接入视频或图包目录。
4. **浏览与整理**：查看扫描进度，在媒体库或标签中选择内容，再进入播放、阅读或快速整理。

服务端支持为 `linux/amd64` 或 `linux/arm64` 构建镜像，需与 NAS 的 CPU 架构匹配。视频直接从 NAS 读取，不实时转码，播放能力取决于 Android 设备支持的格式。

## 部署与维护

[部署手册](docs/deployment.md)包含首次安装、镜像构建、目录权限、视频与图包挂载、飞牛部署、App 连接、备份、升级、迁移和常见问题。

- 服务模板：[Compose](deploy/fnos/compose.yaml) · [环境变量](deploy/fnos/.env.example) · [允许访问的媒体范围](deploy/fnos/mounts.json.example)
- 数据位置：数据库与管理记录保存在持久化的 `data/`，配置在 `config/`，个人口令在 `secrets/`。
- 已有媒体库：迁移或升级时保留完整管理数据、原目录 ID 和容器内挂载路径，继续使用已有标签和阅读记录。

## 文档与开发

| 文档 | 内容 |
| --- | --- |
| [文档导航](docs/README.md) | 根据安装、使用、维护或开发任务选择入口 |
| [部署手册](docs/deployment.md) | NAS 首次部署、App 连接和日常维护 |
| [开发指南](docs/development.md) | Flutter、VS Code、本地服务、APK 构建与测试 |
| [服务端说明](services/server/README.md) | 配置、接口、扫描、文件操作与备份规则 |
| [命令行客户端](apps/cli/README.md) | 登录、扫描、视频查询和视频标签自动化 |

客户端在 `apps/mobile`，服务端在 `services/server`，CLI 在 `apps/cli`。App 版本以 [pubspec.yaml](apps/mobile/pubspec.yaml) 为准，未完成工作与设备验收在 [GitHub Issues](https://github.com/ShiJiJS/shika/issues) 跟踪。

欢迎反馈问题，描述复现步骤，并注明 App 版本、手机型号及 NAS 部署方式。
