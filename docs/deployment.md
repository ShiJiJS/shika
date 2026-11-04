# 部署与日常使用

> 2026-10-30：现有NAS已升级至媒体库体验服务，当前App为preview.16/code22，支持图包和独立标签。当前安装、首次扫描和回退以[本次部署说明](nas-preview-2026-10-30.md)及[安装候选](library-first-preview.md)为准；下文保留V1部署和历史行为说明。

适用于第一版测试交付：FastAPI 单容器、单端口、SQLite 持久化，Android Flutter 客户端。S1–S6 与 I1–I6 已完成，并已部署极空间 ARM64 NAS；首次建库、目标手机和性能仍按 [V1 状态](v1-validation.md) 验收。下面的 NAS 路径是通用示例；实际个人连接配置保存在私有 infos。

## 1. 准备目录、权限和个人口令

NAS 需要 Linux Docker Engine 与 Compose v2，或独立 Compose 二进制。目前已有 `linux/amd64` 本机与 `linux/arm64` 极空间运行证据；没有发布通用多架构镜像。NAS 可以原生构建，也可从本机导入匹配架构的镜像。获取此私有仓库需要自己的 GitHub 访问权限，凭据不要写入仓库或 Compose。

本次 RK3568 原生安装构建依赖较慢，改在 WSL 使用 Buildx/QEMU 生成 ARM64 镜像，再通过 SSH 导入。构建依赖和 NAS 系统软件分开，未升级 NAS Docker。项目自带校验过官方 SHA-256 的 Compose v2.39.4 ARM64 二进制，通过 `sudo -n ./bin/docker-compose -f compose.yaml ...` 维护；全局插件不变。跨架构构建前需具备 [Docker 官方说明中的 QEMU/Buildx 支持](https://docs.docker.com/build/building/multi-platform/)。

在对应源码版本的仓库根目录构建导出，例如：

```bash
docker buildx build --platform linux/arm64 --target runtime -t video-viewer-server:b622329-arm64 --output type=docker,dest=server-arm64.tar services/server
```

把归档传到 NAS 后 `sudo docker load -i server-arm64.tar`，在实际 Compose 中使用该镜像，执行 `up -d --no-build --wait`。构建、导入和运行后均核对架构，不将已有 amd64 镜像改标签后当 ARM64 使用。

先用独立测试视频目录验收，确认后再接入收藏。例如：

| NAS 实际路径示例 | 容器路径 | 用途 |
| --- | --- | --- |
| `/volume1/docker/video-viewer/data` | `/data` | 数据库、缩略图、任务、导出及恢复前快照，必须持久化 |
| `/volume1/video-viewer-test` | `/media` | 视频父目录，保持原有文件夹结构 |
| `/volume1/docker/video-viewer/config` | `/config`，只读 | `mounts.json`，允许访问的目录范围 |
| `/volume1/docker/video-viewer/passphrase` | `/run/secrets/passphrase`，只读 | 个人口令，至少 8 字符 |

使用 NAS 上的专用非 root UID/GID。在 NAS 的权限界面给它管理数据目录的读写权限、口令和配置的读取权限，以及媒体目录的读取和移动/删除权限。新版加入回收站及恢复只写数据库，媒体只读也可操作；永久删除及旧版物理回收记录的恢复才需要媒体写权限。不要为此递归改变整个收藏的所有者。

当前极空间用户授权目录为 root 所有，普通 UID 只读。此实例配置为容器 UID/GID 0:0，保留全部 capabilities 丢弃、只读根文件系统和 no-new-privileges，仅绑定授权媒体子树及专用数据目录；没有放宽 Docker socket 或修改收藏权限。该实例资源上限为 768 MiB、1.5 核、128 个进程，3 路媒体读取和 900 秒扫描间隔，仍需实际手机/媒体条件评估。

在 Bash 终端中，创建自己的应用目录后可隐藏输入口令；此示例不覆盖已有口令：

```bash
mkdir -p /volume1/docker/video-viewer/data /volume1/docker/video-viewer/config
umask 077
if [[ -e /volume1/docker/video-viewer/passphrase ]]; then
  printf '口令文件已存在，保持原值。\n'
else
  read -r -s -p '个人口令（至少 8 字符）: ' vv_passphrase
  printf '\n'
  if [[ ${#vv_passphrase} -ge 8 ]]; then
    printf '%s\n' "$vv_passphrase" > /volume1/docker/video-viewer/passphrase
  else
    printf '长度不足，未创建口令文件。\n'
  fi
  unset vv_passphrase
fi
```

运行 Docker 的服务 UID 必须能读取该文件；若与创建文件的用户不同，通过 NAS 权限设置授权。App 登录时输入同一个口令，App 只保存访问凭据，不保存个人口令。修改文件中的口令后重建容器，原访问凭据将失效，需要重新登录。

## 2. 配置允许范围

例如测试视频实际在 `/volume1/video-viewer-test/shorts` 和 `/volume1/video-viewer-test/camera`。在 `config/mounts.json` 写入容器内路径：

```json
[
  {"id": "shorts", "name": "短视频", "path": "/media/shorts"},
  {"id": "camera", "name": "相机片段", "path": "/media/camera"}
]
```

`id` 保持唯一、稳定；首次启动建立这些媒体目录。App 的“媒体目录”可在允许范围内接入子目录，浏览页文件夹按钮逐层选择目录。它不能浏览 NAS 上未挂载、未允许的任意路径。服务不跟随符号链接。

默认回收站在每个接入目录的 `.video-viewer-trash`，也在媒体 bind mount 中持久化；临时操作区为 `.video-viewer-tmp`，两者都不会被扫描为新视频。第一版不自动清空回收站。不要在外部工具中随意修改这两个内部目录。

有额外物理卷时，在 Compose 中增加实际的 bind mount，并在 `mounts.json` 声明对应的容器路径。需要独立回收卷时，可在 Compose 增加 `VV_TRASH_DIR` 和对应挂载，具体限制见 [服务端说明](../services/server/README.md#文件操作与恢复)。改变回收路径不会迁移已有内容，旧卷必须保留到条目处理完毕。

## 3. 启动与连接

在仓库根目录复制 `.env.example` 为 `.env`，按实际路径修改。例如：

```dotenv
VV_DATA_PATH=/volume1/docker/video-viewer/data
VV_MEDIA_PATH=/volume1/video-viewer-test
VV_CONFIG_PATH=/volume1/docker/video-viewer/config
VV_SECRET_PATH=/volume1/docker/video-viewer/passphrase
VV_UID=1000
VV_GID=1000
VV_PORT=8760
VV_BIND_ADDRESS=0.0.0.0
VV_SCAN_INTERVAL=300
VV_STABILITY_SECONDS=2
VV_MEDIA_STREAMS=4
VV_BACKUP_MAX_BYTES=33554432
```

UID/GID 按目标 NAS 修改；所有源路径须已存在。管理数据使用 NAS 本地持久化文件系统，数据库不放在 SMB/NFS 客户端挂载中。媒体与管理数据分开。

```bash
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 120
docker compose ps
curl --fail http://127.0.0.1:8760/health
```

`healthy` 只说明进程可以响应；媒体探测或目录权限问题需在 App 的扫描任务与媒体目录页检查。容器默认只读根文件系统、非 root、单个 Uvicorn worker，业务与媒体共用 8760 端口。不要增加多 worker：当前持久化任务的执行协调以单进程为边界。

手机和 NAS 在同一局域网时，App 输入 NAS 局域网 IP 和 `8760`，以及自己的个人口令。本版允许局域网 HTTP，不包含外网发布或 TLS 配置。模拟器访问本机 WSL 服务使用 `10.0.2.2:8760`，手机不能用这个地址访问 NAS。NAS 防火墙按局域网范围允许该端口。

启动会扫描，之后默认每 300 秒检查一次；手动刷新可立即发起扫描，已有扫描会合并。稳定观察默认 2 秒，持续写入的视频暂缓处理；复制文件结束后再次刷新。未变化的视频复用媒体信息和缩略图。扫描一次只处理一个任务，媒体原文件流默认最多 4 路，可按 NAS 资源降低；不进行实时转码。

首次先枚举目录并观察文件稳定，再逐个完整校验内容、探测和生成缩略图。已处理记录逐个持久保存，但首次建库完成前锁定预览播放；列表数量标明仍在更新。所有已映射目录完成遍历和文件身份核对后才开放播放，并补全准备期间建立的不完整轮次。已就绪库的日常增量扫描不锁定现有播放，新增内容仍进入下一轮。关闭 App 不会中断服务端扫描，阶段、发现/已处理数量、字节量和逐目录状态自动同步到客户端。

大库首次处理时间取决于总字节数和媒体复杂度，不能按几十个样本的速度估计。界面显示已完成文件的字节量，不把它视为实时磁盘吞吐或精确 ETA。SQLite 使用 WAL、FULL 同步和 1000 页自动检查点，管理目录须为支持 WAL 的本地文件系统。重建容器保留完整管理目录后，已有视频身份、元数据、标签和回收站索引继续使用，未变化文件复用扫描结果。

## 4. 安装与开发调试

当前 NAS 手机测试包为 `tmp/releases/video-viewer-0.1.4-nas-arm64.apk`，0.1.4 / code 5，SHA-256 `1efa5d9fcea0f92e3b35471f167bd2cb7a4f75fb83f81061581b3b5b4d61296d`。可覆盖安装，地址和口令不变。本版加速未变化视频的永久删除，结果查询不锁界面，增加同步外部删除与手动清理失效元数据，提示使用不占视频面积的悬浮层，见 [验证与操作](purge-and-missing-validation.md)。以下包信息保留作历史记录。

0.1.3 历史交付： `tmp/releases/video-viewer-0.1.3-nas-arm64.apk`：0.1.3 / versionCode 4，SHA-256 `758bdfa7f1173dd42a3c6a58516dce3aff9d085d6c1aa4a2938b2c256129c0f3`。可覆盖安装，包名、签名及连接口令不变。新增逻辑回收站、非阻塞翻页与连续删除、顶部定时撤销提示、回收站跨页全选和后台恢复，见 [行为与验证](logical-trash-and-browsing.md)。旧版已移动记录继续兼容恢复；以下包信息保留作历史记录。

0.1.2 历史交付： `tmp/releases/video-viewer-0.1.2-nas-arm64.apk`：版本 `0.1.2` / versionCode `3`，21,668,902 字节，SHA-256 `0b5d5e2b6088224b0d3a9a56dd6afcbf5218c77a3a46c91d27db74f09ad5793f`。包名和本机签名与旧包相同，可覆盖安装保留连接凭据，口令不变。NAS 个人目录 `docker/video-viewer/packages` 已有同名副本，连接信息在同目录的私有说明文件中。本版修正 4K HEVC 精确取图超时、将可选缩略图失败与媒体读取失败分开，详见 [原因与验证](thumbnail-timeout-validation.md)；0.1.1 的准备状态与分页修正继续保留。下列 0.1.0 包信息保留作历史交付记录。

当前本机测试包位于仓库的 `tmp/releases/video-viewer-0.1.0-test.apk`，不纳入 Git；版本 `0.1.0`、versionCode `1`，Android API 24+，Flutter 引擎覆盖 ARM64 和 x86_64。实际手机仍需 V1 兼容验证。包使用本机 Android Debug 证书签名，仅用于本次测试交付。

另有面向当前 NAS 测试的 `tmp/releases/video-viewer-0.1.0-nas-arm64.apk`，只包含 ARM64 Flutter 引擎，约 20.6 MiB，默认地址为用户的 NAS 局域网地址；版本/签名策略相同。已复制到 NAS 个人目录的 `docker/video-viewer/packages`，同目录的“手机连接信息.txt”仅供所属账户读取。服务口令也保存在私有 infos 的 `video-viewer.connection`，没有编译进 APK。

可通过 Android 文件管理器打开 APK 安装，或使用 ADB：

```powershell
adb -s emulator-5554 install -r .\tmp\releases\video-viewer-0.1.0-test.apk
```

`-r` 覆盖安装保留数据。若换机器构建、签名不同，先保留管理备份并确认处理方式；不要用卸载当作常规升级步骤。正式长期分发前需要固定并妥善保存专用签名密钥。

复现测试包，在 `apps/mobile` 执行：

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64,android-x64 --build-name 0.1.0 --build-number 1 --dart-define=LIBRARY_MODE=server
```

输出 `build/app/outputs/flutter-apk/app-release.apk`。未分 ABI 打包，避免 Flutter ABI 分包附加 versionCode 影响本机调试覆盖安装。少数插件包含 32 位辅助库不表示此包有 32 位 Flutter 引擎。

VS Code 的 **Shika (Android)** 继续 F5 调试真实服务；**Shika Demo (Android)** 使用独立演示数据。演示模式也可通过 `--dart-define=LIBRARY_MODE=demo` 构建，不能在运行时把演示备份导入真实服务。环境和热重载步骤见 [Android 开发说明](android-development.md)。

## 5. 日常新增、浏览和快速整理

1. 自己把视频放入已接入的 NAS 文件夹，等待复制完成，在 App 刷新或等待定时扫描。App 不上传视频，也不会按标签自动移动源文件。
2. 浏览页上下滑动切换，当前视频播完循环。文件夹按钮选范围，随机/顺序按钮切换模式，标签点击后高亮；多标签按同时满足筛选。空结果保持为空，不退回全库。新加入视频进入新轮次，主动重新随机可开始下一轮。
3. 点画面暂停/继续，长按临时 2 倍速，松手恢复。进度默认隐藏，左右拖动画面或底部区域快进/后退。横版视频用“横屏”按钮进入全屏，左上箭头退出；控件闲置 3 秒隐藏。横屏左侧上下滑调窗口亮度，右侧调媒体音量。
4. 视频库支持搜索、属性筛选、多选批量追加/移除标签；接近底部时自动分页加载，用整行紧凑动效反馈，失败保留已加载卡片和滚动位置，可就地重试。标签页可新建、改名和删除。标签只改管理数据，不改文件名或路径。
5. 从视频库或更多菜单进入“快速整理”，限定范围后连续查看、打标签、移入回收站。未删除就是保留，没有另一套保留标记或归档类别。按标签一键调整文件夹不在本版。
6. 点击删除立即切下一条，服务端只作回收站标记，原文件不动。顶部提示 8 秒自动消失，下一次删除替换上一条提示；可撤销准确的最近一次成功删除。断网或退出导致结果不确定时，使用“查询结果”，不要把重新提交当成查询；重开也只核对原任务。
7. 设置 → 回收站，可全选全部分页、批量取消回收标记；处理期间允许离开继续浏览。旧版已移动的回收文件恢复时不覆盖原位置已有文件。永久删除需明确确认，不能靠管理备份找回视频字节。
8. 更多菜单或设置可切换暗黑模式，两处同步且重开保留。设置 → 准备相邻视频可减少资源占用；默认当前加前后各一条，最多 3 个播放器，只有当前发声。收益与 NAS/手机条件有关，尚无目标设备性能结论。

外部改名或移动文件后刷新，证据充分时保留视频 ID 和标签，并显示实际路径。重复副本、同路径换成不同内容、身份不唯一时不会猜测继承标签。移出范围后显示缺失，移回后可重新识别；整个目录断开显示目录不可用，不将其全部误记为视频缺失。

## 6. 备份、恢复和升级

设置 → 备份与恢复，创建管理备份，等待完成后通过 Android 文件选择器保存到自己指定的位置。检查文件确实保存，并另存到 App 之外；服务端 `/data/backups` 也保留导出及恢复前快照，当前不自动清理，需定期检查剩余空间。

正式格式为 `video-viewer-management` v1，包含目录映射、视频身份、标签、回收索引、轮次及操作回执，带完整性校验。它不包含视频原文件、可再生缩略图、登录口令/凭据或 App 外观设置。客户端单个管理备份传输上限 32 MiB；只提高服务端限制不会提高客户端上限。

恢复到现有实例时：选择正式备份 → 等待校验 → 核对数量及每个目录映射 → 明确勾选完整替换 → 执行并等待读回。取消预览不会修改管理数据。处理中或结果待确认时禁用冲突写入；断网/退出后重新连接并查询同一任务，不自动重放恢复。恢复前快照可用于检查和再次恢复。

恢复到新机器或空管理实例时：

1. 先恢复视频目录及其中的 `.video-viewer-trash` 实际文件，保持可验证的内容；设置新的口令、允许挂载及空的持久化数据目录。
2. 启动服务，连接这个新实例，上传先前正式管理备份。
3. 对每个旧媒体目录显式选择当前的容器内路径。保留未映射时相应记录为缺失，服务不访问旧 NAS 路径；映射不会创建文件夹或移动视频。
4. 确认替换完成后检查标签、筛选、轮次位置和回收站。App 自动请求一次扫描，目录核对结束前锁定播放；直接调用恢复 API 的使用方须再请求扫描。缩略图在扫描中重建。已恢复且候选集合完整的轮次保留顺序和位置，核对完成后再重开 App 检查播放。

恢复按磁盘现状判断可用、回收或缺失，不能回滚真实文件移动或找回已永久删除的原文件。旧删除/撤销历史不会因恢复重新执行。原视频和回收内容需另做 NAS 文件备份。

容器重建不删除 bind mount：

```bash
docker compose up -d --force-recreate --wait
```

更新源码和镜像前，先保存管理导出与原文件备份。需要可回退的完整实例快照时，停止服务后备份整个 `data` 和 `config`，另外安全保存口令，再启动；不要在运行时只复制 SQLite 主文件。数据库迁移在启动时执行，不承诺旧镜像能打开新数据库。回退应配对还原原镜像和停机快照，避免把管理状态和已经改变的物理媒体混为同一次回滚。

## 7. 已知边界与排查

| 现象 | 检查方式 |
| --- | --- |
| 手机连接失败 | 手机能否到 NAS IP、端口/防火墙、容器 health；`10.0.2.2` 只用于模拟器 |
| 401 / 需要重连 | 重新输入个人口令；口令更改、过期或主动撤销会使旧凭据失效 |
| 看不到新视频 | 挂载与允许范围、复制是否完成、媒体目录可用性、扫描阶段及逐项错误 |
| 删除失败 | 服务 UID/GID 的目录写权限、剩余空间、原文件是否被外部替换、目标文件系统移动能力 |
| 恢复冲突 | 原位置已有内容不会覆盖；核对路径，保留冲突文件后再处理 |
| 某个视频打不开 | 设备实际支持的编码/音频/分辨率；扩展名相同不保证能解码，当前无转码兜底 |
| 扫描慢或快刷卡顿 | 先关闭相邻准备，检查 NAS 扫描/校验负载与网络；按目标环境测量后调整，不直接增加并发 |
| 大批 4K HEVC 读取失败 | 先看失败分类；旧版可能是缩略图 20 秒超时，不能当成原视频损坏。0.1.2 使用关键帧取图，缩略图待补充不再阻止入库；原探测仍失败的文件按实际原因检查，不批量删除或转码 |
| 备份不能导入 | 正式格式、版本和校验、32 MiB 客户端上限；演示或 HTML 原型备份不能混用 |

本机生成的 H.264/HEVC MOV 等样本有实际播放证据，ProRes/PCM MOV 在当前模拟器无法解码；服务仍可探测、索引和授权返回原字节。真实高码率、HDR、特殊音轨、ARM NAS 文件系统和目标手机系统文件选择器仍需实测。本版不含图包、刮削、AI 标签、外网、多用户、离线下载、按标签自动搬文件。
