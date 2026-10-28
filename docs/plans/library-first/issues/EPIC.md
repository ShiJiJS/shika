## 目标

将现有 0.1.4+5 Android App 升级为已确认的「媒体库为中心、视频与图包分别管理」完整产品。用户于2026-10-23确认独立的 `design/reference/library-first/` 原型方向。LF0–LF7已有分阶段实现与证据，LF8尚未终验。最新阶段：[原签名App回退与反复覆盖安装 PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)。固定a3c7659a，配套新媒体库0.2.0-preview.2和旧界面0.1.4-rollback.2均code8、原Windows签名。旧界面窄适配保留新版偏好/多范围日志及凭据代次，未知v2备份任务保留并要求回新版核对；85旧版/兼容+14新版相关检查、双方analyze及正常release通过。独立Android36同一QEMU实际6→新8→旧8→新8→旧8→新8，五次install -r、首次安装时间/身份/数据目录保持、六次免口令冷启，新版零自动播放。旧UI主题/相邻准备修改后新版顺序/迁移标记保留；旧视频回收/菜单撤销完成，升回任务可核对；图包第2页纵向/两套标签保留。148输入及两包只读复核通过，22组原生截图；一容器/自有AVD已归还，原四服务及前阶段数据/媒体未动。配套服务仍b79da7b9 preview.2，原型1cbf605独立未改；未正式发布/部署，目标手机/NAS、500页高分辨率和其余终验继续，#78/#89与#24/#33保持开放。

## 历史阶段记录

截至PR #91的完整旧正文已[原样归档](https://github.com/ShiJiJS/video_viewer/blob/4f82213012e70fec2441cbaafc2429bc501711de/docs/plans/library-first/issues/archive/EPIC-THROUGH-PR91.md)，保留所有固定版本、过程诊断和证据入口。本issue保留产品契约、实施框架、任务清单和当前进度，避免继续追加触及长度限制。

## 产品契约

- 默认进入媒体库；底部为媒体库 / 标签 / 最近 / 设置。视频与图包各自保存筛选和列表位置。
- 视频、图包从库或各自标签/最近的结果进入预览/阅读；完整范围在服务端固化，不能只预览已加载第一页，不能丢失名称搜索，不能自动跳全库。
- 视频与图包标签分开，同名独立。图包是一包一卡、整包标签，无单张管理。
- 图包支持横向翻页、纵向拼接、总览、沉浸、每包进度/偏好、限定范围手动换包；快速整理明确开启、逻辑回收、准确撤销。
- 设置完整保留连接、目录管理与扫描/缺失、批量回收/永久删除、任务查询、备份映射和恢复前快照，以及本机主题/相邻视频准备。
- 保留现有原生视频暂停、倍速、长按2倍、跟手滑动、横屏、亮度/音量和资源上限。
- 视觉沿用 P2：52 顶栏、49 导航内容+系统安全区、16侧距/12列距/18行距、390宽封面211、360宽185、16卡片标题、15设置标题。Android 不额外画 HTML 假 home indicator。

## 已确定的技术框架

继续 Flutter + ChangeNotifier、FastAPI + SQLite/Alembic、Docker 单服务。拆分 AppShell、LibraryQueryController、VideoPreview/PreviewSession、PackReadingSession、MaintenanceController；复用 PlaybackSession、鉴权传输、持久化任务与文件回执。Server 与 Demo 通过相同行为接口验证，页面不直接读 NAS。

旧视频模型、tags/video_tags、ID 与操作记录保留；新增 pack/pack_pages、独立 pack_tag_definitions/pack_tag_links、阅读进度/偏好、最近和包会话。roots 增加 kind/enabled，历史默认 video/true。查询草稿不再修改正在播放的轮次；新固定成员协议不因改标签重排，返回列表才重新查询。

图包首版以根直属文件夹为包，子目录递归归同包、相对路径自然排序；JPEG/PNG/WebP 静态图片。原图/缩略图按稳定 ID 授权读取，采用惰性列表、有限解码窗口和缓存。停用/离线不清理元数据，新图包首扫不阻塞可用视频。

正式备份升级 v2、校验转换旧 v1，显示完整替换影响；主题/相邻准备/凭据不入 NAS 备份。未知操作只读查询，不自动重发；整包永久删除限定确认的图片清单，核对版本与替换，非图片附件保留。先隔离迁移演练，后兼容服务端，再同包名/原签名/递增 versionCode 的 App；回退恢复旧管理快照。

## 实施任务

早期依赖 PR：[LF0 #34](https://github.com/ShiJiJS/video_viewer/pull/34) → [LF1 #35](https://github.com/ShiJiJS/video_viewer/pull/35) → [LF2 #36](https://github.com/ShiJiJS/video_viewer/pull/36) → [LF3 草稿 #37](https://github.com/ShiJiJS/video_viewer/pull/37) → [LF4 四入口与媒体库草稿 #38](https://github.com/ShiJiJS/video_viewer/pull/38) → [LF5 阅读会话草稿 #39](https://github.com/ShiJiJS/video_viewer/pull/39) → [LF6 逻辑整理草稿 #40](https://github.com/ShiJiJS/video_viewer/pull/40)。后续实施进度见下方记录，最新#59基于#58。前序阶段实现完成不等于整体原型验收完成，子任务等待对应依赖合并。

- [ ] https://github.com/ShiJiJS/video_viewer/issues/25 — [LF0] 锁定原型基线与可运行的模块骨架
- [ ] https://github.com/ShiJiJS/video_viewer/issues/26 — [LF1] 兼容迁移数据模型：媒体类型、图包标签与服务能力
- [ ] https://github.com/ShiJiJS/video_viewer/issues/27 — [LF2] 图包扫描、分页目录与授权图片读取
- [ ] https://github.com/ShiJiJS/video_viewer/issues/28 — [LF3] 视频从入口范围进入固定预览会话，保留原生播放能力
- [ ] https://github.com/ShiJiJS/video_viewer/issues/29 — [LF4] 原生四入口外壳、双类型媒体库与独立标签页
- [ ] https://github.com/ShiJiJS/video_viewer/issues/30 — [LF5] 图包阅读器：横翻、纵向拼接、范围与续读
- [ ] https://github.com/ShiJiJS/video_viewer/issues/31 — [LF6] 图包快速整理、准确撤销及安全的回收站操作
- [ ] https://github.com/ShiJiJS/video_viewer/issues/32 — [LF7] 设置完整接线、统一任务与兼容的管理备份 v2
- [ ] https://github.com/ShiJiJS/video_viewer/issues/33 — [LF8] 原型一致性验收、真实服务联调与兼容升级包

依赖顺序：LF0 → LF1 → LF2/LF3 → LF4 → LF5 → LF6 → LF7 → LF8。LF4 可提前用 Demo 搭页面，但真实接口未接不能关闭。

## 防止最终偏离原型

- 本地 `docs/plans/library-first/PLAN.md` 是详细框架、源码差距和迁移方案；`ACCEPTANCE.md` 列出功能及视觉验收 ID；`baseline.json` 固定当前源码/依赖/截图 SHA-256。
- 方案与独立原型已随 LF0 纳入版本控制；参考 tag 为 `design-lf-2026-10-23`，不属于 App 构建。私人图包与密钥不上传。本 issue 及子任务已包含独立可读的范围和完成标准。
- 每个 PR 引用验收 ID、实现提交和实际证据。使用相同非私人素材与状态，390×844 原型/Flutter 并排，补 360×740、横屏、暗色、大字体、键盘。
- 旧功能回归、公开接口/迁移/故障恢复、原生真实服务流程、截图与动作录屏分开验收；关键完整路径连续3轮，不能用 HTML 或 Demo 成功替代真实服务。
- 真机/NAS记录首屏、翻页、p50/p95、内存、CPU/IO/网络；破坏性操作仅在可丢弃测试目录。历史环境记录不是新功能通过证据。
- 必要页面、入口、尺寸、范围、撤销、错误/恢复行为全部有证据，LF8 完成才关闭本任务；行为变动须在对应 issue 列明原因与原型差异。

## 本轮不做

无压缩包直读、单张图片标签/删除、AI标签、离线下载、自动文件夹归档、多用户或新微服务。当前开发与故障验证使用隔离实例和合成媒体，本机预览APK已生成，尚未部署NAS或正式发布；正式交付按LF8验收与迁移流程推进。


## PR #92：正常入口预览包与原签名覆盖升级

最新阶段：[原签名预览包与覆盖升级 PR #92](https://github.com/ShiJiJS/video_viewer/pull/92)。固定cf992025，27个旧格式文件已修，139份服务Python前后AST相同；原型移除副本十步全部通过，客户端672项／服务447项。正常入口0.2.0-preview.1+6沿用Windows原签名，独立AVD实际APK5→6覆盖安装：免口令、原地址／设置及七表选定投影／登录摘要保留，新服务下启动进媒体库且零自动播放。两套标签、图包第2页横向转纵向／返回已实测；实际旧服务0004按原兼容模式保留视频UI。APK与Linux ARM64配套镜像仅输出本机预览，原型独立未改，未正式发布或部署NAS。完整服务迁移／回退、App回退、目标手机／NAS及其它验收继续；#89原始故障未复现、#78保持开放，#24/#33不关闭。

[安装与回退说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/library-first-preview.md)／[源码、原始记录和只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/plans/library-first/evidence/lf8-preview-package/README.md)。产物源码cf992025、证据4f82213，APK的SHA256为d87e98c70d4999b50165ce854f2e4f7156d25cc378f0431ed885f061c1cb9f87。旧／新包首次安装时间及数据目录相同，新PID启动26次GET、没有登录或自动流请求；深色开／相邻准备关保留。图包合成三图2/3实测，不冒充高分辨率长图包或真实手机验收。旧服务兼容可能按旧逻辑直接播放，完整新媒体库需要配套新服务。独立5556及8771/8772已归还，原四服务ID和运行状态不变；服务归档仅linux/arm64，正式NAS部署还需核对实际环境。

## PR #94：视频任务状态与真实旧数据升级回退

[草稿PR #94](https://github.com/ShiJiJS/video_viewer/pull/94)基于#92。服务源码b79da7b9、证据1b31995，正常runtime为preview.2，App仍是cf992025的正常release APK6，客户端生产源码未改、未重跑客户端全集。真实旧任务成功1/失败0却显示待核对，已登记#93并修正；旧JSON/回执不改，异常与部分成功保持原分类。最终15项新增检查在旧代码5失败/10通过，修正后相关21项、完整服务462项及Ruff/格式通过。

`accepted-1/2/3`三轮同一公开样本全部完成：2视频（可用1/回收1）、1标签2关联、原轮次2成员及3请求记录，正常启动迁移0004→0014，自动快照旧表相同；原凭据免口令，新媒体库无自动内容，旧任务已完成、原回执不变。UI新建标记标签后停机恢复完整基线，核对容器内版本/完整性/SHA，再启动原旧镜像，旧UI及原记录保留、标记消失。六个App PID、51成功图（另3基线/5诊断）、336输入只读复核通过；控制登录窗口单列，不冒充整份trace零登录。

首次cf任务问题、一次QEMU退出与一次旧容器首启报告0014而宿主恢复为0004的失败均保留，未计入最终三轮；后者原因未确定。最终驱动关闭SQLite连接，在原绑定目录和数据库文件内恢复内容，并先做容器侧核验。当前三轮通过不等于#78已修复。最终自有AVD关闭、11容器移除，原四服务ID/状态、上一阶段数据与媒体SHA未变。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/LF8-UPGRADE-ROLLBACK.md)／[固定源码、原始记录与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/evidence/lf8-upgrade-rollback/README.md)／[配套安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/library-first-preview.md)。本段补UP-01/02和SET-05明确组合；App回退包、真实手机/NAS、当前新服务配旧客户端完整终验、禁用根其它组合及其余原型验收继续。#89原始上传故障未复现，#78仍开放；原型1cbf605保持独立可移除，未正式发布或部署NAS，#24/#33/#32保持开放。

## 2026-10-28：App回退包与反复覆盖安装（PR #95）

最新阶段：[原签名App回退与反复覆盖安装 PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)。固定a3c7659a，配套新媒体库0.2.0-preview.2和旧界面0.1.4-rollback.2均code8、原Windows签名。旧界面窄适配保留新版偏好/多范围日志及凭据代次，未知v2备份任务保留并要求回新版核对；85旧版/兼容+14新版相关检查、双方analyze及正常release通过。独立Android36同一QEMU实际6→新8→旧8→新8→旧8→新8，五次install -r、首次安装时间/身份/数据目录保持、六次免口令冷启，新版零自动播放。旧UI主题/相邻准备修改后新版顺序/迁移标记保留；旧视频回收/菜单撤销完成，升回任务可核对；图包第2页纵向/两套标签保留。148输入及两包只读复核通过，22组原生截图；一容器/自有AVD已归还，原四服务及前阶段数据/媒体未动。配套服务仍b79da7b9 preview.2，原型1cbf605独立未改；未正式发布/部署，目标手机/NAS、500页高分辨率和其余终验继续，#78/#89与#24/#33保持开放。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/LF8-APP-ROLLBACK.md)／[固定构建、两轮实际安装与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/evidence/lf8-app-rollback/README.md)／[安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/library-first-preview.md)。本段只补UP-02的本机App回退组合。内部code相同可反复替换已在该AVD实测；不能覆盖code>8，后续版本需同步生成回退包。切换前先完成/核对管理任务，进行中或未知v2任务不交旧版接管。偏好扩展字段使用明确公开文件样本，再经真实UI写当前迁移标记；不把文件样本称为全由UI生成。原旧界面、播放器和API业务保留，属于附兼容存储的回退包，不是原Windows APK字节复刻。当前新服务配旧客户端只核对列明组合，完整旧功能/禁用根其它组合、目标手机/NAS和其它终验继续。
