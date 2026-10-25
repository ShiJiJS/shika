总任务：#24

## 目标

已确认设置原型补回当前客户端必要能力。正式实现不能只复刻页面：目录启停、任务核对、图包备份和恢复映射必须接真实服务。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，当前实施中；统一任务入口已接真实服务，完整设置与管理备份 v2 继续推进。

## 依赖

LF1 (#26)、LF2 (#27)、LF6 (#31)

## 实施范围

- 三组设置：连接与文件、数据维护、偏好；地址/端口/口令、根类型/启停/扫描/缺失、回收、任务、备份、主题/相邻准备/默认顺序/阅读默认值全部接线。
- 长管理全高度页，短编辑/确认底部面板；输入失败保留；扫描/恢复/删除待确认统一可查询，但使用各自真实任务回执。
- 默认顺序与阅读默认值、逐包偏好/进度是管理数据；主题/相邻准备/凭据是本机数据，不进入NAS备份。
- LF3 的 `UiPreferences.videoOrder` 是会话隔离期间的临时本机默认。接入服务端默认时须明确已有本机值的迁移与冲突规则、按连接隔离，并验证切换服务/恢复 v2 备份不会改当前预览范围；不能把临时本机字段直接当作最终备份设计。
- 正式备份v2覆盖两类标签/包页身份/进度/最近/根/会话/回收/回执，排除媒体/缓存/凭据；v1先校验再转换成video及空图包状态，明确完整替换影响。
- 保留统计预览、根映射/空映射、显式确认、恢复前快照、任务异步/响应丢失只读核对，历史操作不重放，永久删除内容不复活。HTML localStorage备份不兼容正式协议。

## 主要代码

- `apps/mobile/lib/features/settings/（新增）`
- `apps/mobile/lib/library/server_backups.dart`
- `apps/mobile/lib/library/backup_work_store.dart`
- `services/server/video_viewer/backups.py`
- `services/server/video_viewer/backup_format.py`
- `services/server/video_viewer/backup_reconcile.py`

## 完成标准

- [ ] SETTINGS-AUDIT.md 必要项逐项对应，不能因为新结构删除旧能力。
- [ ] v1→新库、v2往返、根重映射、坏包/中断/存储失败/响应丢失通过隔离真实服务验证。
- [ ] 主题/预加载/连接不被恢复覆盖，恢复前快照可下载，任务查询不自动执行旧命令。

验收 ID：SET-01–05、BAK-01–03、DEL-04/06、UI-03/04

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。

## 2026-10-25 统一任务阶段

已接设置“操作任务”、24条真实服务分页、类型/状态筛选和成员详情；原回执只读核对、迟到旧请求隔离、原导出校验与取消保存保留记录。当前316项客户端、271项服务端/Ruff及analyze通过。固定源码 `92d9b15` 连续三轮真实Android通过（390普通、360双倍字号、390普通）：81张图片哈希不变，任务入口全GET、同一原备份下载两次。PR #41 基于 #40。详细范围和证据见 `docs/plans/library-first/LF7.md`。

整份多批次计划、完整设置审计、服务端默认值/旧本机值迁移、v2/v1转换与恢复前快照、安全存储强杀仍未完成；原导出下载不代表图包v2备份已完成。本 issue 与总任务保持开放。冻结原型独立且未修改。

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
