# 部署与日常使用

拾刻使用一个 Docker 服务和一个 Android App。部署使用 [飞牛 Compose 模板](../deploy/fnos/compose.yaml)及[环境变量示例](../deploy/fnos/.env.example)；镜像版本以模板为准，App 版本以 [pubspec.yaml](../apps/mobile/pubspec.yaml) 为准。真实地址、口令和路径保存在私有 infos 的 `shika.connection`，不提交到仓库。

## 配置目录与权限

将模板和环境文件放到 NAS 的应用目录（例如 `/vol1/1000/docker/shika`），根据实际存储位置修改环境变量：

| 配置 | 用途 |
| --- | --- |
| `SHIKA_DEPLOY_DIR` | 应用目录，包含 `data/`、`config/`、`secrets/` |
| `SHIKA_VIDEO_DIR` | 视频目录，挂载到容器 `/media` |
| `SHIKA_PACK_DIR` | 图包目录，挂载到容器 `/packs-cos` |
| `SHIKA_BIND_ADDRESS`、`SHIKA_PORT` | NAS 局域网地址与服务端口，默认端口8760 |
| `SHIKA_UID`、`SHIKA_GID` | 服务运行身份，须能读写管理数据和获授权的媒体目录 |
| `SHIKA_IMAGE` | 已导入且架构匹配的服务镜像 |

`data/` 必须完整持久化，保存 SQLite、缓存、任务、导出及恢复前快照。使用支持 SQLite WAL 的 NAS 本地文件系统。容器保留只读根文件系统、丢弃 capabilities 和 `no-new-privileges`；不要挂载 Docker socket。

在 `secrets/passphrase` 安全保存至少8字符的个人口令；已有文件沿用原值。限制文件读取权限，并确保容器 UID 能读取。修改口令后重建容器，旧登录凭据失效，App 需要重新登录。

`config/mounts.json` 声明容器内允许接入的目录，例如：

```json
[
  {"id": "videos", "name": "视频", "path": "/media"},
  {"id": "packs", "name": "图包", "path": "/packs-cos"}
]
```

已有实例沿用原配置及稳定目录 ID，不重新生成。允许范围不是完整媒体目录清单；App 在其中接入目录并选择视频或图包类型。服务不访问未挂载路径，也不跟随符号链接。存储位置改变时修改对应 bind mount，保留原容器内路径和完整管理数据。

移入回收站只记录标记，不修改媒体文件；永久删除及旧版物理回收记录的恢复需要相应目录写权限。旧 `.video-viewer-trash`、`.video-viewer-tmp` 或独立回收卷仍可能包含待恢复文件，不手动清除或重命名。

## 构建与启动

先确认 NAS 的 CPU 架构。以下在仓库根目录导出 x86 NAS 镜像；ARM NAS 将平台改为 `linux/arm64`，并使用独立镜像标签：

```bash
mkdir -p tmp/releases
docker buildx build --platform linux/amd64 --target runtime \
  -t shika-server:local-amd64 \
  --output type=docker,dest=tmp/releases/server-amd64.tar services/server
```

飞牛通过已授权的 `fnos-cli` 上传归档和配置。以下为命令格式示例，路径和 profile 必须对应实际设备；先导入并查询镜像，再创建尚不存在的 Compose 项目：

```bash
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.imageLoad --json '{"filePath":"/vol1/1000/docker/shika/image-archives/server-amd64.tar"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker image inspect shika-server:local-amd64
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeCreate --json '{"auto_build":false,"file":"compose.yaml","folder":"/vol1/1000/docker/shika","project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeBuild --json '{"project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker container inspect shika-server
```

使用示例镜像时将环境文件的 `SHIKA_IMAGE` 设为 `shika-server:local-amd64`。命令超时后先查询实际镜像或容器状态，不重复创建或导入。已有项目直接更新其配置并重建，不再调用创建。具有 Docker CLI 的主机可在部署目录运行 `docker compose up -d --wait`；只运行一个服务进程。

只读检查可在本机运行 `python3 scripts/nas-status.py`，通过 infos 选择飞牛连接；旧 SSH 配置仍兼容。不要把凭据写入 Compose、日志或仓库。

## 安装与使用

手机安装使用原签名构建的 APK，填写 NAS 局域网 IP、端口和个人口令。`10.0.2.2:8760` 仅供 Android 模拟器连接本机开发服务。覆盖安装保留 App 数据；不要卸载来代替升级。构建与 VS Code 调试见 [Mac 开发](macos-development.md) 和 [Android 开发](android-development.md)。

- 在媒体库选择视频或图包，按目录、独立标签和搜索条件查找，再进入播放或阅读。返回保留原来源；空结果不扩大到全库。
- 图包默认纵向拼接，支持横向翻页、缩放、总览和续读；已保存偏好继续生效。快速整理及媒体库多选可移入回收站，短提示提供撤销。
- 设置中管理媒体目录、各目录扫描进度、默认值、外观、操作任务、回收站和备份。把媒体复制完成后可手动扫描，也可等待定时扫描；关闭 App 不会中断后台任务。
- 回收站支持多选恢复和永久删除。图包永久删除以所选图包目录为单位在服务端后台处理；查看任务结果了解失败项。管理备份不能找回已永久删除的媒体。

## 备份、升级与回退

设置 → 备份与恢复，创建管理备份后通过手机系统文件选择器保存到 App 外。完整备份包含视频与图包的管理数据、标签、阅读位置、偏好和历史，不包含原媒体、缓存、口令或 App 外观设置。新服务使用 v2 NDJSON，旧 v1 文件仍可校验转换；演示/HTML 原型格式不能混用。文件上限由服务能力公布，配置见 [服务端说明](../services/server/README.md#完整备份与兼容)。

恢复先选择文件、校验并核对目录映射，再明确确认替换；服务自动建立恢复前快照。断线后查询原任务，不重复提交恢复。恢复不会重放历史删除，也不能还原真实媒体文件，媒体及旧物理回收文件须另做 NAS 备份。

更新前保存管理备份。需要完整实例回退时，停止服务后备份整个 `data/`、`config/` 并安全保留口令和原镜像；不能在运行中只复制 SQLite 主文件而漏掉 WAL。重建容器保留 bind mount。旧镜像不保证能打开新数据库，回退须配对还原原镜像与停机快照。

## 排查

| 现象 | 检查 |
| --- | --- |
| 手机连接失败 | NAS IP、端口、防火墙、容器健康状态；手机不能使用模拟器地址 |
| 401 / 需要重连 | 重新输入口令，检查口令是否变更或凭据已过期 |
| 看不到新增内容 | bind mount、允许范围、接入目录类型/启用状态、复制完成情况、扫描任务 |
| 删除失败 | 目录写权限、剩余空间、外部替换或路径变化、原任务的失败结果 |
| 视频无法播放 | 手机实际支持的编码、音频和分辨率；服务不实时转码 |
| 扫描或切换慢 | 网络及 NAS 负载，尝试关闭相邻视频准备；按实际测量调整资源 |
| 备份不能导入 | 格式、版本、完整性与服务公布的大小限制；检查原任务结果 |

未解决问题和目标设备验收在 [GitHub issues](https://github.com/ShiJiJS/shika/issues) 更新；完整原型验收见 [#133](https://github.com/ShiJiJS/shika/issues/133)。
