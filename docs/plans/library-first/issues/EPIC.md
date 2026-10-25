## 目标

将现有 0.1.4+5 Android App 升级为已确认的「媒体库为中心、视频与图包分别管理」完整产品。用户于 2026-10-23 确认当前 `design/reference/library-first/` 原型方向并要求先确定框架、写规划和 GitHub issues。当前 LF0–LF2 已实现并验证，等待依赖 PR 合并；LF3 固定预览与原生兼容已通过完整 I2 两阶段首轮，仍待来源组合/重复验收；LF4 四入口、双类型媒体库与独立标签已接线，标签分页、跨页批选、图包名称和深列表稳定返回已补齐，剩余来源/错误组合仍在验证，LF5 真实阅读器和最近图包已接入，197项客户端/163项服务端检查通过，完整原生异常/大图验收待补，LF6 后端、卡片/阅读器整理及双类型回收站/跨页恢复已接入，客户端代码未变、271项与既有原生检查点保留；永久删除精确清单与逐页执行/恢复后端已接，当前264项服务端/Ruff通过；App双确认和原生验收、完整后台批次与安全存储重开待实施，历史图片失败仍待定位；LF7–LF8 待实施，尚未发布新版。

LF4最新检查点：独立视频标签分页、完整筛选范围跨页全选/排除与每1000项追加、图包名称与首50项外初选均已接入。`be7be51` 补齐图包深列表稳定返回、有限120项窗口及原位失败/取消重试；当前171项客户端测试/静态检查、43项定位/图包相关服务端回归/Ruff通过。同提交真实Android完整路径连续三轮通过（含360宽2倍字号）：73包完整筛选、编辑移出交集、实际503后邻居定位、前补与插入后位置保留。此前名称/标签分页/跨页选择三轮证据各自保留。证据随[LF4记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf4-media-library/docs/plans/library-first/LF4.md)提交；剩余来源/错误组合及旧流程回归继续验证，图包阅读/最近依赖LF5，LF4继续开放。

LF5实施中：[草稿PR #39](https://github.com/ShiJiJS/video_viewer/pull/39)已接入固定完整图包范围、逐包进度/偏好、实际首帧后的独立最近、只读回执和原生阅读器。最近图包按冻结历史行接线，列表/分页/全选/阅读共享来源和排序；修正分页尾部返回定位，媒体库筛选独立保留。当前完整197项客户端测试/静态检查及163项服务端测试/Ruff通过；`d8e3082`最近来源真实Android路径连续三轮通过（含360双倍字号），旧阅读器主路径三轮按`91f1112`独立保留，当前版本再完整回归一次通过。9024f88补齐单指翻页与双指缩放的实际分工，完整197项客户端回归通过，同实现原生操作专项三轮通过（含双倍字号及实际ADB返回），独立证据另行归档。aafccee新增真实图片503、两类进度回执、Android后台和整包标签固定范围恢复专项，同实现原生路径三轮通过（含双倍字号）；197项客户端回归补充无假时钟推进的生命周期保存断言。最近回收/恢复依赖LF6，其它错误码/连接与管理恢复组合、强杀和大图内存仍待补，见[LF5记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5.md)。

LF6实施中：[草稿PR #40](https://github.com/ShiJiJS/video_viewer/pull/40)已接逻辑整包整理、固定范围推进与准确撤销，以及设置内视频/图包独立回收站、24项分页、完整跨页全选排除和每批最多1000项恢复。每批先保存再POST，未知结果只读核对原回执，不自动重放。功能524e89f/排布9de2ebb，记录86de91d：全量271项客户端/静态检查、本轮30项服务端专项/Ruff通过；生产后端未改，完整182项服务端基线保留。Android回收站三轮44/49/46秒通过，覆盖首次读取503、27包跨页选择、恢复受理后503/GET回执、阅读进度/偏好/标签/最近和视频隔离，81张合成图片六阶段SHA相同。阅读连续整理每轮8次的三轮67/68/67秒通过；大字号排布收尾另跑271项和360双倍字号完整原生45秒流程。Slider异步弹层语义断言已有确定性红绿回归并修正，SDK按原哈希恢复；历史两次下一包图片失败仍未定位，不据复跑称已修复。源码SHA、APK哈希、日志、轨迹与截图见[LF6记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6.md)及[回收站证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-trash-client/README.md)。限定图片清单永久删除、整份多批次计划持久化/统一任务、实际安全存储强杀重开与DEL/REC/UI完整验收继续实施；当前离页停止未提交批次，不能把每批日志当完整后台续作。#31保持开放，PR保持Draft，原型继续隔离，正式8760/真实NAS未改。

LF6清单准备检查点 **bdbd741**（记录d138fed）：新增持久化后台精确图片清单，逐包核对目录身份、图片签名/SHA和树成员，附件/独立范围保留。新增图片、替换/链接/越界、准备中的附件/授权/回收状态变化均使清单失败；部分包失败时不产生整份可确认摘要。15分钟服务端期限、原请求只读回执、文件清单分页及queued/interrupted冷重建已接入，历史清单不可确认。完整214项服务端/Ruff通过（新增32项）；0009非空管理数据升级0010逐表保留。8万条合成持久化明细约27.9MB，摘要HTTP读取Python新增分配峰值65,296字节，属于摘要内存专项，不是实际扫描或删除性能。仅声明pack_purge_preview，尚无实际永久删除执行路由或App双确认，新接口未做Android UI验收；客户端沿用上一检查点，不混称本次原生通过。[执行契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6-PURGE-DESIGN.md)与[清单证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-plans/README.md)已提交；继续逐页执行、部分失败/中断核对和App双确认，#31与PR #40保持开放/Draft。

LF6执行后端 **5e89a1a / dd2dcf3**（记录d3315d2）：严格布尔确认绑定plan/digest/request，单计划只消费一次，逐图片认领后SHA/身份复核、持久化阶段和空目录非递归清理已接入。新增/替换/目录授权变化拒绝扩大范围，附件和冲突内容保留。已归档页退出可读清单，剩余可恢复，未知待核对不计成功，重试不重复已完成页或计数。永久删除受理使其旧8秒逻辑撤销失效，不影响无关最新撤销。完整264项服务端/Ruff通过（新增50项）；真实TCP/HTTP的两条SIGKILL路径各3轮通过，另有10阶段合作式中断冷重建。首轮全量发现的清单摘要/任务状态跨SELECT竞争已用同步屏障稳定复现并修正为同一SQL读取，这与历史两次下一包图片失败不同，后者仍未定位。新图出现旧路径获得新ID，不继承旧标签。[执行契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6-PURGE-DESIGN.md)及[源码SHA/原始日志](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-execution/README.md)已提交；本轮未改客户端，尚未接App双确认/部分删除提示/任务结果，也未做新原生验收，App永久删除能力标志暂不开放。正式8760/真实NAS/原型未改，未发布升级APK。继续App接线、完整后台计划、LF7备份/历史化/代次与LF8验收，#31和PR #40保持开放/Draft。

这是后续升级，不覆盖 #1 的历史 V1 规格，也不把 #23 仍未完成的目标环境验收标记为已完成。

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

当前 PR：[LF0 #34](https://github.com/ShiJiJS/video_viewer/pull/34) → [LF1 #35](https://github.com/ShiJiJS/video_viewer/pull/35) → [LF2 #36](https://github.com/ShiJiJS/video_viewer/pull/36) → [LF3 草稿 #37](https://github.com/ShiJiJS/video_viewer/pull/37) → [LF4 四入口与媒体库草稿 #38](https://github.com/ShiJiJS/video_viewer/pull/38) → [LF5 阅读会话草稿 #39](https://github.com/ShiJiJS/video_viewer/pull/39) → [LF6 逻辑整理草稿 #40](https://github.com/ShiJiJS/video_viewer/pull/40)。前序阶段实现完成不等于整体原型验收完成，子任务等待对应依赖合并。

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

无压缩包直读、单张图片标签/删除、AI标签、离线下载、自动文件夹归档、多用户或新微服务。当前开发与故障验证使用隔离实例和合成媒体，尚未部署 NAS 或发布升级 APK；正式交付按 LF8 验收与迁移流程推进。

## LF6 App永久删除：最新检查点（2026-10-25）

[#31](https://github.com/ShiJiJS/video_viewer/issues/31) / [Draft PR #40](https://github.com/ShiJiJS/video_viewer/pull/40)：App已接精确图片清单、勾选后明确确认、受保护命令记录、未知响应只查询原请求、逐项结果与原任务重试；部分条目显示已删/剩余数量。每批最多1000包分别核对，剩余选择保留；附件保留。

实现2d97cc9、原生检查c55e95c，代码/方案/证据已推送。293项客户端/analyze、265项服务端/Ruff通过；Android关键流程连续3轮通过（含360双倍字号，均51秒），实际删除仅触及确认的3张图片，27份附件及其它图包哈希保持。模拟器退出和协议修正前的失败均单独保留，不计通过。

[App设计与原型语义差异](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6-PURGE-CLIENT-DESIGN.md) / [原始证据与验证边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-client/README.md)。冻结原型继续独立且未改，正式NAS未部署，未发布升级APK。

LF6仍实施中：下一步统一任务与整份多批次计划持久化/续作；Android安全存储强杀重开、备份v2/管理恢复、真机/NAS、完整原型一致性和历史图片失败定位仍按LF6–LF8推进，不关闭阶段或总任务。

## LF7 统一任务：最新检查点（2026-10-25）

[Draft PR #41](https://github.com/ShiJiJS/video_viewer/pull/41) 基于 #40，源码92d9b15：设置增加操作任务，真实服务按类型/状态和24条分页，逐项显示结果；本机未确认图包/视频/备份按原请求只读核对，404不重发，旧回执不清除新命令。原备份下载校验SHA，取消保存保留记录。316项客户端、271项服务端/Ruff及analyze通过。固定源码92d9b15连续三轮Android通过（390普通、360双倍字号、390普通）：81张图片哈希不变，任务中心请求全部GET，同一原备份下载两次。[原始证据与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-maintenance-tasks/docs/plans/library-first/evidence/lf7-tasks/README.md)已归档。

整份多批次持久计划、完整设置审计、服务端默认值迁移、v2/v1转换与前快照、安全存储强杀及LF8完整原型验收继续推进。#31、#32和总任务保持开放；冻结原型独立且未改。

## 整份恢复服务端检查点（2026-10-25）

[Draft PR #42](https://github.com/ShiJiJS/video_viewer/pull/42) 基于 #41；实现3416b1e、扫描并发修正6880055。0012持久父计划/完整成员/唯一子批次，统一包预约，最多1000项逐批后台推进；重启先核对同一子操作，停止仅取消尚未开始成员。任务入口显示父计划和原成员分页。

当前294项服务端/Ruff通过：1003项两批，停止/状态变化/并发/历史/迁移，以及三个边界各三次真实HTTP/SIGKILL。启动扫描并发已用两个固定交错复现并修正；进程验收等待扫描完成再核对全部原ID/代次与文件哈希。[设计与剩余范围](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-durable-restore/docs/plans/library-first/LF7-RESTORE-PLAN-DESIGN.md) / [原始证据及失败诊断](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-durable-restore/docs/plans/library-first/evidence/lf7-restore-plans/README.md)。

App尚未替换旧循环，不能据服务端通过关闭DEL-04/06。继续原计划安全存储、响应丢失GET、离页/Android强杀重开、任务中心停止和原生验收。永久删除剩余选择持久化、v2备份及历史化、完整设置/默认值、真机NAS与全原型验收仍待推进。本阶段未改客户端/冻结原型/真实NAS，未发布APK；#31、#32与总任务继续开放。
