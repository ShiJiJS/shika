# Video Viewer 服务端

当前完成 S1–S6：口令认证、多媒体目录扫描、目录层级、媒体信息、缩略图、分页查询、持久化任务、授权原文件流、随机/顺序轮次、标签管理、真实回收站、外部文件变化识别及完整管理备份恢复。Flutter I1–I6 真实联调已完成。NAS 配置、Android 安装与日常使用见 [部署手册](../../docs/deployment.md)；已完成能力与证据见 [服务端验证记录](../../docs/server-validation.md) 和 [V1 待验项](../../docs/v1-validation.md)。

## 完整备份与兼容

当前媒体库／图包开发版通过 `GET /api/v1/info` 的 `backup_v2` 能力开放完整备份页：两套标签、目录、图包／页身份、阅读进度、偏好、最近及管理历史一起保存，不包含媒体、缓存或口令。旧服务没有该能力时，App继续使用原视频备份页；已有未完成v1任务仍按原协议只读核对，不会自动重发或改成v2任务。

完整备份文件使用NDJSON，经手机系统保存／选择；恢复先校验和预览，再确认目录映射及完整替换，并自动建立恢复前快照。快照入口只打开预览，仍需明确确认才能恢复。旧v1文件可以校验并转换；恢复会按备份状态替换当前管理数据，原文件和已永久删除的媒体不会被备份复活。

`VV_BACKUP_MAX_BYTES` 默认32 MiB（33554432字节），可显式配置4096字节至256 MiB；服务通过info返回实际上限，App按该值校验。超过上限会明确失败，不自动截断或扩容；本地约41 MB文件往返使用独立64 MiB配置，不表示默认上限已提高。服务更新和配套App仍须经过目标环境及原签名升级验证，当前源码开放入口不等于已发布到NAS。

## 本机 WSL2 开发

在仓库根目录的 PowerShell 中执行：

```powershell
wsl -d Ubuntu-24.04 -- bash /mnt/c/Project/video_viewer/scripts/prepare-server-dev.sh
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker compose up -d --build
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker compose ps
```

准备脚本仅在文件不存在时建立专用开发目录、随机口令及被 Git 忽略的 `.env`，不会打印口令。数据、测试媒体、配置和口令保存在 WSL 的 `~/.local/share/video-viewer-dev/`。真实收藏不要放入这个开发测试目录。

健康检查：Windows `http://127.0.0.1:8760/health`，模拟器 `http://10.0.2.2:8760/health`。服务业务接口需要登录后的 Bearer 请求头，缩略图也需要授权。

容器使用 UID/GID 1000、只读根文件系统与临时 `/tmp`，管理数据挂到 `/data`。`.env` 可设置 UID/GID、端口、监听地址、扫描间隔及稳定观察时间。默认启动时扫描，之后每 300 秒扫描；手动刷新与正在运行的扫描合并为同一任务。稳定观察默认 2 秒；未变化的文件复用媒体信息和缩略图。

停止或重建：

```powershell
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker compose stop
wsl -d Ubuntu-24.04 --cd /mnt/c/Project/video_viewer -- docker compose up -d --force-recreate
```

这些命令保留数据和测试媒体。业务数据在 `library.sqlite3`，版本由 Alembic 管理；使用 SQLite WAL、FULL 同步、1000 页自动检查点及短事务串行写入，让后台扫描不阻塞普通读取。管理目录必须位于支持 WAL 的本地文件系统，运行中不能只复制数据库主文件而忽略 WAL；使用 App 逻辑备份或停机完整备份。依赖与镜像基础摘要已锁定，FFmpeg 版本在 Dockerfile 中固定。

## 媒体目录配置

`config/mounts.json` 声明允许接入的容器内挂载范围，首次启动会按这些条目建立媒体目录。例如将一个父目录挂到 `/media`，接入两个收藏文件夹：

```json
[
  {"id": "shorts", "name": "短视频", "path": "/media/shorts"},
  {"id": "camera", "name": "相机片段", "path": "/media/camera"}
]
```

App 后续通过 API 在允许范围内添加子目录或修改名称和接入范围；目录选择使用服务返回的稳定标识。重叠目录不会重复建立同一物理位置的视频记录，空子目录也可以查询。服务不跟随符号链接，不枚举任意服务器路径。

初次扫描保留路径与名称。仍在变化的文件延迟处理，损坏或无法探测的文件在任务中返回原因。整个目录不可访问、递归遍历失败或扫描中断时保留记录；成功完整扫描后才标记未发现的视频为缺失。

全新库没有历史视频身份时，每个完成稳定检查、内容校验和媒体探测的视频即可浏览，不必等待整库完成。中断后保留已经发布的视频和标签；后续扫描仍等完整范围证据再核对新发现的身份，避免重复副本或外部移动错误继承标签。

NAS 部署时从 `.env.example` 设置 NAS 本地数据路径、视频挂载路径和当前服务 UID/GID，创建权限匹配的口令文件和配置。额外物理卷可在 Compose 中添加 bind mount，并在 mounts.json 声明范围。NAS 架构、真实媒体兼容性与资源表现待 V1 验证。

## 已实现 API

除 `/health`、登录和接口文档外，以下 API 需要 `Authorization: Bearer <token>`。登录返回可撤销随机 token，数据库只保存 token 摘要和口令哈希；口令变更会撤销原 token。

| 请求 | 行为 |
| --- | --- |
| `POST /api/v1/auth/login` | JSON `{ "passphrase": "..." }` 换取 token 和有效期 |
| `DELETE /api/v1/auth/session` | 撤销当前连接凭据 |
| `GET /api/v1/info` | 当前服务标识和 API 版本 |
| `GET /api/v1/mounts` | 已声明的允许挂载范围 |
| `GET/POST /api/v1/roots` | 查询或接入媒体目录 |
| `PUT /api/v1/roots/{id}` | 修改名称或允许范围内的接入路径，扫描期间返回冲突 |
| `GET /api/v1/directories?parent_id=...` | 已扫描到的直接子目录；无 parent_id 时返回媒体目录入口 |
| `GET /api/v1/directories/{id}` | 按稳定 ID 恢复已选目录路径及可用状态 |
| `GET /api/v1/directories/resolve?path=...` | 在允许挂载范围内解析已扫描目录的 ID；不枚举任意服务器路径 |
| `POST /api/v1/scans` | 发起或取得已有扫描任务，返回 202 与任务标识 |
| `GET /api/v1/tasks` | 最近任务，默认 20 条、最多 100 条 |
| `GET /api/v1/tasks/{id}` | 任务阶段、状态、逐目录结果和受限数量的失败原因 |
| `GET /api/v1/videos` | 分页查询，支持目录标识、名称、方向、时长、类型与可用/缺失/回收状态 |
| `GET /api/v1/videos/{id}/thumbnail` | 授权 JPEG 缩略图 |
| `GET/HEAD /api/v1/videos/{id}/stream` | 授权原文件，支持 Range、If-Range、长度、类型和内容 ETag |
| `GET /api/v1/playback` | 当前轮次、模式、位置、筛选及最多 3 个相邻可播放摘要；未建立时创建默认随机轮次 |
| `POST /api/v1/rounds` | 用 request_id、order、scope 和可选 anchor_video_id 创建轮次；同一请求重试返回原轮次 |
| `GET /api/v1/rounds/{id}/entries` | 分页读取该轮候选顺序，提供视频摘要和位置 |
| `PATCH /api/v1/rounds/{id}/position` | expected_revision 与 video_id 更新位置；finish=true 明确标记耗尽 |
| `GET/POST /api/v1/tags` | 分页名称搜索、可播放视频计数；使用 request_id 和 name 新建 |
| `PATCH /api/v1/tags/{id}` | 使用 request_id 与 name 改名，保留稳定 ID 和关联 |
| `DELETE /api/v1/tags/{id}` | JSON request_id 删除标签及关联，原文件保留 |
| `PATCH /api/v1/video-tags` | request_id、video_ids、tag_ids、mode 批量关联；mode 为 add/remove/replace |
| `POST /api/v1/videos/trash` | request_id、video_ids 移入回收站，202 返回任务 |
| `GET /api/v1/trash` | 分页列出活动回收条目，保留视频 ID 与标签 |
| `POST /api/v1/trash/restore` | request_id、trash_ids 按条目恢复原路径，冲突不覆盖 |
| `POST /api/v1/trash/permanent` | request_id、trash_ids、confirmed=true 永久删除指定条目 |
| `POST /api/v1/operations/{id}/undo` | request_id 精确撤销最近成功删除，旧操作返回冲突 |
| `POST /api/v1/operations/{id}/retry` | request_id 重试该操作未完成条目，成功项不重做 |
| `GET /api/v1/operations/{id}` | 文件操作任务、阶段和逐项成功/失败结果 |
| `GET /api/v1/file-requests/{request_id}` | 按客户端命令 ID 只读查询文件操作，未受理返回 404，不触发重执行 |
| `POST /api/v1/backups` | request_id 创建一致性管理备份，202 返回导出任务 |
| `GET /api/v1/backups` | 最近完成的导出及恢复前快照，默认 20、最多 100 |
| `GET /api/v1/backups/{id}/download` | 授权下载已完成的 JSON 备份 |
| `POST /api/v1/backup-imports` | 上传原始 JSON 文件，Idempotency-Key 请求头可重试；202 返回校验任务 |
| `POST /api/v1/backup-restores` | request_id、preview_id、root_mapping、confirmed=true 接受完整恢复 |
| `GET /api/v1/backup-requests/{kind}/{request_id}` | 按 export/inspect/restore 与客户端请求 ID 只读查询备份任务 |
| `POST /api/v1/management-backups` | request_id 导出视频和图包的完整v2管理备份，202返回任务 |
| `GET /api/v1/management-backups/{id}/download` | 授权下载已完成的NDJSON备份／快照文件 |
| `POST /api/v1/management-backups/imports` | 上传v2或旧v1文件，Idempotency-Key标识原校验任务，202返回任务 |
| `GET /api/v1/management-backups/{id}/roots` | 校验成功后的根目录映射清单，默认24条、最多100条 |
| `POST /api/v1/management-backups/restores` | request_id、preview_id、root_mapping、confirmed=true 明确完整替换，202返回任务 |
| `GET /api/v1/management-backups/latest-restore` | 只读取得当前服务最近一次成功恢复及对应快照信息 |
| `POST /api/v1/management-backups/from-snapshot/{id}` | request_id 校验指定恢复前快照，仅生成预览，不发起恢复 |
| `GET /api/v1/management-backups/requests/{kind}/{request_id}` | 按export/inspect/restore原请求只读查询，不补执行 |

分页为 offset/limit，默认 50、最多 200；返回 items/total/offset/limit。目录范围包含子树，名称按字面查找，排序为路径与稳定 ID。视频摘要包含实际视频/音频编码、容器、时长、旋转后的尺寸、媒体入口与 tag_ids；标签列表返回稳定 ID 和名称。完整参数可在 `/docs` 和 `/openapi.json` 查看。

错误统一为 `{"error":{"code":"...","message":"..."}}`；参数错误返回字段位置，不回显原输入或口令。业务未授权为 401，目录越界或输入非法为 422，不存在为 404，扫描忙/媒体不可用等冲突为 409。

## 播放协议与轮次

媒体通过已校验的文件描述符读取，执行时核对文件属性和路径范围。原文件改变、缺失或不可访问时返回明确错误，不读取被替换位置的新内容。Range 为 206，越界范围为 416，格式错误为 400；范围协议错误采用文件响应约定。默认最多 4 个媒体读取连接，可用 `VV_MEDIA_STREAMS` 调整；并发已满为 503，取消、错误和正常结束均释放资源，前台业务接口独立响应。

轮次建立时保存候选顺序；随机顺序不会随普通重开改变，顺序模式按目录和文件名排列。新增视频留到新轮次，筛选或模式变化通过新建轮次表达。scope 包含 directory_id、orientation、duration、file_type 和 tag_ids。

位置提交使用目标视频 ID 和 expected_revision，避免目录变化或并发迟到请求把位置写到另一条。相同位置重试幂等，冲突返回 409 后重新读取当前轮次；被新轮次替代的旧轮次不能再写位置。创建轮次重试要复用 request_id，用户主动换范围或重新随机则生成新 request_id。重试旧轮次创建不会重新激活它。

耗尽通过 finish=true 显式标记，最后一条仍可循环；回看会解除耗尽标记。只有轮次与条目位置持久化，单视频时间进度由播放器从头开始。失效条目在选中和相邻准备前重新校验，空候选不退回全库。

## 标签语义

标签平铺，名称去首尾空白，空名与完全重复名称拒绝。列表查询使用重复的 `tag_ids` 参数表示 AND，例如 `?tag_ids=idA&tag_ids=idB`，并与目录子树和属性条件共同生效；未选择标签表示无标签限制，未知标签或空结果不会扩大范围。

批量单次最多 1000 个视频、256 个标签，重复 ID 按集合处理。add 追加、remove 仅移除明确指定的标签，replace 精确替换；replace 的空标签集合表示清空所选视频标签。未知视频/标签会让整次关联操作失败并回滚。标签与关联的写操作都使用 request_id，重试返回原操作结果；客户端随后刷新权威标签列表或相关分页，不把历史结果当作当前完整状态。

改名保留标签 ID，轮次筛选不变；删除活动筛选中的标签会在同一事务中解除关联、移除该筛选条件并建立新轮次，保留其他范围条件。批量打标和标签维护只修改管理数据，目录名不会自动转标签，原视频位置与字节保持。

## 外部改名、移动与缺失

扫描接受外部路径，识别后更新记录，不搬回文件。新发现先在成功扫描的范围内核对身份再公开：相同设备/inode 与完整内容一致且候选唯一时保留 ID；跨文件系统则要求完整 SHA-256 和大小/快速指纹一致，旧缺失记录及已知可用内容对应唯一。快速指纹相同而完整内容不同不会继承标签。

重复副本、硬链接位置分别记录；对应关系不唯一时保留旧缺失记录，新记录不继承旧标签，任务通过 identity_ambiguous 计数及受限 issues 表达。整个目录不可用与单个视频缺失分开；目录断开、未完成扫描和文件操作中间状态不能用于猜测合并。重新发现证据充分的缺失视频会恢复原 ID 与标签。任务另返回 identity_matched 计数。

整个轮次范围内的文件移到别处后，不扩大为全库；外部移除所选目录时旧轮次保留范围并为空，重新选择存在的目录建立新轮次即可。身份核对使用 SQL 聚合保存紧凑计数，每次至多加载两条旧候选、逐文件短事务发布，不一次载入全库视频与标签对象。

## 文件操作与恢复

文件操作先持久化意图，再由单个执行器处理。202 表示已接受，客户端轮询任务直到完成，检查 result.items 的逐项结果和 partial；只有物理操作完成且数据库提交后才报告成功。同一视频操作互斥，重试复用 request_id；撤销绑定原删除操作 ID。

默认回收位置为各接入目录的 `.video-viewer-trash/<条目ID>/<原文件名>`。临时中间区为源/目标父目录的 `.video-viewer-tmp`，两者均从扫描排除。不自动清空。原目录已有同名文件、来源被替换或路径为链接时拒绝执行，保留冲突等待处理。恢复成功保留稳定视频 ID 和标签；撤销在原范围和目标仍有效时恢复原轮次位置。

同文件系统使用 Linux renameat2 的不覆盖移动；文件系统不支持时返回 filesystem_unsupported，保留原文件。跨文件系统先复制、fsync 和完整 SHA-256 校验，再发布目标并清除受控中间区来源。异常时优先恢复完整来源，无法核对的副本保留并报告冲突。重启核对未完成阶段后接续；历史成功步骤不重复操作。

可用容器内绝对路径环境变量 `VV_TRASH_DIR` 指定独立回收位置（自定义 Compose 环境与卷），默认 Compose 不设置。它不能包含媒体挂载根，若位于媒体范围内也从扫描排除。路径调整不会自动迁移已有回收内容，请保留原挂载和配置直到条目处理完毕。真实 NAS 文件系统能力仍须 V1 验证。

## 管理备份与完整恢复

导出格式 `video-viewer-management` v1，当前支持数据库格式 0004。逻辑快照包含目录映射、视频证据、标签关联、回收站索引、轮次顺序/位置和操作回执，带规范 JSON 的 SHA-256 校验及文件 SHA-256。不包含原视频、可再生缩略图、口令哈希、访问凭据或本机外观设置。鉴权和当前服务身份保留在实例中，新环境单独设置口令。

先导出并等待任务 completed，然后下载。导入以 JSON 文件原字节上传，等待校验任务 completed，读取 result.roots 的原路径与建议映射；校验坏包、版本、字段类型、关联及唯一约束不修改现有管理数据。请求大小默认最多 32 MiB，可通过容器环境 `VV_BACKUP_MAX_BYTES` 调整（4096 字节至 256 MiB）；读入和导出都受该边界限制。导入后的文件如果变化，恢复会拒绝，须重新上传确认。

恢复必须显式确认并为每个备份目录提交映射，例如 `{"main":"/media/shorts","camera":null}`；null 明确保留未映射，记录保持缺失，服务不访问旧环境路径。映射目标必须位于允许挂载内，不能指向管理数据、回收位置或链接。映射不创建媒体目录，也不复制或移动原文件。

扫描、文件操作或其他备份正在进行时返回 library_busy；接受恢复后普通写入返回 503/restore_in_progress，查询与任务轮询仍可用。先保存可下载的恢复前管理快照，再核对原位置、当前已知位置及受控回收文件，完整校验内容后在一个数据库事务中替换管理数据。事务失败保留旧数据；进程被终止时，重启接续同一任务，恢复核对完成后再启动扫描和文件执行器。

恢复根据磁盘现状表达可用、回收或缺失，不回滚真实文件移动，不声称找回已永久删除的视频。当前可验证的回收索引及命令回执保留为安全证据，标签、筛选和视频管理记录按备份替换。所有历史文件操作隔离为只读记录，旧撤销和显式重试不能重新执行；备份后发出的旧请求再次到达时也只返回回执。客户端随后刷新权威状态。

恢复前快照及导出文件在 `/data/backups`，不自动清理。任务 result.pre_snapshot_id 可用于下载恢复前快照；客户端恢复请求重试复用 request_id，重新发起恢复使用新的请求标识。未映射目录可后续通过媒体目录配置重新接入；恢复产生的根目录不会在重启时被默认挂载范围静默扩大。缩略图在下一次扫描重建。此协议区别于 Flutter 演示备份格式；I6 已验证真实客户端文件传输、确认、断线只读核对及新实例显式映射恢复。

## Docker 内验证

```powershell
wsl -d Ubuntu-24.04 -- bash /mnt/c/Project/video_viewer/scripts/test-server.sh
```

测试镜像由同一 runtime 构建，使用非 root 用户和只读根文件系统，在容器临时目录生成媒体和数据库。覆盖 MP4、MOV、MKV、WebM、AVI，以及 H.264、HEVC、VP9、MPEG-4 Part 2、ProRes；MOV 另含旋转与 PCM 音频。生成器也可用于指定的可丢弃开发目录，固定样本名称会被重建，不要对个人视频目录运行。

测试验证服务端探测、文件字节和 API 行为，I2 已记录 Android 模拟器解码与真实网络播放结果。NAS 上的首帧、快刷、预加载及后台扫描资源测量仍属于 V1，额外性能优化记录在后续事项。
