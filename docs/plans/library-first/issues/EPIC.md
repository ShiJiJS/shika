## 目标

将现有 0.1.4+5 Android App 升级为已确认的「媒体库为中心、视频与图包分别管理」完整产品。用户于2026-10-23确认独立的 `design/reference/library-first/` 原型方向。LF0–LF7已有分阶段实现与证据，LF8原型一致性收口进行中；最新[Draft PR #76](https://github.com/ShiJiJS/video_viewer/pull/76)修复图包瞬断重试并完成500页/大图三轮原生验证，646项客户端与开发签名release构建通过；#75的移除参考目录构建隔离证据保留。原型仍独立保留且可移除，当前结果及未完成范围见[验收台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-long-pack/docs/plans/library-first/RESULTS.md)。仍需依赖PR合并、完整同版验收、目标手机/NAS及原签名升级验证，尚未发布新版。

## 历史阶段记录（各自固定版本）

LF4阶段检查点：独立视频标签分页、完整筛选范围跨页全选/排除与每1000项追加、图包名称与首50项外初选均已接入。`be7be51` 补齐图包深列表稳定返回、有限120项窗口及原位失败/取消重试；当前171项客户端测试/静态检查、43项定位/图包相关服务端回归/Ruff通过。同提交真实Android完整路径连续三轮通过（含360宽2倍字号）：73包完整筛选、编辑移出交集、实际503后邻居定位、前补与插入后位置保留。此前名称/标签分页/跨页选择三轮证据各自保留。证据随[LF4记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf4-media-library/docs/plans/library-first/LF4.md)提交；剩余来源/错误组合及旧流程回归继续验证，图包阅读/最近依赖LF5，LF4继续开放。

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
## 整份恢复 App 与安全存储强停（2026-10-25）

[Draft PR #43](https://github.com/ShiJiJS/video_viewer/pull/43) 基于 #42：实现eba2541，最终布局e58864e。当前服务上App不再循环提交1000项，完整选择确认后只提交父计划、受理后可离页；回收站/任务中心能找回原恢复和停止请求。安全日志写盘失败不提交，未知/404保留并只GET，停止/失败/成功计数分开。

330项客户端、294项服务端/Ruff及analyze通过。固定最终源码真实Android连续三轮（390普通、360双倍字号、390普通）：宿主强停活进程并证明PID消失，服务端在App缺席时恢复27包/14个唯一批次；新PID通过真实SecureStorage找回原请求，仅GET原恢复回执。另一份停止响应丢失后只GET原停止ID，2包恢复/25包未执行，原包ID和81张图片哈希保持。第一段预期被强停，不算测试通过；必须第二段实际通过及独立轨迹核对，整轮才通过。

[App设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-restore-client/docs/plans/library-first/LF7-RESTORE-CLIENT-DESIGN.md) / [原始证据、源码SHA与失败诊断](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-restore-client/docs/plans/library-first/evidence/lf7-restore-client/README.md)。实际发现并修正SnackBar Hero冲突和大字号提示挤掉列表，修正后重新固定源码三轮；旧轮次/旧布局不混算。

继续永久删除剩余选择持久化、v2备份与父/子/成员历史化、完整设置/默认值迁移、其它命令强停组合、旧原生用例迁移及LF8全原型/真机NAS。冻结原型独立且未改，未部署NAS或发布APK；#31、#32与总任务保持开放。

## 永久删除剩余选择与逐批核对（2026-10-25）

[Draft PR #44](https://github.com/ShiJiJS/video_viewer/pull/44) 基于 #43，应用实现19ef6e5。完整选择已写入原安全日志，回收站及操作任务都能找回；打开只读本机选择，不准备或提交删除。每批仍需重新核对精确图片清单并明确确认，未提交内容不自动执行。

选择与本批命令一次落盘后才POST；写盘失败不发，未知/404保留原命令并只GET，明确未受理的批次恢复到未提交选择。旧确认/旧移除不能消耗后来批次，移除本机选择不清已提交命令；本机管理恢复将选择标为历史，跨设备权威代次和完整v2管理历史化仍继续。

完整345项客户端/analyze通过。1027组件流程证明明确删除1000后剩余27保持，新批确认框默认关闭，取消/离页不追加删除；覆盖390普通/360双倍字号。真实Android增加取消后保存/重开入口检查，并保留响应丢失、部分删除、原任务重试和27附件哈希检查；具体轮次与边界见[证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-purge-selections/docs/plans/library-first/evidence/lf7-purge-selections/README.md)。原生此用例仍使用内存命令/凭据，不能当作永久删除真实SecureStorage强停证明。服务端生产源码未改，294项基线沿用上阶段，仅调整隔离测试夹具检查点。

[选择设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-purge-selections/docs/plans/library-first/LF7-PURGE-SELECTION-DESIGN.md)。继续永久删除等其它命令的真实安全存储强停组合、v2/v1备份与父/子/成员历史化、完整设置/默认值迁移、旧原生用例迁移及LF8全原型/真机NAS。冻结原型独立未改，未发布APK或修改真实NAS，LF6/LF7及总任务保持开放。

## 2026-10-25：真实1003包与安全存储强停补证（PR #45）

测试源码 b8c823b，Draft PR #45：https://github.com/ShiJiJS/video_viewer/pull/45 ，基于 #44。实际扫描1003个合成图包，每包1张图片和1份附件；明确确认第一批1000，未知响应后由宿主强停活PID，服务在App缺席时完成，新PID从生产安全存储适配器恢复连接与原命令，只GET原回执。剩余3包从任务入口重新核对，确认框默认关闭，取消不再提交。

固定源码完整三轮通过（360双倍字号283.58秒、390普通328.94秒、390普通334.18秒）。独立verify.py核对原1003ID分区、精确1000删除路径、1003附件及3张余图SHA、单次永久删除POST、原回执GET及实际分页。首段预期非零强停不算测试通过；完整证据见 docs/plans/library-first/evidence/lf7-purge-secure-restart/。

本轮只增加测试/夹具/证据，应用和生产服务源码未改；analyze、夹具Ruff和编译通过，345客户端/294服务端为前阶段基线。其它来源/命令及部分失败重试强停组合、v2/v1备份与完整历史化、全设置/默认值迁移、历史图片失败根因及LF8完整原型/真机NAS/签名发布继续推进；冻结原型独立未改、未改8760/NAS、未发布APK，本issue保持开放。

## 服务端默认值与旧本机设置迁移（2026-10-25，PR #46）

[Draft PR #46](https://github.com/ShiJiJS/video_viewer/pull/46) 基于 #45，实现459870b。默认播放顺序接入当前服务的revision/idempotency管理数据，首次从旧轮次采纳后与轮次独立；新范围进入前读取最新值。图包阅读偏好直接复用既有reading-defaults接口，已读包保留独立偏好。旧本机顺序不自动上传，明确选择并保存后迁移，决定按endpoint+server_id本机隔离；冲突要求重读，未知只GET原请求，取消草稿不写。

完整354项客户端、302项服务端、analyze及变更Ruff通过。固定源码Android正式三轮通过（390普通143.51秒、360双倍字号125.56秒、390普通109.66秒）；当前视频范围完整响应/已读包保持，未读包继承新默认，App/Repository及本机文件重建能读回迁移决定。每轮2次明确PATCH/1次原回执GET，81张图片SHA不变，独立verify.py复核。此次不是进程强停，不覆盖三个视频入口全部组合或v2恢复。首轮服务端环境漏传共享内存限制，按64MiB完整重跑通过；原始失败和ADB viewport超时均单独保留，不混算成功轮次。

[契约与设置缺项审计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-managed-defaults/docs/plans/library-first/LF7-DEFAULTS-DESIGN.md) / [完整证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-managed-defaults/docs/plans/library-first/evidence/lf7-defaults/README.md)。旧v1拒绝遗漏明确保存的新默认值，合法v1恢复重建隐式默认；v2仍未完成。

下一步先补目录类型/启停的实际App控件（当前新建仍固定视频）与图包缺失管理，再继续v2类型化全数据图/根映射/前快照/完整替换/跨设备权威代次和历史只读、有界传输、真实文件选择器，以及其它命令/来源强停、历史图片失败根因、全原型暗色横屏、真机NAS与原签名升级。冻结原型独立未改，未改正式8760/NAS、未发布APK，LF7和总任务保持开放。

## 2026-10-25：目录类型与图包缺失管理（PR #47）

[Draft PR #47](https://github.com/ShiJiJS/video_viewer/pull/47)基于#46。真实设置表单已接视频/图包类型、启停及冲突保留；缺失内容按类型24条分页。0013持久父任务和固定成员只清失效管理元数据，保留源字节、墓碑和历史会话；后来新增缺失不进入原范围。执行必须匹配最近成功扫描的根目录身份，同路径替换、离线、停用、返回或占用均保留。原request_id先写安全日志，未知/404重开只查询原请求，不自动重复提交。

实现4e569ad，目录身份修复ed60bc9，当前宿主截图守卫59f78b6。369项客户端/analyze/Ruff及15项新增服务端针对检查通过。服务端全量316通过/1项旧视频扫描30秒超时，同一用例不改码独立重跑13.54秒通过；不称作一次全量317通过。原生曾遇到QEMU崩溃、连接异常和Launcher/System UI无响应，均保留诊断。固定59f78b6正式三轮308.89/138.03/197.17秒全部退出0，27检查点的窗口/请求/文件/数据库及源码独立核对通过；每轮保留25、清24/返回1、2次明确POST/1次原GET，原视频范围保持。App/Repository同进程重建不是强停；新建根未扫描文案及任务编号截图缺字/裁剪继续视觉复查，完整UI验收不关闭。

[设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-roots-missing/docs/plans/library-first/LF7-ROOTS-MISSING-DESIGN.md) / [实际结果与诊断](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-roots-missing/docs/plans/library-first/evidence/lf7-roots-missing/README.md)。仍需v2/v1转换、全任务图/回执和设置、根映射/前快照/完整替换/权威代次与历史只读、有界传输和系统选择器，以及其它强停组合、历史图片失败、全原型暗色横屏/手势、真机NAS与原签名升级。原型保持独立且未改，未动8760/NAS、未发布APK；LF7和总任务保持开放。


## 2026-10-25：备份 v2 文件模块与 v1 校验转换（PR #48）

[Draft PR #48](https://github.com/ShiJiJS/video_viewer/pull/48)基于#47，最终文件模块源码94f8dc6。已实现逐记录v2文件、在线一致快照、全部33张管理表的类型/主外键/计数校验、多个历史图及私有磁盘暂存；凭据、媒体字节、缩略图和扫描身份缓存排除。v1先沿用原校验，再转换为同一暂存形式并保留原文件SHA/旧范围及默认值。扫描暂存只在私有快照排除，若存在用户/任务关联则等待同步，不能借CASCADE丢失管理状态。

最终29项文件检查通过，19项既有备份/进程故障回归通过，Ruff和编译通过。真实HTTP夹具生成全部33表非空关联，独立逐管理字段核对；18,000行、每行2048字符生成40,947,094字节文件，独立文件stat/SHA及原生SQLite核对通过，Python分配峰值2,957,764字节。该量测不代表总RSS/App性能；旧v1兼容解析仍保留原最多256MiB整份JSON界限。详见[设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-v2/docs/plans/library-first/LF7-BACKUP-V2-DESIGN.md)与[原始证据/源码SHA](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-v2/docs/plans/library-first/evidence/lf7-backup-v2-archive/README.md)。

当前仅文件/校验模块，尚未发布backup_v2能力或注册新API。只读完整历史查询、根映射/空映射/物理删除真相、前快照与原子完整替换、跨设备写入代次、任务协议、App流式传输/真实系统选择器继续实施。其它强停组合、历史图片失败根因、全原型暗色横屏/手势、真机NAS与原签名升级继续；原型独立未改，未修改SDK/正式8760/NAS或发布APK，LF7/#32及总任务/#24保持开放。


## 2026-10-25：完整关联的只读历史查询（PR #49）

[Draft PR #49](https://github.com/ShiJiJS/video_viewer/pull/49)基于#48，实现ac4f4d1。完整替换前可准备独立历史包，保留全部关联和相同ID的新旧图；复制的实际字节再次核对原摘要，完整索引/持久化后禁止覆盖地原子发布。任务标量和成员分页、8类原回执及明确历史标记已实现；整份恢复执行批次仍可按ID查，最新来源/活动图优先，类型筛选不会回退旧身份。完整历史图可再次导出，不写当前库或源媒体，不注册启动队列。

固定源码联合66项检查通过（12历史、29文件、6任务分页、19既有备份/进程回归），Ruff和编译通过。真实27成员恢复/永久删除、视频/缺失/阅读/设置回执和输入/源文件SHA核对通过；发布前后各一次真实SIGKILL，前者无正式目录，后者冷重开完整30条任务/原回执。18,000行实际文件41,113,806字节，历史准备/分页Python峰值2,111,481字节；不是总RSS/App性能。详见[设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-history/docs/plans/library-first/LF7-BACKUP-HISTORY-DESIGN.md) / [固定源码、诊断和证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-history/docs/plans/library-first/evidence/lf7-backup-history/README.md)。

准备历史包尚不会更改当前服务正式历史；恢复父任务中的正式引用/孤立准备清理、预约/前快照/根映射与物理真相/原子完整替换/权威代次、旧命令拒绝和公开路由适配、App有界传输/系统选择器继续接线。历史包SIGKILL不代表完整v2恢复提交或断电证明，显式单回执仍可能较大。公开backup_v2能力保持关闭；其它强停、历史图片失败根因、完整原型/暗色横屏/手势、真机NAS及原签名升级继续。冻结原型独立未改，未改SDK/正式8760/真实NAS或发布APK，LF7/#32和总任务/#24保持开放。


## 2026-10-25：恢复事务代次与旧写入隔离（PR #50）

[Draft PR #50](https://github.com/ShiJiJS/video_viewer/pull/50)基于#49，实现403b5a7。0014给令牌绑定签发代次；info/登录/已鉴权响应提供当前权威。显式请求头或旧令牌缺省代次在实际Database.write检查，RLock和SQLite BEGIN IMMEDIATE持有到提交，避免受理后恢复或另一连接在检查与DML之间轮换。实际v1恢复在替换事务内生成并flush新代次；旧令牌仍可GET原任务/回执及前快照，旧写入409且不执行，自己退出独立。代次/凭据不进管理备份，v2逻辑图仍0013，公开backup_v2关闭。

固定源码服务端全集375项通过（新增17项），全量Ruff/编译通过。真实HTTP两个受理后恢复交错、锁内顺序/另一连接、令牌撤销/旧上传/严格头/回滚和13→14迁移验证通过；两处真实v1 SIGKILL确认提交前旧数据/旧代次可见、重启后一起更新、旧POST拒绝/原GET可查/源媒体保持。见[设计](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-management-authority/docs/plans/library-first/LF7-AUTHORITY-DESIGN.md) / [固定源码、原始证据及诊断](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-management-authority/docs/plans/library-first/evidence/lf7-authority/README.md)。

本轮是服务端隔离，App尚未接不可变代次、旧安全日志/剩余选择历史化和迟到响应失效；旧App恢复后继续写需重新连接。完整v2预约/前快照/根映射与物理真相/原子替换/正式历史引用及孤立清理、历史路由与任务协议、App有界传输及系统选择器继续；现有v1的SIGKILL不代表新v2完成。其它强停、历史图片失败、完整原型/暗色横屏/手势、真机NAS和原签名升级继续。冻结原型独立未改，未改SDK/正式8760/NAS或发布APK；LF7/#32及总任务/#24保持开放。

## 2026-10-25：App 管理代次与原请求历史分册（PR #51）

[Draft PR #51](https://github.com/ShiJiJS/video_viewer/pull/51)基于#50，固定实现aa48c9e。App按不可变服务权威代次发送请求，管理恢复后替换连接、使旧网关与读取失效并免口令返回媒体库。六类本机意图保留原分册；历史选择不能继续删除，原GET404不擦记录，写盘回执未知先重读再合并，原POST不重发；成功的旧恢复/停止回执也保留，不走当前结算。旧服务回退/人工重连及本机已确认恢复分配本机代次。真实原生检查发现并修复自动重连后仍停连接表单的问题。

最终客户端全集398项、analyze、全量服务端Ruff和新增夹具/runner编译通过；生产服务未改，375项服务端沿用#50。固定源码原生三轮通过：390普通运行中实际v1恢复、360双倍字号及390普通两次真实SecureStorage强停重开。后两轮确认旧PID消失后才在App缺席时恢复，新PID无需再登录；主动强停首段非零与Flutter附带终结异常如实保留，实际通过的是重开段。独立核对12个窗口/截图检查点、每轮27源文件SHA、五类旧回执只有GET404、App仅一次登录及唯一新代次导出POST；旧安全日志与27未提交选择保留。见[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-client-authority/docs/plans/library-first/LF7-CLIENT-AUTHORITY-DESIGN.md) / [固定源码、原始日志及独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-client-authority/docs/plans/library-first/evidence/lf7-client-authority/README.md)。

这是实际v1恢复后的客户端隔离；图包本机意图使用合成未受理ID，不代表图包物理操作或完整v2恢复。当前原GET查不到就保留未知，完整v2协调器/根映射/物理真相/前快照/原子替换/正式历史引用与公开历史路由、App有界传输及系统选择器继续，backup_v2仍关闭。其它强停组合、历史图片失败、完整原型/暗色横屏/手势、真机NAS与原签名发布继续。冻结原型独立未改，SDK/正式8760/NAS及发布APK未变；LF7/#32和总任务/#24保持开放。


## 2026-10-25：完整管理恢复协调器（PR #52）

[Draft PR #52](https://github.com/ShiJiJS/video_viewer/pull/52)基于#51。已接v2/已校验v1转换、持久维护预约、可下载恢复前快照、明确/null根映射、实际文件只读核对、33表原子完整替换、正式历史引用与新权威代次。当前已明确恢复的内容不受旧回收标记覆盖，实际永久删除页ID不复活；导入未完成任务只读不重放。历史按原epoch/graph定位父子成员和8类回执，连续恢复保留本机历次备份控制回执与原文件。

固定最终源码0c841f3（实现04d9834、初始化修复8193272）。服务端全集396项（433.47秒）通过，新增21项纳入全集；全目录Ruff及111文件编译通过。另行固定源码4项进程/网络复跑32.01秒通过，三处真实SIGKILL均正确恢复或保持已完成，媒体SHA不变。实际40,949,448字节网络上传/下载/完整恢复、18,000行独立SQLite核对通过，服务端Python分配峰值5,634,876字节；配置64MiB，默认限制仍32MiB，不代表总RSS或Android性能。33表非空关联、19表逐字段保持、连续两次恢复/原epoch严格读取、旧POST拒绝/冷启动不重放、回滚/预约/坏文件/模拟中止/磁盘及历史图变化均有检查。完整失败和中止诊断单独保留，不累加成最终通过数。

[恢复契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-restore/docs/plans/library-first/LF7-RESTORE-V2-DESIGN.md) / [固定源码、原始日志及核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-restore/docs/plans/library-first/evidence/lf7-backup-restore/README.md) / [下一步App文件接线](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-backup-restore/docs/plans/library-first/LF7-APP-ARCHIVE-PLAN.md)。初始化前SQLite写入和旧能力清单断言在全量检查中发现并修正；默认播放设置GET已改为只读。客户端398项及原生三轮沿用#51，本轮未改App或重跑，不作为v2 App验收。

App流式文件网关、真实系统选择器/取消、两类统计/分页根映射/确认、历史页面与原epoch网关继续；backup_v2仍关闭。旧专用永久删除清单/页明细等GET尚需审计，通用历史入口不代表所有页面完成。其它强停组合、历史图片失败、暗色/横屏/手势与目标设备/NAS及签名升级继续。冻结原型独立未改，未改SDK/正式8760/NAS或发布APK；LF7/#32及总任务/#24保持开放。

## 2026-10-25：App流式管理文件与原图历史（PR #53）

[Draft PR #53](https://github.com/ShiJiJS/video_viewer/pull/53)基于#52。最终App/验收源码38ae54a，服务端树ff9699c不变：v2文件以私有文件ID、长度、SHA和所属服务代次传递，HTTP与Android SAF按块处理并协商真实上限。设置中分两类统计、24根分页映射、跨页草稿、默认关闭的完整替换确认和直接恢复前快照入口已接通。任务详情支持原导出/原快照流式下载，回执按原epoch、详情/成员按原graph；旧v1未知意图不改协议重发。

433项客户端与398项服务端全集通过；全目录Ruff、analyze和127个Python文件编译通过。[设计与兼容边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-files/docs/plans/library-first/LF7-APP-ARCHIVES-DESIGN.md) / [固定源码、原始轨迹及独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-files/docs/plans/library-first/evidence/lf7-archive-files/README.md)。独立视觉复核发现大字号目标路径末尾不可见，已自然换行并复核；临时连接切换异常、当前快照查询误用旧回执通道及测试脚本滚动目标均已修正，诊断日志分开保留。

原生App三轮（360双倍、390普通、390普通）使用实际服务、生产安全日志适配器与私有磁盘，27根真实分页、一次恢复POST、免口令新代次、前快照原文件与源媒体SHA保持均独立核对。真实系统选择器另跑三轮40MiB取消/保存/重新选取/超限清理/主动取消；二者分开记证，不宣称一条大文件恢复整路或Android内存测量。App路径使用私有文件选择/保存适配器，不冒充系统选择器；没有把App重建当强停。

生产backup_v2仍关闭，8762只读源码夹具独立测试开放；没有改SDK、正式8760/NAS或发布APK。v2真实强停/新PID、完整历史专用清单与页细项接线、其它命令/来源组合、历史图片失败、暗色/横屏/手势、目标手机/NAS和原签名发布继续。原型树保持1cbf605且独立可移除；LF7/#32及总任务/#24保持开放。

## 2026-10-25：v2 App 三处真实强停与原日志重开（PR #54）

[Draft PR #54](https://github.com/ShiJiJS/video_viewer/pull/54)基于#53，固定源码2839c5d。真实v2完整替换在snapshot_written、after_replace_before_commit、restore_committed三个服务位置扣留202，安全日志先落盘；宿主强停活跃PID并确认消失后，服务在App缺席时完成同一任务，新PID免口令自动重连新代次。六条旧本机意图、原私有文件和两个真实受理的图包任务/原graph成员都保留；重开只GET和既有启动扫描，不重发原写入。实际系统快照保存取消后不结算旧记录，历史未提交选择不能继续删除。

固定源码三轮（360双倍字号115.47秒、390普通79.17/81.29秒）通过，164份manifest输入已入库并独立核对；首段有意强停的非零退出和开发失败日志分开保留。analyze/Ruff/Python语法及24项服务端针对检查通过。App/服务端生产树未改，433/398项全集沿用#53且本轮未重跑；这里不是40MiB全路恢复、Android内存或整机断电验证。[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/LF7-ARCHIVE-RESTART-DESIGN.md) / [固定源码、原始日志与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/evidence/lf7-archive-restart/README.md)。

接下来继续历史专用永久删除精确清单/逐页结果及只读页面（原graph绑定、有界分页、不得借用当前投影或执行/结算接口），然后其它命令/来源强停、历史图片失败、暗色/横屏/手势、目标设备/NAS和原签名发布。生产backup_v2仍关闭；原型树1cbf605独立未改，未改SDK/正式8760/NAS或发布APK。LF7/#32、总任务/#24保持开放。

## 2026-10-26：原历史删除清单与逐项结果（PR #55）

[Draft PR #55](https://github.com/ShiJiJS/video_viewer/pull/55) 基于 #54，固定源码 `cabbc68`，证据提交 `0e0c1a5`。设置→操作任务→历史详情现可查看原确认清单、包内精确文件及永久删除的原图片/目录结果。三个认证 GET 绑定原 graph、父任务、计划与包条目；缺失或无效关联不退回当前库。文件 manifest 在 SQLite 内分页，App 专用网关没有执行、重试删除或结算能力，旧服务及缺失原图明确说明。

原生隔离8763真实扫描27包/153图，0101.png权限失败后实际126图已删、27图未完成；完整恢复后读回原历史。27包末3包、127图末页、54项目录、查询503保留原页再同GET重试及原预览入口均通过。固定源码三轮（360双倍字号64.96秒、390普通55.14/58.00秒），21张实际窗口截图、54份剩余源文件、原历史SQLite与三份真实安全日志前后核对；274份manifest输入已入库并独立校验。Paper比例延续既有页面，两尺寸目录结果及“图包根目录”文案复核通过。

完整客户端451项、服务端402项、analyze、Ruff lint和132份Python语法检查通过。服务端全集启动于9199f31、客户端全集于619033c，其完整服务端/客户端lib及test树均与固定源码相同。Ruff format继承23份、Dart format继承2份既有文件，未误报全量格式通过。实际43,806,720字节SQLite/18,000条manifest的分页Python分配峰值2,550,992字节，不能当作进程RSS、Android内存或NAS性能。首次Docker未加仓库规定shm参数的401通过/1失败、原生定位/等待失败和旧源码成功均单独留存。

[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/LF7-PURGE-HISTORY-DESIGN.md) / [原始证据与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/evidence/lf7-purge-history/README.md)。本段补齐BAK-03、SET-05、DEL-04/06的历史读取部分；其它命令/来源强停、历史图片解码/资源不可用、全原型暗色/横屏/手势、目标手机/NAS及原签名发布仍继续。生产backup_v2仍关闭，冻结原型树1cbf605独立未改；未改正式8760/NAS/SDK或发布APK。LF7/#32及总任务/#24保持开放。

## 2026-10-26：失败末张与横屏错误操作（PR #56）

[Draft PR #56](https://github.com/ShiJiJS/video_viewer/pull/56) 基于 #55，固定源码 `e68f487`，证据提交 `fc97f17`。原型 advance(1) 越过末张会进入 finished；App 原来把“跳过这一张”截回失败末张，且禁用了末张“下一张”。现已接到原生现有本包末尾页，可返回末张/来源，只有明确点击下一包才切换原固定范围；失败图片没有首帧，不写opened、最近、进度或完成状态。

沉浸中到达末尾显示工具，返回动作在黑色画布用白色保持可读。真实844横屏发现17像素溢出，失败/末尾区改为短视口可滚动，保留字体和操作。五项真实HTTP 404/HTTP200非图片解码及完整阅读路由检查回放旧生产代码全部失败，修正后通过。

完整客户端456项、analyze和新夹具/脚本Ruff lint通过。客户端全集在bc3c9fb执行，lib/test树与最终源码相同，最后仅改取证滚动；服务端生产树未改，402项全集沿用#55且本段未重跑。固定源码三轮（360双倍字号37.84秒、390普通36.09秒、844横屏38.74秒）通过，18张实际前台截图、六张源PNG前后SHA、原始轨迹及独立SQL投影保存，253份manifest输入已复核。SQL证实异常包没有progress行、recent只有手动进入且真实显示首帧的正常包。旧源码成功、17像素溢出、测试等待/取证偏移等开发记录单独保留。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/LF5-IMAGE-ERROR-DESIGN.md) / [固定源码及证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/evidence/lf5-image-errors/README.md)。本段补PKG-03、READ-01/02/04/05、UI-04/05的失败末张路径，不关闭整项。其余图片错误码/连接恢复/迟到图片、500页4K/8K性能、全原型与目标手机/NAS、原签名发布仍开放；本段使用MemoryCredentialStore，不作为强杀/安全存储证明。生产backup_v2仍关闭，冻结原型树1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24继续开放。

## 2026-10-26：按实际点中的可见末张跳过（PR #57）

[Draft PR #57](https://github.com/ShiJiJS/video_viewer/pull/57) 基于 #56，固定源码 `07d1cad`，证据提交 `92f08b8`。纵向视口顶部仍在倒数第二张时，可以点击下方可见的失败末张。旧逻辑按顶部index拒绝该点击；现按所点图片进入原末尾页，不自动换包，不把失败图片记成首帧或完成进度。

新真实HTTP组件检查在旧逻辑失败，修正后与原五项图片检查共6项通过；完整客户端457项、analyze及夹具/脚本Ruff lint通过。服务端生产代码未改，402项全集沿用#55且本段未重跑。原生390×844普通字号三轮59.20/39.59/38.89秒，顶部index=1、点击图片index=2、比例约70.94%，关键点击没有先滚动对齐；进度前后完整对象相等，包含revision与更新时间，返回原失败末张、退出重开恢复原页/比例，明确下一包才推进。独立SQL仍是上一张真实图片、未完成。

另按同源码跑既有末张/损坏图片844横屏回归一次35.93秒。三轮加兼容回归共21张实际窗口截图、6张源图前后SHA、原始HTTP与SQL投影已保存；119份manifest输入独立复核通过。普通字号三轮不冒充其它视口组合或安全存储强杀验收。

[核查与修复说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/LF5-VISIBLE-PAGE-SKIP-AUDIT.md) / [固定源码与证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/evidence/lf5-visible-page-skip/README.md)。本段补READ-02/04/05与PKG-03的明确组合，不关闭整项。接下来推进整体原型对照；其它异常/连接恢复/迟到图片、500页4K/8K性能、目标手机/NAS及原签名发布仍开放。生产backup_v2仍关闭，冻结原型1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24保持开放。
## 2026-10-26：共享比例与原型收口台账（PR #58）

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)基于#57。固定App与最终原生源码a9da395，证据提交6b71cd1：两类库统一搜索55dp/输入42dp/文字16dp、范围工具60dp，顶栏与300dp居中导航对齐；设置开关约40×24可见、整行至少64dp可点，保留原回调/存储并覆盖键盘/单一开关语义；设置分组、标签确认区及文案密度已调整。

真实8768新库的2视频/4包/24图，普通字号三轮、360双倍字号与844短横屏各一轮通过，共40个前台ADB检查点。16项针对组件检查、analyze/Ruff通过，235份manifest输入的源码、实际背景像素、窗口、源字节、SQLite数量及设备配置恢复独立核对通过。两轮独立存量视觉评审后，本轮问题已复核处理；早期主题过渡帧和屏外懒加载前置失败均单列诊断。没有重跑所有业务/服务端全集。

[45项收口台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/RESULTS.md) / [具体差异与尺寸边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/LF8-SHARED-GEOMETRY.md) / [原始证据和只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/evidence/lf8-shared-geometry/README.md)。HTML390×844去掉12px假系统区、原生390×905去掉实际49/24dp系统区后比较390×832内容，不拉伸Android画面；大字和横屏按各自实测安全区分别记证。

尚需推进（不关闭LF8或总任务）：
- [x] 图包库真实继续阅读区与原范围返回。
- [x] 权威两类库存计数；不能用分页缓存或当前筛选数冒充。
- [x] 可识别的图包标题/作者与保守回退，以及服务端排序/分页/范围一致性。
- [ ] 预览、阅读、管理、键盘和动作的完整同版对照；500页4K/8K性能、目标手机/NAS与原签名升级发布。

冻结原型树1cbf605仍独立可移除，未改正式8760/NAS/SDK或发布正式APK；生产backup_v2仍关闭。#33与#24保持开放。


## 2026-10-26：图包库真实继续阅读（PR #59）

[Draft PR #59](https://github.com/ShiJiJS/video_viewer/pull/59)基于#58，固定源码c4aaf3b，证据提交daf1863。图包媒体库在无筛选/搜索且非多选时显示真实最近打开包与页码；摘要独立于24条分页和列表取消通道，只读且不创建历史。点击从该包续读，保持原媒体库完整范围，返回原位置。搜索、多选、最近来源不展示全库续读条；失败保留列表并就地重试。

普通三轮、360双倍字号及844短横屏共五轮同源码通过，每轮10个真实前台检查点，共50图；公开2视频/4包/24PNG，实际打开后从3/6翻到4/6，续读仍为完整4包范围。两次显式opened、SQL最近/进度/会话投影、只读区间、26个源文件SHA与设备配置恢复均核对。202份manifest输入只读校验通过。客户端471项、服务端续读/阅读16项、analyze/Ruff通过；不是服务端全集或目标设备性能证明。

原生字体的实际行高取代估算，普通续读86dp（参考85）、双倍字号147dp，无裁切；共享“更多”菜单收起搜索键盘，修复短横屏进入多选时的4.7dp溢出。两轮独立存量视觉复核后无本段必须修正项；首轮材料、字体/键盘失败诊断与最终五轮分别保存。长标题/错误说明省略仍是已知显示边界，未缩字号或缩短压力输入。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/LF8-PACK-CONTINUATION.md) / [原始证据与可重跑校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/evidence/lf8-pack-continuation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/RESULTS.md)。本段补LIB-02、NAV-02、READ-04/05、REC-01与UI-01/04/05的明确组合，不关闭整项；使用MemoryCredentialStore，不新增强杀/安全存储或覆盖升级证明。

下一步继续权威两类总数、保守标题/作者与服务端排序，再核对完整预览/阅读/管理、键盘和手势；500页4K/8K、目标手机/NAS和原签名升级仍待验证。冻结原型1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：媒体库权威分类总数（PR #60）

[Draft PR #60](https://github.com/ShiJiJS/video_viewer/pull/60)基于#59，固定实现910cfb2、证据提交b927026。媒体库“视频 N / 图包 N”复用library-state中的同一SQLite只读快照，按实际完整可浏览目录计数；搜索零结果和分页不改写全库数，标签/最近隐藏标记。失败显示“—”并可点分类重试，旧服务隐藏；连接代次和请求顺序拒绝旧响应，图包操作后只读重取。

客户端485项、服务端相关75项、analyze/Ruff通过。普通三轮、大字、短横屏五轮同源码共45个库存检查点，真实逻辑回收/恢复2/4→2/3→2/4，完整进度不变、最近/阅读会话0；同源码另10个续读回归检查点通过。215份manifest输入核对源码、55个前台窗口/原始图、SQL投影、26个源SHA与设备恢复；并发提交测试证明两个总数来自同一快照。75项是相关服务回归，不是服务端全集或目标机性能。

受影响147dp顶栏与4785a69已实际渲染的冻结参考同状态并排；图包正文历史、标题/作者与排序仍有差异，不宣称整页完全一致。横屏键盘过渡暴露非当前标签页61dp可用高度下的79dp溢出，改为按实际空间约束并滚动操作区；两类标签缩高/恢复与原生横屏通过。正式取证不忽略Flutter异常，早期失败日志单列；本段未新增独立视觉评审或手势录屏。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/LF8-CATALOG-COUNTS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/evidence/lf8-catalog-counts/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/RESULTS.md)。本段补LIB-01/02、UI-01/04/05的明确组合，不关闭整项。管理网关用于验证计数更新，不替代删除确认UI验收；MemoryCredentialStore不新增强杀/安全存储证明。

下一段继续保守标题/作者与服务端一致排序，随后完整预览/阅读/管理、键盘手势、500页4K/8K、目标手机/NAS和原签名覆盖升级。冻结原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：图包标题、作者与完整范围排序（PR #61）

[Draft PR #61](https://github.com/ShiJiJS/video_viewer/pull/61)基于#60，固定源码4e391a2、证据提交614b135。图包卡片分开标题/作者，未知格式回退原名；原name/path/ID保留。续读、阅读器、范围、详情和最近复用显示标题，阅读头显示作者/编号；阅读角标补实际页码并移到左上，多选隐藏。

能力pack_presentation将App图包名称排序统一映射为title；SQLite内同一ICU中文标题键贯穿分页、锚点、完整全选和创建阅读范围。保留name/默认旧调用、旧固定会话及newest/recent；不在App只重排一页。Docker固定已有ICU运行库，裸环境缺依赖不广告能力；无schema迁移或重扫要求。双倍字号切最近加入曾向右溢出51dp，现大字操作行可横向滚动，保留字号与两端完整动作。

客户端494项、服务端8文件相关111项、analyze/Ruff通过。普通三轮、大字、短横屏共50个展示/排序检查点，另库存9点与续读10点回归；262份manifest输入核对69个前台窗口/原始图、同版源码、SQL范围ID/ordinal、26个源SHA及设备恢复。服务含28包跨页与创建后改名/新增不重排。续读回归的显式refresh沿用一次扫描，标题/库存流程无扫描；不是服务端全集或目标机性能证明。

实际浏览器和原生四包顺序一致；参考以未保存snapshot配置冷库history为空、保留第三张页码，加载的HTML/CSS/运行脚本与冻结Git字节核对。完整并排不挪列或拉伸，已明确保留差异：桌面滚动条使参考列167.5dp/原生173dp，共享标签仍11dp，参考12dp/1.6行高和4dp上距；标签顺序、次要文字颜色、菜单图标与横屏列数继续复核。视频中文排序及完整管理/阅读/预览、手势、500页4K/8K、目标手机/NAS和原签名升级也仍开放。

[设计与兼容约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/LF8-PACK-PRESENTATION.md) / [原始证据及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/evidence/lf8-pack-presentation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/RESULTS.md)。本段补LIB-02/03及UI-01/04/05局部组合，不关闭整项；未新增独立视觉评审或手势录屏，MemoryCredentialStore不新增强停/安全存储证明。早期验证预期、指标锚点/懒加载与真实大字溢出日志均单列，失败轮次不计正式图。

下一段继续共享卡片标签密度与横屏排布、视频中文排序，再收口完整页面和动作。原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。


## 2026-10-26：卡片标签密度与短横屏网格（PR #62）

[Draft PR #62](https://github.com/ShiJiJS/video_viewer/pull/62)基于#61，固定源码e53e173、证据提交8812d24。视频/图包标签统一12dp/1.6和元信息后4dp间距，作者/方向色对齐参考；卡片按实际字形测量高度。媒体库及标签结果短横屏四列，其余两列，键盘高度不改变列数；重排和返回共用实际几何，保存稳定成员与行内偏移，不重排或重查服务结果。最近视频完整形态继续核对。

客户端501项、analyze/Ruff通过。普通三轮、大字和短横屏30个卡片点，另共享8点、排序10点、续读10点、库存9点，共67张同源码原生前台图；277份manifest输入只读核对通过。120项组件样本验证两类双向重排及真实查询次数不增加；原生固定视口不冒充深列表旋转。26个公开源SHA、进度/会话SQL和设备恢复均保留。服务生产树未改，本段未重跑服务端测试；续读显式refresh沿用一次扫描，其余场景无扫描。

独立存量视觉评审一轮及修正复核一轮：作者/方向偏浅的唯一问题已修正，相邻标题/标签/网格未损坏。首轮大字续读脚本等屏外摘要挂载超时，现先核对真实返回锚点，再实际滚回顶部；失败与首轮图片单列，不忽略异常。并排复用已核对冻结字节的冷库浏览器参考，仅移除真实安全区并按DPR等比降采样，不挪列或拉伸。

[设计与返回约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/LF8-CARD-LAYOUT.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/evidence/lf8-card-layout/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/RESULTS.md)。本段补LIB-02及UI-01/04/05局部组合，不关闭整项。标签顺序/菜单图标、桌面滚动条列宽、视频中文排序、完整最近/预览/阅读/管理及手势、500页4K/8K、目标手机/NAS和原签名升级继续。冻结原型1cbf605独立可移除，backup_v2仍关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：视频中文名称顺序与预览退出（PR #63）

[Draft PR #63](https://github.com/ShiJiJS/video_viewer/pull/63)基于#62。实现a769d28、固定取证a8e94b2，生产树相同；证据提交8d65cb0。视频名称顺序在服务端贯穿分页、锚点、完整全选和固定播放范围，公开样本为“风里的花园→水边的花”。新客户端附可选name_locale=zh-CN，公共sort仍为name，旧请求和旧App可解析性保留；已有范围不因改名/新增或随机后恢复而改变原序。

真实回归同时修复退出时先销毁播放器、退场页面仍绘制导致的“No active player with ID”。现先卸载原生视图、等待本帧结束，再释放和返回；界面/系统返回两项检查在旧源码均失败、修正后通过。完整客户端505项、9个相关服务文件88项、analyze/Ruff通过；普通三轮/大字/短横屏40个视频点，加卡片6、共享8、图包呈现10，共64张同版原生图、256份manifest输入复核通过。27项跨页/固定成员与序号、实际解码/队列跳转/原筛选返回/最近去重、公开源SHA和设备恢复均核对。

首屏等真实ready及可用动作后与实际浏览器冷库参考并排，冻结源字节核对，不挪列或拉伸。旧销毁异常、末尾面板固定帧等待不足、原生空字符串输入未生效的诊断单列；最终通过可见“清除”按钮验证实际查询清空。未新增独立视觉评审或完整手势录屏，88项非服务端全集，2视频夹具非真机/NAS性能证明。

[设计与兼容约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/LF8-VIDEO-NAME-ORDER.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/evidence/lf8-video-name-order/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/RESULTS.md)。本段补LIB-01/03、预览/返回和UI局部组合；完整最近形态、视频文件名/时长显示、其它完整页面/手势、500页4K/8K、目标手机/NAS及原签名升级继续。原型1cbf605独立未改，backup_v2仍关闭；未发布APK或改正式8760/NAS/SDK，LF8/#33与总任务/#24保持开放。

## 2026-10-26：最近视频/图包历史行（PR #64，首次阶段记录；修后结果见下节）

[Draft PR #64](https://github.com/ShiJiJS/video_viewer/pull/64)基于#63。最近记录初次固定点2e971ac，键盘/错误提示修正bd2b34f，阶段证据12a3a8d。视频与图包统一为单列历史行，64×78封面、18/13dp标题/说明、普通111dp行高；普通空态对齐原型。视频显示标题隐藏已知扩展名、时长按播放器整秒显示，原名/路径/ID保留。视频分页补24项/120项窗口、前补/淘汰补偿、页尾锚点及分页变化后的定位重试。

客户端516项、相关服务26项、analyze/Ruff通过。2e971ac的15个真实普通字号点验证实际视频首帧与最近固定1项范围、两条历史、图包续读与最近2包范围、返回、两类503保留/重试、独立媒体库草稿；只读区间完整进度不变，26份源字节不变。101份manifest输入的只读复核通过；这只证明所列阶段边界。

普通/双倍字号独立存量评审未见列表/空态/返回裁切重叠，仅提出错误提示边距/颜色不一致。最新实现已统一本轮错误提示，并针对短横屏键盘暂时收起标题/导航、保留分类/搜索，组件检查覆盖280dp键盘及恢复。修后原生复核尚未通过：最后测试Android的window/settings系统服务退出，ADB仍连接，自动配置恢复失败，专用8768容器已清理，未重启/卸载/清数据。不能以旧版15图或516项组件检查冒充新版普通三轮、大字/短横屏或手势验收。

[设计与限制](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/LF8-RECENT-HISTORY.md) / [阶段证据与只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/evidence/lf8-recent-history/README.md)。继续先恢复本轮模拟器配置并补最新原生证据、同一问题复核，再推进其它完整页面/手势、500页4K/8K、目标手机/NAS和原签名升级。冻结原型1cbf605独立未改，backup_v2仍关闭；未改生产8760/NAS/SDK或发布APK，LF8/#33与总任务/#24保持开放。
## 2026-10-26：最近记录修后原生复核（PR #64）

[Draft PR #64](https://github.com/ShiJiJS/video_viewer/pull/64)基于#63，最终取证源b2ce2a8、生产界面源01bf735，证据提交33b84f4。视频和图包均为111dp普通历史行；显示标题、时长、真实阅读位置和24项/120项视频窗口已补齐。最近分别使用各自真实打开记录及完整固定范围，返回保留来源位置和独立媒体库草稿。

客户端完整518项、相关服务26项、analyze及夹具/脚本Ruff通过。lib/test及本轮integration文件format通过；全量integration另有既存server_files_test.dart格式差异，诊断单列且未修改。普通三轮、大字、短横屏各17点共85点；同源视频顺序8点及卡片6点回归，共99个原生前台检查点。323份manifest输入的只读校验通过：原始图/窗口、源码、SQL成员/序号、503到重试只读与完整进度相等、26个媒体源SHA及七轮设备恢复均核对。26项不是服务端全集，小夹具不是目标机性能证明。

同一独立存量视觉问题清单共三轮：两类失败提示边距/颜色已复核关闭；双倍字号真实键盘下操作按钮裁切已修正并复核关闭。键盘可用高度判断包含完整搜索摘要及工具行，大字临时收起标题、保留分类/搜索与完整动作，关闭后恢复；新增两项组件检查在旧实现均失败、修正后通过，原生等待实际IME并断言整个按钮位于键盘上方。短横屏最近视频scrollOffset=98是原锚点恢复，保留正常视口裁界，不强制回顶。

此前Android系统服务退出后，按开发文档受控重启同一AVD并使用host图形后端，保留userdata、没有wipe/卸载/清数据；确认window/settings服务恢复及原显示配置，再完成七轮。Binder报错不能证明磁盘或GPU根因，恢复证据单列。旧101份阶段证据保持原样，不能代替本轮修后材料。

[最终证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/evidence/lf8-recent-history-final/README.md) / [设计与来源约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/LF8-RECENT-HISTORY.md)。本段补REC-01、来源返回及UI-01/04/05的明确组合，不关闭整项。继续完整预览/阅读/管理同状态对照、手势录屏、其它异常/旧服务、500页4K/8K；目标手机/NAS、原签名覆盖升级仍待配合，按授权暂跳过。MemoryCredentialStore不新增强杀/安全存储证明。冻结原型1cbf605独立未改，backup_v2仍关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。

## 2026-10-26：阅读画布、工具与固定面板操作区（PR #65）

[Draft PR #65](https://github.com/ShiJiJS/video_viewer/pull/65)基于#64。

短横屏采用冻结原型的完整画布、浮动顶栏与360dp窄底栏，快速整理最多430dp；隐藏的总览/沉浸从更多菜单可达。竖屏保留既有顺序，收拢页码/工具/来源比例；双倍字号来源与包切换分行，保留完整来源及自然字体。设置的“继续阅读”和范围分页固定在面板底部，正文独立滚动，普通/大字分组分别留16/24dp。

最终取证源码0ab8a83，生产及组件测试树与a00d12c相同，证据提交e86726b。客户端完整530项、analyze、lib/test及本轮integration文件format和脚本Ruff通过；服务端生产/测试树与基线68f90bb相同，本段未重跑服务端测试。普通三轮、大字及短横屏各13点共65点，加最近17点回归，同源码82个原生前台检查点全部通过；303份manifest输入只读复核通过。

真实四包范围中完成总览跳页、纵向拖动、沉浸/恢复、范围查看、快速整理/退出、返回及重开。工具/面板只读区间完整进度对象相等；同一pageId与页内比例、返回锚点/偏移、两次完整4包会话成员及顺序、最近去重、纵向偏好均核对。26个源文件SHA和六轮设备配置恢复保持一致；无文件操作/回收项/扫描提交。组件另补双向旋转保持页内位置与不重建范围，以及长正文滚动时固定底部动作；固定视口原生截图不能冒充真实设备旋转或手势录屏。

独立存量视觉评审首轮及同清单复核：短横屏设置按钮裁切、大字标签边界冲突、大字来源省略、横屏分页收尾四项均在静态范围完成，没有新增必须修正项。正文超出时仍需滚动，不声称所有设置或四个成员均在横屏首屏显示。与实际浏览器冻结参考并排仅去真实安全区、按DPR等比降采样并补中性空白，不拉伸或挪动元素；真实平台行高差异保留。

[设计与实现约束](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-chrome/docs/plans/library-first/LF8-READER-CHROME.md) / [固定源码、原图、诊断和只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-chrome/docs/plans/library-first/evidence/lf8-reader-chrome/README.md)。本段补READ-01–05及UI-02/04/05的明确组合，不关闭完整验收项。继续完整预览、阅读其它异常/方向/手势、完整管理、500页4K/8K和目标手机/NAS及原签名覆盖升级；需用户配合部分按授权暂跳过。原型1cbf605独立可移除、backup_v2生产能力仍关闭，MemoryCredentialStore不新增强杀/安全存储证明；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。

## 2026-10-26：视频预览范围、播放控件与操作面板（PR #66）

[Draft PR #66](https://github.com/ShiJiJS/video_viewer/pull/66)基于#65。

控制条按实际文字宽度排布，空间不足时分行，保留至少88dp拖动轨道及原字号；短横屏中央播放按钮避让控制条，空间不足时保留明确的控制条播放入口。面板覆盖期间禁用播放/速度，关闭后恢复原播放意图。范围正文统一滚动，保留有界读取和当前项定位；补完整筛选来源、浅/暗色切换及大字整理动作排布。

固定取证源码bd40372（生产与组件测试树bd40372），客户端完整540项、analyze、lib/test及本轮integration文件format、脚本Ruff通过。服务生产与测试树同基线40b85e1，本段未重跑服务测试。普通三轮、大字和短横屏各19点共95个视频点，另阅读器13点与最近17点同源码回归，共125个原生前台检查点；442份manifest输入只读复核通过，证据提交e97852d。

真实服务路径完成单项搜索预览和返回筛选、完整范围内暂停/拖进度/速度选择、长按2倍及松手回1.5倍；整理显隐、标签取消、更多/详情、主题切换恢复、顺序队列、末尾返回及最近去重。SQL核对两轮固定1/2项来源与成员/序号、完整范围结束，工具/面板未改候选或提交标签/删除；26个源SHA及七轮设备显示配置恢复相同。组件补四种视口/字号的长来源滚动与当前定位，以及真实偏好文件读回/写入失败保留旧值。

独立存量评审一轮、同清单三次追加；暗色取图等实际主题与图标颜色完成，稳定态低对比项关闭；大字结束计数和队列说明孤字项关闭。保留原始观察和全部修后材料，不外推动态结论。普通短队列83%固定高度留白、横屏640dp面板宽及工具图标仍与冻结原型不同，继续列入UI-02/05，不能以本次评审关闭代替整页一致。

[实现约束](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-preview-panels/docs/plans/library-first/LF8-PREVIEW-PANELS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-preview-panels/docs/plans/library-first/evidence/lf8-preview-panels/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-preview-panels/docs/plans/library-first/RESULTS.md)。本段补PRE-01/02/04、来源返回及UI-02/04/05明确组合；完整预览其它异常/后台/全屏设备手势与录屏、完整管理、500页4K/8K、目标手机/NAS及原签名升级继续。固定视口不能冒充实际旋转，小型公开视频不能冒充目标机性能。原型1cbf605独立未改，backup_v2生产能力仍关闭；MemoryCredentialStore不新增强杀/安全存储证明，未发布APK或修改正式8760/NAS/SDK。LF8/#33与总任务/#24保持开放。

## 2026-10-26：范围面板尺寸、Paper轮廓与紧凑整理条（PR #67）

[Draft PR #67](https://github.com/ShiJiJS/video_viewer/pull/67)基于#66。

按上一段实际并排的残差继续对齐冻结原型：短队列随内容收缩、长队列上限后滚动，横屏预览范围改为可用全宽；恢复圆角描边选择、当前项边界、来源/说明层级与三个工具/方框播放轮廓。快速整理恢复浅绿紧凑条、文字动作和危险文字色，普通状态标题按原型保留，大字优先完整两动作。标题“范围”和视频数量按完整短语换行；新增真实滚到底部的完整说明和固定关闭检查。

固定取证eee463a（生产与组件测试树相同），完整客户端544项、analyze、lib/test及本轮integration文件format、脚本Ruff通过。普通三轮、大字和短横屏各20点，同源码100个原生前台检查点；325份manifest输入只读复核通过，证据提交5c711d6。普通两项范围实际总高435dp（含实际系统底部），旧固定面板约700.5dp；横屏宽844dp，旧640dp限制已移除。5000项末端定位组件检查仍按48项、有界次数读取，不能替代真实设备/NAS性能。

独立存量视觉首轮与同清单复核：大字标题/来源孤字、快速整理的面积与危险填色权重两项提升已在指定视口/状态关闭，没有剩余必须修正或提升项。按冻结参考保留普通整理状态标题，记录与删减建议的取舍。原始输入、诊断、修后原图与不拉伸的并排材料一并归档；没有用静态图声称完整动效已验收。

真实服务仍核对单项搜索返回、固定1/2候选与完整成员/序号、实际暂停/拖进度/倍速与长按恢复、面板/整理显隐和最近去重；26个源SHA与五轮设备显示配置恢复一致，无标签/删除/图包操作提交。服务生产/测试树同4bf060b，本段未重跑服务测试。完整预览其它异常/全屏/后台/手势录屏、完整管理、500页4K/8K、目标手机/NAS与原签名覆盖升级继续；需用户配合部分按授权暂跳过。原型1cbf605独立可移除且未改，backup_v2生产能力仍关闭，MemoryCredentialStore不新增强杀/安全存储证明；未改正式8760/NAS/SDK或发布APK。#33/#24保持开放。

[实现约束](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-geometry/docs/plans/library-first/LF8-PREVIEW-GEOMETRY.md) / [固定源码证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-geometry/docs/plans/library-first/evidence/lf8-preview-geometry/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-geometry/docs/plans/library-first/RESULTS.md)。

## 2026-10-26：设置表单、媒体目录与真实键盘（PR #68）

[Draft PR #68](https://github.com/ShiJiJS/video_viewer/pull/68)基于#67，最终源码81b598f（生产界面同57edbc8）。连接/目录保持全高度管理页，文字输入恢复外置标签与近白输入面，类型/方向/适配使用开放设置行；保留图片适配、显式保存和原请求核对。正常完成扫描收为可展开摘要，异常仍显示详情；错误滚入可见区，极短键盘窗口允许动作随正文滚动，当前值与焦点保持可见。共享Paper短面板全宽，修正短媒体库状态区消息/重试可达。

完整客户端550项、analyze、181个Dart文件format与runner Ruff通过。普通三轮/大字/横屏105个设置点，另阅读13/预览20/最近17个短横屏回归，共155个同源码原生前台图。设置核对端口错误、真实目录类型409、草稿取消、默认值保存/重开读回/恢复；活动2成员视频范围、根记录和夹具原进度不变，阅读默认只两次写入/revision2、播放默认未写。八轮源SHA及显示配置恢复核对；阅读/最近回归产生的会话和进度按各自预期另核对。服务生产/测试树同8b68804，本段未重跑服务测试。

独立存量首轮与同清单复核，2问题/2提升均关闭：横屏连接焦点遮挡、表单还原、大字时间行首分隔点、类型冲突重复说明。原始图与不拉伸的并排、先行不稳定截图、真实溢出修正及两次QEMU自身崩溃/恢复分开归档；中断不计最终通过。主题文件IO测试改为等待真实保存/错误，相关两分支连续三轮及最终550通过，不隐藏原失败。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/LF8-SETTINGS-FORMS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/evidence/lf8-settings-forms/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/RESULTS.md)。本段补SET-01/02/04与UI-03/04/05明确组合，完整其它管理、预览/阅读异常与手势录屏、500页4K/8K、目标手机/NAS及原签名升级继续；需配合部分按授权暂跳过。原型1cbf605独立未改且可移除，backup_v2仍关闭，MemoryCredentialStore不新增强停/安全存储证明；未改正式8760/NAS/SDK或发布APK。#33/#24保持开放。

## 2026-10-26：缺失内容管理与待核对结果（PR #69）

[Draft PR #69](https://github.com/ShiJiJS/video_viewer/pull/69)基于 #68，生产及主流程源码固定 2369f0d，证据提交 8813c78。缺失内容改为 Paper 全高度页，视频/图包继续分别读取；名称、完整路径、类型/标签、实际根目录状态分层，保留 24 条分页、刷新、原请求和任务详情。危险清理位于列表之后，短确认层保留完整风险说明；普通/大字标题为 52/72dp，正文 20dp，次级色与原型浅暗色一致。

修正两个真实长列表问题：底部提交后先揭示顶部错误/原请求入口，避免惰性项未挂载而滚动失效；显式翻页成功回到新页开头，读取失败仍保留原页、成员及偏移。通用联调的原型元数据改为可空，不再要求独立设计目录一定存在；未据此声称已完成删除原型后的构建演练。

21 项相关客户端检查连续三轮、analyze、变更 Dart 格式与 Ruff 通过。普通/大字/短横屏各 13 点，同源码 39 个原生前台检查点；另同生产源码补大字/短横屏页尾与确认末尾共 4 图。每轮真实 27 包→25 缺失，停用清理保留 25 包及标签/进度/偏好/最近；返回一包后明确清理 24 条管理记录、保留返回包与原历史成员身份。两次 POST、一次原请求 GET、当前完整视频范围、源图片 SHA、数据库投影及五轮显示恢复均核对。第二次丢回执后的 App/Repository 重建发生在同进程，不冒充强停证明。本段未重跑客户端或服务端全集，服务生产树与 #68 相同。

独立存量首轮、中间普通复核、最终三视口及页尾补充复核，冻结 1 问题/1 提升已关闭：次级色过浅和分页到清理的间距已处理，完整页尾与确认末句可读。保留原生字体/真实安全区差异，静态图不作为完整动效或手势证明。失败脚本前置、真实结果不可见、分页起点修正和两次 QEMU 崩溃/恢复均单列诊断，不计最终成功点。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/LF8-MISSING-MANAGEMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/evidence/lf8-missing-management/README.md)。本段补 SET-04、DEL-06 与 UI-03/04/05 的明确组合，完整其它管理、旧服务/扫描异常、预览/阅读手势、500 页 4K/8K、目标手机/NAS和原签名升级继续；需配合部分按授权暂跳过。冻结原型 1cbf605 独立未改且可移除，backup_v2 仍关闭，未发布 APK 或改正式 8760/NAS/SDK。#33/#24 保持开放。


## 2026-10-26：双类型回收站、逐行恢复与待核对选择（PR #70）

[Draft PR #70](https://github.com/ShiJiJS/video_viewer/pull/70)，证据提交f5493f4。本段基于#69，最终生产及主流程固定88a45ec。视频／图包回收站统一为Paper全高度管理页：20dp正文、名称／完整路径、左侧勾选、逐行恢复和底部选择动作。短列表动作跟随内容；长列表保留可见收尾，真实IME或极短高度时随正文滚动。24项分页、图包搜索、刷新、原请求与任务入口继续保留；成功翻页回到新页开头，读取失败保持成员、偏移和选择。

原生核查修复两处实际状态问题：查询原请求成功后只释放对应26个选择，后来新选成员保留；ListView保持同一视口类型，避免键盘弹出切布局时丢失焦点。核实前显示“保留选择N／恢复结果待核对”，阻止相交内容的重叠恢复与删除；逐行确认写“恢复1个图包”，与批量选择区分。恢复确认和任务终态说明精简，真实停止结果仍保留。

47项相关客户端检查连续三轮、analyze、13个变更Dart文件格式及Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏同源码各15点，共45个原生前台检查点。每轮真实27包81张图片，跨页选26、确认取消零写、受理丢回执只GET原请求一次、再逐行恢复剩余1包；两次POST(503/202)、精确26+1成员、SQL计数、81张源SHA、首包进度／偏好／标签、完整当前视频范围及设备显示恢复单列核对。

独立存量评审沿冻结2问题/1提升复核页签锚线与通栏细线、未知选择语义、单项确认及终态减字，三视口可见项已静态闭合。另同生产补横屏unknown页尾1图，确认保留选择／核对说明／禁用动作完整；补轮原生只提交一次26恢复、零原GET，源SHA与视频响应保持。原始基线首阶段通过但旧runner误启动第二阶段，整体失败；旧选择问题、键盘焦点及惰性列表脚本等待失败另归诊断，不计最终成功点。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-trash-management/docs/plans/library-first/LF8-TRASH-MANAGEMENT.md) / [原图、固定源码及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-trash-management/docs/plans/library-first/evidence/lf8-trash-management/README.md)。本段补DEL-04/06与UI-03/04/05明确组合，完整永久删除复核／部分失败、备份／任务管理、其它预览／阅读异常与手势、500页4K/8K、目标手机/NAS及原签名升级继续。MemoryCredentialStore不新增安全存储或真实强停证明；冻结原型1cbf605独立未改且可移除，backup_v2仍关闭，未发布APK或改正式8760/NAS/SDK。#33/#24保持开放。
## 2026-10-27：备份、恢复预览与操作任务管理（PR #71）

[Draft PR #71](https://github.com/ShiJiJS/video_viewer/pull/71)基于#70，证据提交b9ccf92；生产及13点主流程固定e10bbbc，archive等待修订30bc9d7的生产字节相同。备份采用Paper开放操作行；两目录短面板、27目录完整分页表单保留外置标签、完整路径、空映射与明确确认。任务说明、筛选、回执、记录和分页归入同一正文，详情使用相同页头与筛选样式。成功翻页归位，失败保留原页和草稿；真实IME时动作随正文可达。

修正保存取消仍显示“已下载”、同次格式错误重复、确认框顺序及不限行输入截获正文滚动。37项相关客户端检查连续三轮、analyze、14个变更Dart文件格式及Ruff通过，未重跑客户端或服务端全集。普通／双倍字号／短横屏各13个旧备份／任务点与8个完整archive点，共63个最终原生前台点；521份输入逐字节纳入manifest并只读复核通过。

任务阶段零POST、唯一原回执GET、两次原备份下载与81张源SHA独立核对；前置备份准备写入不称只读。完整archive仅在既有隔离8762夹具，每轮核对27目录、明确恢复一次，实际epoch及两类新增标签替换、当前任务完成，恢复前快照仅预览，源SHA保持。文件边界为注入／Android私有文件，不冒充系统文档提供器。大字初轮异步分页脚本失败已保留，等待27/27就绪后重新取齐最终三组；旧基线整体失败与中间成功样本均单列。

独立存量六份静态报告按冻结2问题／2提升复核，可见项已闭合；v1响应式确认行、暗色跨页详情和部分archive字段不在对应帧内，未扩大为所有组合或手势／动效通过。原始日志的尾随空白保留，源文件与文档另通过diff检查。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-task-management/docs/plans/library-first/LF8-BACKUP-TASK-MANAGEMENT.md) / [原图、固定源码及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-task-management/docs/plans/library-first/evidence/lf8-backup-task-management/README.md)。本段补BAK-01/02/03与UI-03/04/05明确组合，不勾选整体验收。永久删除复核／部分失败、大文件／更多备份故障与实际选择器、完整预览／阅读手势、500页4K/8K、目标手机/NAS及原签名升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760/NAS/SDK。#24/#33保持开放。

## 2026-10-27：永久删除复核、完整清单与部分失败（PR #72）

[Draft PR #72](https://github.com/ShiJiJS/video_viewer/pull/72) 基于#71，最终源码35a29d4，证据提交adeb1e2及527份manifest输入已逐字节复核。视频采用短底部前置勾选确认，图包保留精确图片清单／摘要／有效期和附件保留；保存选择、图包／图片清单及结果改为完整Paper管理页，20dp正文、52／72dp页头、单一正文滚动、真实分页和原请求／原任务重试。成功翻页归位，失败保页并揭示错误，完成空态移除零项页控。

90项相关客户端检查连续三轮、analyze、11个变更Dart文件格式与Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏各12点，同源码36个原生前台点。每轮108份真实源文件，取消／保存重开零物理提交；两次准备503/202、一次删除503、一次原任务重试202。相同task/plan逐项结果与SHA核对，最终差集恰为清单3张图片，其余105份SHA不变，27份附件保留、目录retained。视频原生仅取消确认；勾选分发与代次变化由组件边界检查，不外推真实视频源删除。

独立存量首轮冻结1问题／1提升，三视口36张最终PNG均已亲看，原1问题／1提升在可见范围闭合；静态图不认证动效／手势与行为。初次暗色图捕到主题与嵌套文字过渡中间帧，最终等待过渡结束并检查三个实际按钮文字／背景对比≥4.5，未更换主题色板。失败脚本定位、busy无限加载、长清单揭示距离和Demo队列测试诊断单列保留，不计最终成功点。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-purge-management/docs/plans/library-first/LF8-PURGE-MANAGEMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-purge-management/docs/plans/library-first/evidence/lf8-purge-management/README.md)。本段补DEL-05与UI-03/04/05明确组合，不关闭整体验收。更多批次／断电、备份大文件／故障／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机/NAS与原签名覆盖升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760/NAS/SDK。#24/#33保持开放。

## 2026-10-27：两套标签目录、定义编辑与交集结果（PR #73）

[Draft PR #73](https://github.com/ShiJiJS/video_viewer/pull/73)基于#72，证据提交[d710b33](https://github.com/ShiJiJS/video_viewer/commit/d710b33)，生产客户端固定4e905aa；普通完整脚本2cde25c、大字核心4e905aa、横屏核心c7e9799，结果专项补充79de2d9，完整生产字节一致。标签目录沿用Paper开放行、20dp正文锚线与描边选择，视频／图包继续独立。新建／改名复用外置字段、类型范围和明确动作；同名错误只留在表单。移除在同一面板独立确认，取消保留未保存草稿；写入中防重复及关闭，连接身份变化禁止旧ID写入。

46项相关客户端检查连续三轮、analyze、6个Dart文件格式与Ruff通过；未重跑客户端或服务端全集。生产字节相同的普通完整15点、大字核心13+结果专项2点、短横屏核心13+结果专项2点，共45个有效原生前台点。结果补充各自使用独立夹具，不冒称同一次全流程；旧弱门槛结果图不计。真实图包同名409保草稿、创建201、原ID改名保关联与移除取消／确认、视频61项跨50分页503／重试均核对。结果页另注入503并实际点击重试，核对唯一视频ID、total=1及两个标签条件，未以页面标题代替加载成功。四次UI定义写尝试、61视频定义／3关联、81图片SHA、27视频路径／大小／SHA和完整播放响应分别核对；前置准备写入不称只读。

独立存量评审沿冻结唯一提升将双层确认收敛为单层，浅暗编辑与普通完整15图／大字和横屏各新增2图复核；13核心图沿已亲看且字节未变的结论，不称再次重跑；静态图不认证完整动效／手势。原14点弱结果门槛、夹具遗漏代次头、短视口惰性定位与QEMU退出／同AVD恢复均单列，不计最终成功点。真实视频UI定义CRUD、批量追加／完整范围等其它TAG组合继续，不以共享组件分发代替完整业务验收。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/LF8-TAG-MANAGEMENT.md) / [固定源码、原图与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/evidence/lf8-tag-management/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，不关闭整体验收；更多备份故障／大文件／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机／NAS及原签名升级继续，需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS／SDK。#24/#33保持开放。


## 2026-10-27：视频／图包标签分配与批量追加（PR #74）

[Draft PR #74](https://github.com/ShiJiJS/video_viewer/pull/74)基于#73，生产客户端固定94c7292，最终原生脚本94c7292。标签分配统一Paper面板、21dp标题及20dp正文；视频／图包分别读取、创建与关联标签。单项保存替换整项标签，跨页批量仅追加，即使最后只剩一个目标也保留原标签。搜索与新建字段分离；创建／关联错误保留草稿，分页与名称核对沿原协议；提交中阻止重复、返回和拖动关闭，连接／恢复变化拒绝旧回调。小目录去除重复已选区，新建与添加同行；短横屏字段并排，系统字号保持。短横屏只在所选标签不在当前候选中时显示独立已选区，避免重复挤占首行。覆盖媒体库的弹层自行避让IME，背景保持原视口及读取错误，修复74dp剩余窗口中的29dp溢出。

48项相关客户端检查连续三轮、另31项共享导航／设置／面板检查、analyze及Ruff通过；Linux隔离服务10项标签／名称／全范围选择契约检查通过，未重跑客户端或服务全集。普通／双倍字号／短横屏同生产与最终脚本各14点，共42个原生前台点，包含两类单项替换、新建同名409保草稿、真实IME、保存返回实际来源模型读回，以及跨24项分页全选27再排除1项的批量追加。请求ID、单项其余26项未变、批量精确26成员、最终每类53条关联、两套命名空间、81图片SHA及显示配置恢复分别核对。

独立复核沿冻结1问题／1提升检查最终42图，可见范围内低高度操作截断与面板体量均闭合；静态图不外推动效或完整手势。截图保持状态并由宿主完成采集后确认，初始等待真实候选、保存等待来源模型读回；旧错位、加载中、未刷新图和失败轮单列诊断。普通使用默认Android渲染，大字／短横屏用测试专用Skia以绕过QEMU默认渲染崩溃，未修改应用或SDK默认，不冒称三组默认渲染全部通过。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-assignment/docs/plans/library-first/LF8-TAG-ASSIGNMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-assignment/docs/plans/library-first/evidence/lf8-tag-assignment/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，#24/#33及整体验收保持开放。真实视频定义CRUD的完整UI组合、更多备份故障／大文件／系统选择器、预览／阅读异常与手势、500页4K/8K、目标手机／NAS与原签名升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS。

证据提交 [c1f51ab](https://github.com/ShiJiJS/video_viewer/commit/c1f51ab)：920份清单输入及925份实际暂存文件已逐字节核对，三组完整只读复核通过。


### PR #75前的目标段落快照

将现有 0.1.4+5 Android App 升级为已确认的「媒体库为中心、视频与图包分别管理」完整产品。用户于2026-10-23确认独立的 `design/reference/library-first/` 原型方向。LF0–LF7已有分阶段实现与证据，LF8原型一致性收口进行中；最新[Draft PR #69](https://github.com/ShiJiJS/video_viewer/pull/69)补缺失内容管理、长列表错误显露与成功翻页起点，21项相关检查连续三轮、39+4点同生产源码原生与独立复核通过；完整其它管理及预览/阅读异常与手势继续。各阶段未收口项目及当前证据见[45项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/RESULTS.md)，仍需依赖PR合并、完整同版验收、目标手机/NAS及原签名升级验证，尚未发布新版。

## 2026-10-27：原型可移除构建演练与当前整合回归（PR #75）

[Draft PR #75](https://github.com/ShiJiJS/video_viewer/pull/75)基于#74，固定源码7c70e59。将整个Git提交导出到新建副本，仅移除副本内72份`design/reference/`文件，12,145份保留文件与固定提交全部blob独立逐字节核对；App package root实际指向副本，Git discovery上界避免借用父仓库。构建后保留源码与原仓库参考文件SHA均未变，副本参考目录保持不存在。冻结原型树1cbf605在原仓库独立保留。

同一副本Flutter analyze、完整643项客户端测试、debug/release APK构建、服务镜像Ruff check和完整Linux pytest 447项通过；初次pub解析离线且强制锁文件，构建使用标准Flutter模式注册。两包Flutter资产清单不含原型路径，Flutter引擎仅ARM64，JNI依赖另含armeabi-v7a/x86_64；release DEX无integration_test插件路径。APK仅本机构建，沿现有开发签名、未递增版本，不作为原签名升级包。服务格式检查仍有27份存量文件失败，单列保留，未误报全部门禁通过。

首轮debug后错误复用`--no-pub`使release残留测试插件注册而失败，`complete:false`与原始日志保留；同副本标准release通过只作诊断，修正脚本后按7c70e59重新完整跑第二轮。未修改SDK或移除开发测试依赖。输出安全检查拒绝仓库根目录、整个.dev及已有目录；实际只删除一次性导出副本。

[实施与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reference-isolation/docs/plans/library-first/LF8-REFERENCE-ISOLATION.md) / [固定源码、原始日志与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reference-isolation/docs/plans/library-first/evidence/lf8-reference-isolation/README.md)。此段证明实际移除参考目录后的构建/测试隔离，服务用例覆盖大于32MiB HTTP备份和500页4K/8K扫描，但不证明Android长包渲染、真机/NAS性能、系统选择器、完整手势或原签名覆盖升级。#24/#33及整体验收保持开放；需用户配合项按授权暂跳过。原型树独立未改，backup_v2生产仍关闭，未发布APK或修改正式8760/NAS。

## 2026-10-27：图包瞬断重试与500页/大图阅读（PR #76）

[Draft PR #76](https://github.com/ShiJiJS/video_viewer/pull/76)基于#75。真实大图响应头前连接关闭暴露自动恢复缺口，生产固定f8631ae：SocketException/HttpException沿现有400/800ms、最多两次自动重试；持续失败仍可手动重试/跳过，失败不记进度，离页取消定时器。布局、服务业务、SDK和冻结原型均未改。新增3项回归在修复前两项失败、修后通过；12项相关与完整646项客户端测试、analyze/格式/Ruff通过。服务447项全集仍归属#75，本段未重跑。

最终驱动/采集固定df9d80c，生产与组件测试字节同f8631ae。同一API36 ARM64专用AVD、软件GPU/headless、390×844/DPR3/字号1、App无渲染覆盖，连续三轮均从媒体库进入500页，经730次实际拖动覆盖所有页；末页横纵切换、固定4包范围、三次4K/6K/8K实际解码往返、返回媒体库再续读及纵向偏好，均核对实际可见帧、HTTP与只读SQL。共39个前台点、6段原生录屏（全帧解码通过），源SHA相同，显示基线恢复。宿主GPU退出139、长扫描准备、旧图像传输失败及驱动/采样就绪问题分别留档，不拼为成功。

元数据峰值120、provider 6项/估算24.4MiB、Flutter缓存约26.8MiB/待解码4；全部采样与检查点PSS最高480.8/631.4/462.9MiB。不同指标不互作上限，debug驱动节奏及高压缩纯色合成图不代表真实照片、SMB或目标手机/NAS性能。第一轮一次已处理离屏长包预读HttpException保留；没有原生当前大图故障注入，自动恢复/重试上限由组件检查证明。标准ARM64 release编译成功，资产无原型路径且release DEX无integration_test；仅本机构建、开发签名和原版本，不发布或冒称原签名升级。

[实施与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-long-pack/docs/plans/library-first/LF8-READER-LONG-PACK.md) / [固定源码、原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-long-pack/docs/plans/library-first/evidence/lf8-reader-long-pack/README.md)。本段补READ-01..06、PKG-03与UI-02的明确组合，未据此关闭整项。目标手机/NAS峰值与30次p50/p95、其它方向/缩放/大字/手势及异常、系统选择器和原签名覆盖升级继续；需配合部分按授权暂跳过。原型树1cbf605独立未改且可移除，backup_v2生产仍关闭，未改正式8760/NAS。#24/#33保持开放。
