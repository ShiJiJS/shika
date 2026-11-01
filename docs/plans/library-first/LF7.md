# LF7 设置与统一任务实施记录

最新阶段：[上传失败原因与原任务找回 PR #91](https://github.com/ShiJiJS/video_viewer/pull/91)。App保留底层异常／等待阶段，提示及不重发写命令的规则不变；672客户端、28相关检查通过。848a1b8正式受控回复中断／双进程找回12点和普通完整恢复14点，共26点／28图，325输入复核通过；旧PID停止并移除本机输入后，新PID免口令只GET原任务、27目录预览且确认关闭。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复仍未完成，不把已受理回复中断当作原始问题。先前host归还显示失败已修，原配置恢复后重新验证通过；服务生产源码未改，27个旧格式问题待处理。原型独立未改、资源已归还，未部署NAS／发布APK，#24/#33/#32/#89保持开放。

下文保留LF7实施历史，较早缺项描述以最新阶段与逐项台账为准。

## 目录类型、启停与分类型缺失管理（2026-10-25）

[Draft PR #47](https://github.com/ShiJiJS/video_viewer/pull/47)基于#46，主实现4e569ad，根扫描身份保护ed60bc9，保留原因文案fd1db91；最终原生测试锚点及实际结果见[证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-roots-missing/README.md)。[契约](LF7-ROOTS-MISSING-DESIGN.md)明确旧服务兼容、连接隔离、24条分页、持久任务与本机原请求日志。

设置→媒体目录已能真实新建视频/图包类型、启停并提示状态，类型冲突保留输入。全高度缺失页按视频/图包分别计数与查询；取消不写，图包确认只清失效管理元数据，不删源字节。0013受理时通过SQL固定全部缺失成员，每项独立事务结算，原任务在服务重建后继续pending；后续新缺失不加入原范围。活跃标签/进度/偏好/最近可清，墓碑和历史会话成员保留，路径重新出现不复用被清理的旧ID。

离线、停用、归属变化、返回、文件任务占用与扫描证据不可靠时逐项保留；根路径相同但目录已替换也须匹配最近成功扫描的本机身份，不能只比较清理时的两次当前目录。无旧证据的升级库须重新成功同步。未知结果先保留安全日志，重开不自动重发，明确查询只GET原request_id；任务详情显示保留原因和有界成员分页。

369项客户端、analyze/Ruff和15项新增服务端针对检查通过；服务端全量316通过/1次旧视频扫描超时，该用例原样独立重跑13.54秒通过，完整保留两次结果。固定59f78b6原生三轮308.89/138.03/197.17秒全部退出0，27检查点独立复核通过，源文件和原视频范围保持；系统无响应/网络中断等诊断均未混算。本阶段结果分层写入证据，不用服务端协议检查替代原生完整流程。SET-04全组合、管理备份v2/v1转换及权威历史化、真实选择器和有界传输、其它强停组合、历史图片错误、全原型暗色横屏/手势与真机NAS仍开放；没有改冻结原型或发布APK。下文保留前阶段历史记录，其中当时的缺项状态以本段及最新证据为准。

源码锚点：`92d9b15`，基于 LF6 `f306817`；分支 `codex/lf7-maintenance-tasks`。设计契约见 [任务中心设计](LF7-TASKS-DESIGN.md)。

设置新增“操作任务”和本机待核对提示，沿用现有 Paper 风格、设置行比例和全高度管理页。真实服务按24条分页筛选同步/视频/图包/备份，详情显示成员和部分结果，历史操作保持只读。列表只取标量投影，不物化巨大任务结果。

本机未确认请求独立读取，服务端历史失败与本机日志错误分别呈现。图包、视频、备份按原request ID和任务ID核对；404不重发，迟到旧回执不清除新命令。原导出下载验证SHA与UTF-8；取消保存保留原记录，保存成功才结算同一任务。连接或数据代次变化使旧读取失效。

## 任务中心阶段的检查与原生证据

- Flutter analyze 无问题，完整客户端316项通过。服务端Ruff及271项测试通过；pytest的2条既有配置警告保留在原日志。
- 隔离服务8761、API36 Android，从设置进入任务中心，实际响应丢失图包回执只查询原操作、27条服务端任务跨页、历史视频任务只读、同一原备份取消/保存两次。
- 固定源码连续三轮通过（390普通、360双倍字号、390普通）；文件哈希和请求轨迹与截图分别保留，详见 [证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-tasks/README.md)。
- 原型目录与 `design-lf-2026-10-23` 的Git树均为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`，独立可移除。

## 必须继续的范围

整份逻辑恢复已接服务端父计划/成员/唯一子批次，离页或关闭App后继续、重开只查询原请求。永久删除尚未提交的剩余选择也已持久化并提供回收站/任务入口，后续批次仍需逐批核对确认。1003包中明确确认1000包、真实安全存储强停重开并找回剩余3包的三轮验证已补齐，见文末最新阶段；其它命令、来源及异常边界的组合仍待继续。

服务端默认值与旧本机值明确迁移已接入，见文末最新阶段。完整设置仍需补目录类型/启停控件和图包缺失管理；管理备份v2/v1转换、根映射/完整替换/恢复前快照、其它命令的真实SecureStorage强杀组合、全原型状态/暗色/横屏与真机/NAS性能仍待完成。任务中心最初阶段使用内存凭据和注入保存适配器；下方App阶段已补齐逻辑恢复/停止及永久删除的真实安全存储进程重启，系统文件选择器仍待验证。原备份仍是兼容v1；有真实图包或明确保存的新默认值时阻止旧格式备份，不能据下载成功宣称v2往返已完成。

未发布APK，未修改真实NAS/8760。#32、#31、#24 保持开放。

草稿 [PR #41](https://github.com/ShiJiJS/video_viewer/pull/41) 基于 [PR #40](https://github.com/ShiJiJS/video_viewer/pull/40)，阶段与总任务继续保持开放。

## 整份恢复服务端阶段

实现3416b1e，扫描并发修正6880055，[Draft PR #42](https://github.com/ShiJiJS/video_viewer/pull/42) 基于 #41。新增0012持久父计划/完整成员/唯一子批次，统一包预约，最多1000项逐批后台推进，重启先核对原子操作；明确停止只取消尚未开始成员，逐项结果和历史保持可查询。

当前294项服务端/Ruff通过；1003项跨批、三种边界各三次真实SIGKILL、停止/并发/状态变化/旧库迁移/历史保护均覆盖。启动扫描并发用两个固定交错复现并修正；进程检查等待启动扫描结束并核对原ID和代次。原始失败日志也保留。见 [设计](LF7-RESTORE-PLAN-DESIGN.md) / [证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-restore-plans/README.md)。

本阶段没有修改客户端，尚未把旧App循环替换成整份计划；不得据服务端通过关闭DEL-04/06或LF6/LF7。下一步落实原计划安全存储、未知回执GET、离页/强杀重开、任务中心停止和原生验收。永久删除剩余选择持久化、v2备份及其历史化、完整设置/默认值、真机NAS与全原型验收继续推进。

## 整份恢复 App 与安全存储强停

实现 eba2541，大字号布局修正 e58864e；[Draft PR #43](https://github.com/ShiJiJS/video_viewer/pull/43) 基于 #42。支持当前能力的服务不再由 App 循环提交1000项：确认完整选择只提交父计划，受理后可离页；回收站和任务中心都能找回原恢复/停止请求。写盘失败不提交，未知/404不自动重发，停止与失败/成功计数分开。

330项客户端、294项服务端/Ruff及analyze通过。固定源码真实Android连续三轮（390普通、360双倍字号、390普通）：活跃进程强停后PID消失，服务端在App缺席期间完成27包/14个唯一批次；新PID从真实SecureStorage找回原请求，仅GET原恢复回执。另一计划停止响应丢失后只GET原停止回执，2包恢复/25包未执行，81张源图片及原包ID保持。详见 [App设计](LF7-RESTORE-CLIENT-DESIGN.md) / [原始证据与边界](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-restore-client/README.md)。

已修正实际Android快速进详情的SnackBar Hero冲突；大字号错误/查询入口改为可滚动，避免列表仅剩52像素。修正前失败、旧布局截图与此前核心逻辑三轮独立保留，当前完成证据只使用e58864e后的三轮。首段本就保持测试未结束并由宿主强停，其runner非零退出是预期中断；第二段必须实际通过，不能把第一段算成测试通过。

以上解决整份逻辑恢复及其停止的持久重开，不能替代永久删除、撤销及管理恢复等其它命令的完整强杀组合。永久删除剩余选择持久化、v2备份及父/子/成员历史化、完整设置审计/服务端默认值迁移、旧原生用例迁移、全原型状态与真机NAS仍未完成。冻结原型独立且未改，未发布APK，#31/#32/#24保持开放。

## 永久删除剩余选择与逐批核对

应用实现19ef6e5，[Draft PR #44](https://github.com/ShiJiJS/video_viewer/pull/44) 基于 #43。完整选择持久保存，回收站和操作任务都有入口，打开只读本机记录；每批仍重新核对精确图片清单并明确确认。原选择/本批命令在同一次安全日志写盘后才POST，未知保留原批次，明确未受理回到未提交范围。旧确认/旧移除不覆盖新批次，移除本机选择不清已提交命令。本机管理恢复将选择标为历史，跨设备权威代次及完整管理历史化仍属后续v2。

完整345项客户端/analyze通过；1027组件流程验证取消/离页找回、明确删除1000后剩余27、新批确认默认关闭，另覆盖任务入口/历史筛选和移除选择不清未知命令。服务端生产源码未改，294项基线沿用上阶段；本轮仅增加测试夹具检查点并通过Ruff/编译。多页回收站分页栏改为大字号可换行，核对面板期间底层不显示持续加载。

固定最终原生源码fdef0e4，连续三轮为360双倍字号、390普通、390普通，原请求/哈希独立核对见 [证据与范围](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-purge-selections/README.md) / [设计](LF7-PURGE-SELECTION-DESIGN.md)。取消后保存/重开入口不新增POST；一份真实精确清单的未知回执、部分删除和原任务重试保留27附件，文件108→106→105且剩余SHA不变。夹具422和大字号原生测试尚未滚回入口/滚到部分结果的失败记录保留，不混算旧轮次。

本原生流程使用内存命令/凭据，未强停进程；不能据它宣称永久删除真实SecureStorage强停完成，也不把单包文件流程说成1000包物理性能。后续强停补证见下一节。v2/v1备份及父/子/成员历史化、完整设置/默认值、旧原生用例迁移、全原型/真机NAS与原签名发布继续推进。原型树仍独立未改，未改8760/NAS、未发布APK，所有阶段保持开放。

## 永久删除真实安全存储强停与1003包

测试实现 `b8c823b`，[Draft PR #45](https://github.com/ShiJiJS/video_viewer/pull/45) 基于 #44。使用生产安全凭据/文件命令存储适配器的专用测试键；真实扫描1003个公开合成图包，每包1张JPEG和1份附件。完整选择后明确核对第一批1000，响应丢失后原命令和剩余3包已落盘；宿主强停活跃PID，服务在App缺席期间完成1000包，新PID无需口令恢复连接、只GET原回执，结果可跨真实服务分页。剩余3包重新打开精确清单，确认默认关闭，取消不提交。

固定源码完整三轮通过：360双倍字号283.58秒、390普通328.94秒、390普通334.18秒。每轮首段受控强停的非零退出如实保留，只有重开段实际通过及独立校验吻合才记整轮通过。`verify.py`逐轮确认原1003ID严格分为提交1000/未提交3、精确删除1000张原图片、1003附件及余3张图SHA不变、永久删除POST只有1次、原回执GET只有1次及扫描POST只有1次。见 [完整证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-purge-secure-restart/README.md) / [独立核对](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-purge-secure-restart/proof.json)。

本轮仅测试/夹具/runner及文档，应用与生产服务源码未改；analyze、夹具Ruff及Python编译通过。345项客户端/294项服务端沿用前阶段，不宣称本轮重跑。保留扫描等待、原生滚动及定位诊断，未修改SDK；模拟器已恢复1080×2400、420dpi、字号1。冻结原型Git树仍为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`。

下一阶段继续完整设置与管理备份：复用已有revision化 `reader_defaults`，保留已读包独立偏好；补服务端默认视频顺序及本机旧值迁移。v2须覆盖两类媒体及完整父/子/成员/回执历史，兼容v1转换，落实根映射、完整替换、前快照、跨设备数据代次及有界文件传输；当前v1仍不能备份真实图包。其它命令/来源与部分失败重试强停组合、历史图片失败根因、全原型/暗色横屏、真机NAS性能与原签名发布仍待完成。#31/#32/#24保持开放。

## 服务端默认值与旧本机设置迁移

实现 `459870b`，[Draft PR #46](https://github.com/ShiJiJS/video_viewer/pull/46) 基于 #45。[契约及完整设置审计](LF7-DEFAULTS-DESIGN.md)。默认播放顺序成为当前服务管理数据，服务首次从旧轮次采纳后与轮次独立；新范围进入前读取当前默认。图包直接复用已有阅读默认接口，已读包保留各自偏好。设置增加阅读偏好面板；旧本机顺序只在明确选择并保存后迁移，决定按endpoint+server_id本机隔离。冲突要求重读，未知响应只GET原ID，关闭/取消草稿不提交，连接或本机管理代次变化使旧网关失效。

完整354项客户端、302项服务端、analyze及变更Ruff通过；服务端保留1条既有弃用警告。首次服务端全量命令漏传共享内存限制导致ENOSPC夹具前置断言失败，按项目要求加入64MiB后完整重跑302通过；不修改断言或文件执行器。测试路由/映射、编译及widget HTTP覆盖问题的诊断分开保留。

固定源码Android正式三轮：390普通143.51秒、360双倍字号125.56秒、390普通109.66秒。通过实际设置入口取消/保存、旧顺序迁移、阅读响应丢失后原ID查询、App/Repository和本机文件重建读回；当前视频范围完整响应及已读包偏好不变，未读包继承新默认。每轮只有2次明确PATCH、1次原设置回执GET，81张图片SHA不变；`verify.py`独立核对源文件与全部请求/文件证据。[完整证据与边界](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-defaults/README.md)。此次是同一Android进程内重建App，不冒充新的强停验收；三个视频入口完整组合仍由LF8继续。

旧v1明确阻止遗漏已保存的新默认值，合法v1恢复从导入轮次重建隐式默认；仍不能据此宣称v2完成。审计发现目录类型/启停仅在服务端已具备，App表单仍缺控件、新建固定视频，缺失列表也主要是视频。下一步先补实际目录接入与图包缺失管理，再继续v2类型化全数据图、映射/前快照/完整替换/跨设备代次与历史只读、有界传输和系统文件选择器。其它命令/来源强停、历史图片失败根因、全原型/暗色横屏、真机NAS与原签名发布继续。冻结原型与SDK未改，未改8760/NAS或发布APK，#32/#24保持开放。

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

433项客户端与398项服务端全集通过；全目录Ruff、analyze和127个Python文件编译通过。[设计与兼容边界](LF7-APP-ARCHIVES-DESIGN.md) / [固定源码、原始轨迹及独立核对](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf7-archive-files/README.md)。独立视觉复核发现大字号目标路径末尾不可见，已自然换行并复核；临时连接切换异常、当前快照查询误用旧回执通道及测试脚本滚动目标均已修正，诊断日志分开保留。

原生App三轮（360双倍、390普通、390普通）使用实际服务、生产安全日志适配器与私有磁盘，27根真实分页、一次恢复POST、免口令新代次、前快照原文件与源媒体SHA保持均独立核对。真实系统选择器另跑三轮40MiB取消/保存/重新选取/超限清理/主动取消；二者分开记证，不宣称一条大文件恢复整路或Android内存测量。App路径使用私有文件选择/保存适配器，不冒充系统选择器；没有把App重建当强停。

生产backup_v2仍关闭，8762只读源码夹具独立测试开放；没有改SDK、正式8760/NAS或发布APK。v2真实强停/新PID、完整历史专用清单与页细项接线、其它命令/来源组合、历史图片失败、暗色/横屏/手势、目标手机/NAS和原签名发布继续。原型树保持1cbf605且独立可移除；LF7/#32及总任务/#24保持开放。

## 2026-10-25：v2 App 三处真实强停与原日志重开（PR #54）

[Draft PR #54](https://github.com/ShiJiJS/video_viewer/pull/54)基于#53，固定源码2839c5d。真实v2完整替换在snapshot_written、after_replace_before_commit、restore_committed三个服务位置扣留202，安全日志先落盘；宿主强停活跃PID并确认消失后，服务在App缺席时完成同一任务，新PID免口令自动重连新代次。六条旧本机意图、原私有文件和两个真实受理的图包任务/原graph成员都保留；重开只GET和既有启动扫描，不重发原写入。实际系统快照保存取消后不结算旧记录，历史未提交选择不能继续删除。

固定源码三轮（360双倍字号115.47秒、390普通79.17/81.29秒）通过，164份manifest输入已入库并独立核对；首段有意强停的非零退出和开发失败日志分开保留。analyze/Ruff/Python语法及24项服务端针对检查通过。App/服务端生产树未改，433/398项全集沿用#53且本轮未重跑；这里不是40MiB全路恢复、Android内存或整机断电验证。[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/LF7-ARCHIVE-RESTART-DESIGN.md) / [固定源码、原始日志与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/evidence/lf7-archive-restart/README.md)。

接下来继续历史专用永久删除精确清单/逐页结果及只读页面（原graph绑定、有界分页、不得借用当前投影或执行/结算接口），然后其它命令/来源强停、历史图片失败、暗色/横屏/手势、目标设备/NAS和原签名发布。生产backup_v2仍关闭；原型树1cbf605独立未改，未改SDK/正式8760/NAS或发布APK。LF7/#32、总任务/#24保持开放。

后续专用历史接口与页面的源码审计及待实施检查见 [历史清单/逐页结果计划](LF7-HISTORY-DETAIL-PLAN.md)。

## 2026-10-26：原历史删除清单与逐项结果（PR #55）

[Draft PR #55](https://github.com/ShiJiJS/video_viewer/pull/55) 基于 #54，固定源码 `cabbc68`，证据提交 `0e0c1a5`。设置→操作任务→历史详情现可查看原确认清单、包内精确文件及永久删除的原图片/目录结果。三个认证 GET 绑定原 graph、父任务、计划与包条目；缺失或无效关联不退回当前库。文件 manifest 在 SQLite 内分页，App 专用网关没有执行、重试删除或结算能力，旧服务及缺失原图明确说明。

原生隔离8763真实扫描27包/153图，0101.png权限失败后实际126图已删、27图未完成；完整恢复后读回原历史。27包末3包、127图末页、54项目录、查询503保留原页再同GET重试及原预览入口均通过。固定源码三轮（360双倍字号64.96秒、390普通55.14/58.00秒），21张实际窗口截图、54份剩余源文件、原历史SQLite与三份真实安全日志前后核对；274份manifest输入已入库并独立校验。Paper比例延续既有页面，两尺寸目录结果及“图包根目录”文案复核通过。

完整客户端451项、服务端402项、analyze、Ruff lint和132份Python语法检查通过。服务端全集启动于9199f31、客户端全集于619033c，其完整服务端/客户端lib及test树均与固定源码相同。Ruff format继承23份、Dart format继承2份既有文件，未误报全量格式通过。实际43,806,720字节SQLite/18,000条manifest的分页Python分配峰值2,550,992字节，不能当作进程RSS、Android内存或NAS性能。首次Docker未加仓库规定shm参数的401通过/1失败、原生定位/等待失败和旧源码成功均单独留存。

[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/LF7-PURGE-HISTORY-DESIGN.md) / [原始证据与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/evidence/lf7-purge-history/README.md)。本段补齐BAK-03、SET-05、DEL-04/06的历史读取部分；其它命令/来源强停、历史图片解码/资源不可用、全原型暗色/横屏/手势、目标手机/NAS及原签名发布仍继续。生产backup_v2仍关闭，冻结原型树1cbf605独立未改；未改正式8760/NAS/SDK或发布APK。LF7/#32及总任务/#24保持开放。

## PR #90：完整备份公开入口与旧版兼容

[完整备份公开入口 PR #90](https://github.com/ShiJiJS/video_viewer/pull/90)。开发源码已声明backup_v2、移除测试额外注入，旧服务入口／v1任务协议与默认32 MiB保留。2f62dd0完整回归：客户端670项、服务端447项通过；27个既有文件格式未过，与基线相同。6287cc4正式原生一轮14点／15图、283输入只读复核通过，公开入口、真实系统文件与完整恢复走通。偶发上传连接失败尚未定位，已登记[#89](https://github.com/ShiJiJS/video_viewer/issues/89)，一次成功不能算修好。下一步定位该失败并验证原请求保留／重开只读核对；仍为草稿，未部署正式8760／NAS或发布APK，#24/#33/#32/#89保持开放。

[实现／后续](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/LF8-PUBLIC-BACKUPS.md)／[固定源码与原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/evidence/lf8-public-backups/README.md)。原生19,204字节同文件保存／读回SHA一致，27目录明确恢复、代次变化、两类后来标签移除与快照只预览通过；系统两种取消不新建导出／不上传。此前桌面无响应、上传失败、初扫409及文档XML未就绪分别保留；临时日志诊断通过不并入正式14点，通用传输未改、无自动重发。原型独立未改，容器／显示／自有AVD归还、原四服务ID不变。目标手机、云文档提供器、NAS及原签名覆盖升级仍待验收。

## PR #91：上传失败记录与真实进程找回

[上传失败原因与原任务找回 PR #91](https://github.com/ShiJiJS/video_viewer/pull/91)。App保留底层异常／等待阶段，提示及不重发写命令的规则不变；672客户端、28相关检查通过。848a1b8正式受控回复中断／双进程找回12点和普通完整恢复14点，共26点／28图，325输入复核通过；旧PID停止并移除本机输入后，新PID免口令只GET原任务、27目录预览且确认关闭。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复仍未完成，不把已受理回复中断当作原始问题。先前host归还显示失败已修，原配置恢复后重新验证通过；服务生产源码未改，27个旧格式问题待处理。原型独立未改、资源已归还，未部署NAS／发布APK，#24/#33/#32/#89保持开放。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/LF8-BACKUP-UPLOAD-DIAGNOSTICS.md)／[原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/evidence/lf8-backup-upload-diagnostics/README.md)。组件的真实拒绝连接／重建对象／缺少本机输入／两次原请求404，日志保留且零POST；明确区分内存日志与原生安全存储。受控样本读取回复时HttpException，重开14次GET、零POST、原键／同任务／SQL回执／代次相符；普通样本完整替换及快照只预览。中间d22d6fc覆盖屏幕配置变量导致归还失败，两例单列不计最终点，修正并使归还失败非零后重新验证。两类各一次，不称三轮稳定性；原始偶发原因、目标手机／NAS／云文档及覆盖升级继续。
