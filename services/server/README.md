[项目首页](../../README.md) · [文档导航](../../docs/README.md) · [部署手册](../../docs/deployment.md)

# 拾刻 · shika 服务端

FastAPI 服务为视频和图包提供扫描、查询、授权媒体读取、独立标签、固定浏览范围、回收站及管理备份。App 从媒体库选择内容后进入播放或阅读。

NAS 使用 [飞牛部署模板](../../deploy/fnos/compose.yaml)，安装、权限、日常维护和回退见 [部署说明](../../docs/deployment.md)。App 版本见 [pubspec.yaml](../../apps/mobile/pubspec.yaml)，部署镜像见 Compose 环境配置；本文不维护另一份“当前交付版本”。

## 本机开发

工具链与客户端调试见 [开发指南](../../docs/development.md)。在仓库根目录运行（Windows 使用 WSL2）：

```bash
bash scripts/prepare-server-dev.sh
docker compose --env-file .env -f deploy/local/compose.yaml up -d --build --wait --wait-timeout 120
docker compose --env-file .env -f deploy/local/compose.yaml ps
```

准备脚本只在文件不存在时创建口令、配置和被 Git 忽略的 `.env`，保留已有值。可通过 `VV_SERVER_DEV_HOME` 指定本地数据目录，默认 `~/.local/share/video-viewer-dev/`。测试和联调只使用独立的可丢弃媒体。

本机健康检查地址为 `http://127.0.0.1:8760/health`，Android 模拟器访问宿主机使用 `10.0.2.2:8760`。服务默认启动扫描，定时扫描间隔、稳定观察时间、媒体读取并发和备份大小上限由 Compose 环境配置控制；飞牛模板与本地开发模板可以采用不同值。

## 配置与接口

`config/mounts.json` 声明容器内允许访问的媒体范围。保留已有挂载 ID，App 在允许范围内添加或编辑视频/图包目录；未挂载的 NAS 路径不会自动变得可访问。图包目录需在 NAS Compose 中额外挂载，具体见部署模板。服务不跟随符号链接。

图包根目录下的每个一级子文件夹作为一个图包，其子目录中的图片会加入同一个图包；直接位于根目录的零散图片不会组成图包。推荐目录树、分类层级和支持格式见[媒体目录格式](../../docs/media-layout.md)。

完整请求参数、分页上限与返回类型以运行实例的 `/openapi.json`（或 `/docs`）为准；`GET /api/v1/info` 返回实例身份、当前 schema、能力和备份限制。客户端按能力决定入口，不能只按版本号猜测功能。业务接口和媒体读取需要登录返回的 Bearer token，缩略图也需要授权。

| 功能 | 主要入口 |
| --- | --- |
| 登录与退出 | `/api/v1/auth/login`、`/api/v1/auth/session` |
| 允许范围、接入目录与目录树 | `/api/v1/mounts`、`/api/v1/roots`、`/api/v1/directories` |
| 扫描与状态 | `/api/v1/scans`、`/api/v1/library-state`、`/api/v1/tasks` |
| 视频目录与标签 | `/api/v1/videos`、`/api/v1/tags`、`/api/v1/video-tags` |
| 视频固定浏览范围 | `/api/v1/rounds`、`/api/v1/playback` |
| 图包、标签与阅读 | `/api/v1/packs`、`/api/v1/pack-tags`、`/api/v1/pack-sessions` |
| 视频回收与文件任务 | `/api/v1/trash`、`/api/v1/operations/{id}` |
| 图包回收与文件任务 | `/api/v1/pack-trash`、`/api/v1/pack-operations/{id}` |
| 完整管理备份与恢复 | `/api/v1/management-backups` |

## 扫描与浏览

媒体库查询、两类标签和最近记录分开处理。查询列表不会创建播放/阅读范围；只有明确进入内容时才开始对应会话。已创建范围的成员保持固定，新增内容留到下一次主动创建范围。

设置中的目录进度来自服务端扫描任务，可查看各接入目录的状态。指定目录扫描需要实例支持对应能力；失败不能擅自改成全库扫描。首次建库、增量扫描及目录暂时离线按实际阶段显示，已发布内容可继续查询。

外部改名或移动有充分身份依据时保留原 ID、标签和阅读数据；同路径替换或身份不唯一时不猜测继承。目录不可用、扫描失败或未完整遍历时不据此清理旧记录。缩略图是可重建缓存，生成失败与原媒体损坏分开反馈。

## 个人口令

`GET /api/v1/auth/status` 返回是否已初始化。新数据库未挂载种子口令时，App 通过 `POST /api/v1/auth/setup` 设置口令（8–1024 字符），仅首次成功；已有实例使用 `POST /api/v1/auth/login`。已登录设备通过 `POST /api/v1/auth/passphrase` 提交 `current_passphrase` 和 `new_passphrase`，收到替代访问凭据，全部旧会话失效。接口返回相同的登录凭据结构，`credential_management` 能力用于 App 展示入口。

数据库保存 Argon2 哈希。可选的 `VV_PASSPHRASE_FILE` 兼容原部署并提供管理员恢复入口；未变化的种子不会撤销 App 修改，主动改变种子后重启会重置口令并撤销旧凭据。恢复步骤见部署手册。管理备份不导出口令或其种子哈希。

图片不按原始像素数量拒绝收录。扫描先发布格式、尺寸等元数据，再在子进程生成缩略图；JPEG 尽量缩小解码。8000 万工作像素预算只用于预览生成，超过预算、内存不足或处理超时会保留原图入口；页清单通过 `thumbnail_warning` 与空 `thumbnail_url` 区分缺少缩略图和图片错误。子进程保留 512 MiB 地址空间、CPU 和父进程超时保护，异常退出时回收部分缓存。确实无法识别、解码损坏和不支持的动画仍返回实际错误。重新扫描会恢复旧的尺寸或处理资源错误记录，保留原 ID 与阅读进度；封面选取第一张有缩略图的可读图片。

## 回收站与文件操作

视频和图包移入回收站只记录标记，保留源文件；恢复取消标记。旧版已物理移动的视频回收记录仍可恢复，遇同名冲突不覆盖。旧 `.video-viewer-trash`、`.video-viewer-tmp` 和自定义 `VV_TRASH_DIR` 可能仍承载这些记录，不随改名或升级清除。

永久删除需要明确确认，服务端受理后后台执行：视频以选中的视频条目为单位，图包使用 `/api/v1/pack-trash/directories/permanent`，以选中的图包目录为单位删除，不需要在 App 先逐张核对图片清单。图包内附件也属于目录删除范围。旧图片清单接口仅供兼容旧客户端和历史任务，飞牛模板可通过 `VV_LEGACY_PURGE_PREVIEWS=false` 停止新建旧式预览，不影响目录删除。

查看原任务了解完成、失败或部分完成的结果。写操作使用 `request_id` 标识，查询原请求/任务不会重发操作。连接中断或凭据过期后先核对实际结果；重启恢复和幂等处理不意味着可用新请求反复提交删除。

## 完整备份与兼容

App 在服务声明 `backup_v2` 时使用完整管理备份：v2 NDJSON 包含视频与图包身份、两套标签、目录、固定范围、阅读进度、偏好、最近和管理历史。它不包含源媒体、缓存、口令、访问凭据或 App 本机外观设置。

恢复先校验文件、核对目录映射，再明确确认替换。服务建立恢复前快照；快照入口只生成预览，仍需确认才能恢复。恢复不会复制媒体、找回已永久删除的文件或重放历史文件操作。中断后查询原任务，旧连接中的写入意图不能跨恢复继续执行。

`VV_BACKUP_MAX_BYTES` 默认32 MiB，可配置4096字节至256 MiB，实际限制通过 `/api/v1/info` 返回。管理目录在 `/data`，导出和恢复前快照位于其备份目录，不自动清理；升级及实例回退前的停机快照方法见部署说明。

旧视频管理备份 `/api/v1/backups` 和 `/api/v1/backup-imports` 继续兼容，格式为 `video-viewer-management` v1。CLI 的 `rv backup` 使用这个视频备份入口，不能当作包含图包的完整备份；完整备份使用 App 的上述 v2 入口。旧 v1 文件可由完整备份流程校验转换。旧格式标识、内部目录和数据库字段不随产品改名随意替换。

## 验证

在仓库根目录运行：

```bash
bash scripts/test-server.sh
```

Windows 可通过 WSL 执行同一脚本。它构建测试镜像并运行 Ruff、格式检查和服务端测试，容器使用非 root 用户、只读根文件系统、64 MiB 共享内存及临时 `/tmp`。测试只使用合成媒体和临时数据库，不对真实收藏运行文件操作实验。

待办与实际设备验收在 [GitHub issues](https://github.com/ShiJiJS/shika/issues) 跟踪。
