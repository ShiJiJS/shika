[项目首页](../README.md) · [文档导航](README.md) · **简体中文** · [English](deployment.en.md)

# 部署与日常使用

拾刻由 Android App 和一个 Docker 服务组成。服务运行在自己的 NAS 上，App 使用 NAS 局域网地址、端口和个人口令连接。下面以[现有 Compose 模板](../deploy/fnos/compose.yaml)为基础，从首次安装讲到备份和迁移；开发调试另见 [开发指南](development.md)。

## 部署前准备

- **NAS**：支持 Docker Engine 与 Compose v2，具有可持久化的本地存储。镜像架构必须匹配 `linux/amd64` 或 `linux/arm64`。
- **媒体**：准备实际的视频和图包目录。图包以文件夹为单位组织；视频播放依赖 Android 设备支持的编码，服务不实时转码。
- **网络**：手机能访问 NAS 的局域网地址。默认服务端口为 `8760`，模板绑定指定的 NAS 地址。
- **权限**：选定容器 UID/GID，默认 `1000:1000`；它需要读写管理数据、读取配置，并按需要获得媒体写权限。

本文的 `/srv/shika`、`/srv/media/videos`、`/srv/media/packs` 和 `192.168.1.100` 都是示例。飞牛通常使用 `/vol1/1000/...` 形式的实际路径；其他 NAS 使用其真实卷路径。个人口令及私人路径只放在本机配置中。

## 首次部署

已有实例升级或换 NAS 时，先看[备份、升级与迁移](#备份升级与迁移)，不要用示例覆盖已有口令或目录 ID。

### 1. 构建与 CPU 匹配的镜像

在有 Git 和 Docker 的主机上取得源码：

```bash
git clone https://github.com/ShiJiJS/shika.git
cd shika
```

如果直接在目标 NAS 上构建，镜像默认使用该主机架构：

```bash
docker build --target runtime -t shika-server:1.0.0 services/server
```

如果在另一台电脑构建并传到 NAS，显式指定架构。例如为 x86 NAS 导出：

```bash
mkdir -p tmp/releases
docker buildx build --platform linux/amd64 --target runtime \
  -t shika-server:1.0.0-amd64 \
  --output type=docker,dest=tmp/releases/server-amd64.tar services/server
```

ARM NAS 将平台改为 `linux/arm64`，并对应修改标签和归档文件名。在 NAS 导入归档后，查询镜像确认架构；有 Docker CLI 时可使用：

```bash
docker load -i /path/to/server-amd64.tar
docker image inspect shika-server:1.0.0-amd64 --format '{{.Os}}/{{.Architecture}}'
```

随后将环境文件的 `SHIKA_IMAGE` 设置成**实际构建或导入的标签**。模板中的默认标签不代表镜像已经发布到公共镜像仓库。飞牛也可通过 Docker 界面或已授权的 CLI 导入，见下文。

### 2. 准备持久化目录

在 NAS 上创建下面的结构，可使用文件管理器；下面的 Bash 示例仅用于首次部署，路径需要替换为自己的位置：

```text
shika/
├── compose.yaml
├── .env
├── data/                 # SQLite、任务、缓存、导出与恢复前快照
└── config/
    └── mounts.json       # 允许访问的容器内媒体范围
```

模板从源码目录复制，已有文件不覆盖：

```bash
mkdir -p /srv/shika/data /srv/shika/config
cp -n deploy/fnos/compose.yaml /srv/shika/compose.yaml
cp -n deploy/fnos/.env.example /srv/shika/.env
cp -n deploy/fnos/mounts.json.example /srv/shika/config/mounts.json
```

`data/` 使用支持 SQLite WAL 的 NAS 本地文件系统，不放在电脑挂载的 SMB/NFS 客户端目录中。不要递归修改整个媒体收藏的所有者；只给服务所需的目录授权。

### 3. 设置路径

编辑 NAS 应用目录中的 `.env`。在 NAS 原生构建镜像时，例如：

```dotenv
SHIKA_IMAGE=shika-server:1.0.0
SHIKA_BIND_ADDRESS=192.168.1.100
SHIKA_PORT=8760
SHIKA_UID=1000
SHIKA_GID=1000
SHIKA_DEPLOY_DIR=/srv/shika
SHIKA_VIDEO_DIR=/srv/media/videos
SHIKA_PACK_DIR=/srv/media/packs
```

跨架构导入示例则使用 `SHIKA_IMAGE=shika-server:1.0.0-amd64`。两个媒体源目录必须已经存在。配置与容器实际挂载的对应关系是：

| NAS 路径或设置 | 容器内位置 / 用途 |
| --- | --- |
| `SHIKA_DEPLOY_DIR/data` | `/data`，完整持久化的管理数据 |
| `SHIKA_DEPLOY_DIR/config` | `/config`，只读配置 |
| `SHIKA_VIDEO_DIR` | `/media`，允许接入的视频范围 |
| `SHIKA_PACK_DIR` | `/packs-cos`，允许接入的图包范围 |
| `SHIKA_BIND_ADDRESS`、`SHIKA_PORT` | 手机访问的 NAS 局域网地址与端口 |
| `SHIKA_UID`、`SHIKA_GID` | 服务读取文件和写入管理数据的身份 |

新安装无需创建口令文件。首次连接时在 App 设置口令，服务仅在 `data/` 数据库保存 Argon2 哈希。已有部署保留原口令文件及其挂载，升级不会要求重新初始化，也不会因重启撤销在 App 修改的口令。

`config/mounts.json` 可以使用复制的示例：

```json
[
  {"id": "main", "name": "视频", "path": "/media"},
  {"id": "cos-packs", "name": "图包", "path": "/packs-cos"}
]
```

这是**允许访问的范围**，不是所有媒体目录的清单。App 可以在范围内接入多个目录，选择视频或图包类型。新增其他媒体范围时，同时增加 Compose 的 bind mount 和这里的配置。服务不访问未挂载路径，也不跟随符号链接。

模板中的媒体挂载可写，以支持永久删除；移入回收站和普通恢复只改变管理记录。只读媒体挂载也能浏览和标记，但无法执行需要写文件的操作。保留模板的只读根文件系统、capabilities 移除和 `no-new-privileges`，不挂载 Docker socket。

### 4. 启动与检查

在 NAS 应用目录运行；示例健康检查地址需要与 `.env` 的地址、端口一致：

```bash
cd /srv/shika
docker compose --env-file .env -f compose.yaml config --quiet
docker compose --env-file .env -f compose.yaml up -d --no-build --wait --wait-timeout 120
docker compose ps
curl --fail http://192.168.1.100:8760/health
```

健康检查返回 `{"status":"ok","api_version":1}` 后，继续在 App 中登录并检查媒体目录。健康状态表示进程可响应，不等于所有媒体已扫描完成。保持一个服务进程，不增加 Uvicorn worker。

## 飞牛 fnOS 部署

应用目录可以放在 `/vol1/1000/docker/shika`；媒体必须使用当前实际位置。把准备好的 `compose.yaml`、`.env`、配置放在该目录，**先导入架构匹配的镜像**，再通过 Docker 管理界面选择已有 Compose 文件创建项目并启动。已有项目更新时重建原项目，不重复创建。

也可使用已授权的 `fnos-cli`。下面的 profile、路径和标签是命令格式示例；使用前确认对应设备和授权，上传镜像与配置后执行：

```bash
fnos-cli --profile home-fnos --allow-insecure-http docker image ls
fnos-cli --profile home-fnos --allow-insecure-http docker container ls --all
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.imageLoad --json '{"filePath":"/vol1/1000/docker/shika/image-archives/server-amd64.tar"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker image inspect shika-server:1.0.0-amd64
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeCreate --json '{"auto_build":false,"file":"compose.yaml","folder":"/vol1/1000/docker/shika","project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeBuild --json '{"project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker container inspect shika-server
```

`--allow-insecure-http` 仅在已保存的连接采用局域网 HTTP 时需要；HTTPS 配置使用对应连接选项。命令超时后先查询实际镜像、项目或容器状态，再决定下一步，不重复导入或创建。部署不要求额外开启 SSH。

## 安装与连接 App

使用维护者提供的 APK，或按[客户端开发说明](development.md)配置 Flutter / Android 后自行构建。以下在 `apps/mobile` 中执行：

```bash
flutter build apk --release \
  --target-platform android-arm64 --dart-define=LIBRARY_MODE=server
```

产物位于 `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`。首次安装使用自己的构建签名或提供安装包的签名；以后覆盖升级必须沿用同一签名。版本以 [pubspec.yaml](../apps/mobile/pubspec.yaml) 为准。

打开 App，填写：

| 项目 | 示例 |
| --- | --- |
| 服务器地址 | `192.168.1.100` |
| 端口 | `8760` |
| 个人口令 | 新服务首次连接时设置；已有服务使用原口令 |

手机需能访问这个 NAS 地址。`10.0.2.2:8760` 仅供 Android 模拟器访问本机开发服务，不能用于真机连接 NAS。App 登录后保存访问凭据，不保存个人口令。

在设置中接入媒体目录，选择视频或图包类型，检查启用状态和扫描进度。允许范围、实际接入目录和 Docker 挂载需要对应。

### 修改与找回口令

新服务：输入 NAS IP 和端口，点“连接”后出现首次设置提示。填写两次 **8–1024 个字符**的个人口令，点“设置口令并连接”。首次设置前只允许自己的可信局域网访问服务。

已有服务：继续使用原口令。修改入口为 **设置 → 修改个人口令**，需要当前口令并确认两次新口令。成功后本机自动保存新的登录凭据，所有旧凭据立即失效，其他设备需重新连接。App 保存访问凭据，不保存明文个人口令；口令不进入管理备份。

忘记口令时，由 NAS 管理员新建或修改一个 `secrets/passphrase` 文件，写入与原种子不同的新口令（8–1024 个字符），限制文件读取权限并允许容器 UID 读取。在 Compose 增加只读 bind mount，将该文件挂到 `/run/secrets/passphrase`（或用 `VV_PASSPHRASE_FILE` 指定容器内位置），重建原容器。服务检测到文件值变化后重置口令并使旧登录失效，之后用新口令连接。不要删除数据库来重置口令。未变化的旧种子文件不会覆盖 App 后来设置的新口令。

## 日常使用

- **媒体库与标签**：视频和图包分别查询、筛选和管理标签，选择内容后进入播放或阅读；返回保留原来源，空结果不会自动扩大到全库。
- **图包阅读**：默认纵向拼接，支持横向翻页、缩放、总览和续读；已保存偏好继续生效。
- **快速整理**：在选定范围连续查看，快捷移入回收站并撤销；媒体库支持多选整理。
- **扫描**：复制完成后可手动扫描，也可等待定时扫描。各目录进度由服务端同步，关闭 App 不会中断后台任务。模板默认扫描间隔为900秒。
- **回收站**：移入回收站保留源文件。永久删除才会移除对应媒体；图包按所选文件夹及其中内容在服务端后台删除。查看任务结果了解失败项。
- **缩略图缓存**：服务启动及扫描结束后检查是否需要回收，空闲时每小时检查一次。无引用或仅由已永久删除记录引用、且最后修改与创建/属性变更均超过一小时的缩略图会分批清理。现用、回收站、缺失及未发布扫描记录引用的缓存继续保留；源媒体和管理备份不参与清理。清理与缩略图生成串行，管理恢复期间暂停，结果写入服务日志。

## 备份、升级与迁移

### 管理备份与媒体备份

在 App 设置 → 备份与恢复创建管理备份，并通过手机系统文件选择器保存到 App 外。完整备份包含视频与图包身份、标签、目录、阅读位置、偏好和历史；**不包含源视频、图片、缓存、个人口令或 App 外观设置**。源媒体及旧物理回收文件需要独立的 NAS 备份。

完整备份使用 v2 NDJSON，旧 v1 文件仍可校验转换。CLI 的旧视频备份不能当作包含图包的完整备份。文件上限由服务能力公布，具体规则见[服务端说明](../services/server/README.md#完整备份与兼容)。

恢复时选择备份文件，校验并核对目录映射，再确认替换。服务会保存恢复前快照。恢复不会重放历史删除，也不能找回已永久删除的媒体。断线后查询原任务，避免重复提交。

### 升级与回退

1. 先导出管理备份，保存当前 Compose、环境配置和镜像信息。
2. 需要完整实例回退时，停止服务后备份完整 `data/`、`config/`，安全保留口令和原镜像；不要在运行中只复制 SQLite 主文件而漏掉 WAL。
3. 构建或导入新镜像，修改 `SHIKA_IMAGE`，重建**原** Compose 项目，保留 bind mount。
4. 检查容器健康、App 登录、目录状态与任务结果。App 更新保持签名一致并覆盖安装。

回退旧服务须配对恢复兼容的原镜像与停机快照，旧镜像不保证能读取新数据库。在 App 修改个人口令无需重建容器，其他设备使用新口令重新登录。

### 换 NAS 或移动存储

- 保留完整管理数据、口令、稳定目录 ID，以及容器内的 `/media`、`/packs-cos` 等路径；只调整外部 bind mount 的源路径。
- 为新 NAS 重新构建或导入匹配 CPU 的镜像，不把 ARM 镜像改标签当作 x86 镜像。
- 同一份管理数据只由一个服务实例访问。确认新服务可用后再处理原部署；不要同时启动两份服务写同一数据库。
- 迁移改变文件身份信息后，服务会重新核对媒体；尚未核对的内容需等待对应目录扫描。
- 旧 `.video-viewer-trash`、`.video-viewer-tmp` 或自定义回收卷可能承载旧物理回收记录，不随产品改名清除或重命名。

## 常见问题

| 现象 | 检查 |
| --- | --- |
| 手机连接失败 | NAS IP、端口、防火墙、手机网络和容器健康状态 |
| 401 / 需要重新连接 | 口令是否变更、凭据是否过期；重新输入口令 |
| 看不到新增内容 | bind mount、允许范围、接入目录类型/启用状态、复制完成情况与扫描任务 |
| 迁移后图片暂时不能打开 | 对应图包目录的重新核对进度；保留原目录 ID 和容器内路径 |
| 删除失败 | 目录写权限、剩余空间、路径变化或外部替换、原任务失败结果 |
| 视频不能播放 | 手机支持的编码、音频与分辨率；服务不实时转码 |
| 扫描或切换慢 | 网络、NAS 负载及相邻视频准备设置；按测量调整资源 |
| 备份无法导入 | 格式、版本、完整性、服务公布的大小限制与原任务结果 |

仍未解决时，在 [GitHub Issues](https://github.com/ShiJiJS/shika/issues) 附上复现步骤、App 版本、手机型号及部署方式。更多开发与接口说明从[文档导航](README.md)进入。
