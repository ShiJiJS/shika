总任务：#24

## 目标

图包需快速移除并继续下一包，但源文件不能因为逻辑回收被移动，未知回执不能报成功，整包永久删除必须限定本次确认的文件清单。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，LF6 已开始实施，首批后端逻辑操作见下文，完整阶段保持开放。

## 依赖

LF3 (#28), LF5 (#30)

## 实施范围

- 普通卡片菜单确认整包回收；库/阅读器显式开启快速整理后直接回收，成功才进入本范围下一包，失败留原包，末尾返回来源。
- 8秒撤销绑定 operation ID，保存包ID/页码/队列位置/模式；旧撤销不误撤最新操作。保留现有视频异步跟手机制。
- 按类型回收站、跨页全选、批量恢复，逻辑标记/恢复不移动源文件，保留标签/进度；旧视频物理回收兼容。
- 永久删除双确认，限定已索引图片清单；执行前核对版本和签名，新增/替换/歧义停止重新核对；附件保留、仅清空空目录；部分成功逐项报告。
- 持久化命令与任务、幂等/互斥/崩溃恢复；断线重开只读查询原请求，不自动重放；重试只执行未完成项。

## 主要代码

- `services/server/video_viewer/pack_operations.py（新增）`
- `services/server/video_viewer/file_operations.py`
- `apps/mobile/lib/library/file_command_store.dart`
- `apps/mobile/lib/features/packs/`
- `apps/mobile/lib/features/settings/`

## 完成标准

- [ ] 下一包/末尾/单包/失败/连续操作/撤销位置均用原生流程覆盖。
- [ ] 可丢弃目录操作前后哈希证明逻辑回收不改字节；永久删除不误删新增/替换/附件。
- [ ] 断线、响应丢失、部分失败和服务重启均可查询原结果，无全局UI锁。

验收 ID：DEL-01–06、UI-02/04

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。规划与冻结原型已推送GitHub，原型独立位于 `design/reference/library-first/`（标记design-lf-2026-10-23），后续可单独移除；设置差异见 `SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。


## 当前实施进度

[草稿PR #40](https://github.com/ShiJiJS/video_viewer/pull/40)，基于LF5 #39。逻辑后端、卡片与阅读器快速整理/准确撤销/待核对、设置内视频与图包独立回收站、跨页全选排除和批量恢复已接线。图包恢复使用独立trash IDs，24项分页、完整选择后按每批最多1000项提交；先持久化再POST，未知结果停止后续批次并只读核对原命令，失败项保留供重试。

实现524e89f及其大字号排布收尾：完整271项客户端测试/静态检查通过，30项图包服务端专项/Ruff通过。本轮生产后端未改，完整182项服务端基线来自上一检查点。Android真实HTTP回收站三轮44/49/46秒通过，覆盖首次读取503/重试、跨页27包选择排除、恢复已受理后503、GET原回执、阅读位置/偏好/标签/最近恢复和视频回收独立；各阶段81张合成图片哈希相同。阅读整理每轮8次的三轮67/68/67秒通过。大字号排布收尾另有一次完整原生流程及全量复核，分开标注来源。

Flutter 3.47.7 Slider跨帧弹层保存的语义断言已用延迟保存测试确定复现并以可交互状态Key修正，保留语义与实际滑动断言；SDK临时诊断后按原哈希恢复。该问题与两次历史下一包图片失败不同，后者仍未定位，不以复跑通过称已修复。

[实施记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6.md)与[回收站证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-trash-client/README.md)保留源文件SHA、APK哈希、原始日志、请求和截图。真实NAS/正式8760未修改，未发布新版APK，原型继续隔离。

新增清单准备 **bdbd741**：后台只读核对目录/图片签名与SHA，持久化精确文件清单、保留项和摘要；请求回执不重算，完成后15分钟期限，服务重建只重做未完成准备，历史计划不可确认。完整214项服务端/Ruff通过（新增32项），包含非空0009→0010迁移和8万条持久化明细的轻量汇总检查。仅声明pack_purge_preview，没有物理删除执行路由或App双确认；[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6-PURGE-DESIGN.md)与[证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-plans/README.md)独立保存，新清单接口未作Android UI验收。

执行后端 **5e89a1a / dd2dcf3** 已接：严格确认绑定plan/digest/request，单计划单操作；逐页认领后SHA复核、持久化日志与空目录非递归清理。新增/替换/冲突时保留内容，已归档页不重复删除或计数；部分已删页退出可读清单，剩余内容可恢复，待核对保持互斥。所属旧8秒逻辑撤销失效，无关最新撤销保持有效。完整264项服务端/Ruff通过（新增50项），两条真实HTTP SIGKILL流程各三轮通过，另有十阶段合作式中断冷重建；清单状态/摘要跨查询竞争已有确定性红绿复现并修正。新内容重现旧路径获得新ID，不继承旧标签。原始日志、源码SHA和边界见[执行检查点](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-execution/README.md)。本轮未改客户端，尚无App双确认或新原生验收，App永久删除能力标志暂不开放。

仍须继续：整份多批次计划持久化与统一任务（当前离页停止后续未提交批次，关闭App未保留整份选择）；Android安全存储强杀重开、历史图片失败定位及DEL/REC/UI完整验收。issue与PR保持开放/Draft，每批命令日志不等于完整后台续作。

## App永久删除接线（最新检查点，2026-10-25）

实现 **2d97cc9**、原生截图等待调整 **c55e95c**：设置→图包回收站→准备精确清单→分页核对图片→勾选不可恢复声明→确认永久删除→逐项结果。附件保留，取消/过期/连接变化不提交；超过1000包逐批核对，其余选择保留。

确认范围和plan/digest/request先落命令日志，未知响应重开只GET原请求；部分条目明确已删/剩余数量并可重进原结果，needs_attention不清日志。原任务显式重试只处理原清单，旧结果确认不会清掉后来受理的重试。

完整 **293项客户端/analyze、265项服务端/Ruff**通过。冷启动后的API36 Android关键流程连续三轮通过（390正常、360两倍字号、390正常，均51秒）；每轮108份文件，取消不变，部分后106、原任务重试后105，27份附件哈希全部保持，只有1次永久删除POST。真实HTTP大整数签名兼容问题已修正；早期夹具422和模拟器QEMU退出均单独保留为失败诊断，不计入三轮。

[App契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6-PURGE-CLIENT-DESIGN.md) / [完整证据与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-purge-client/README.md)。冻结原型独立且未改；按DEL-05只删确认图片并保留附件，与原型“删除整目录”的文案差异已记录。原生仓库使用内存注入，不能冒充SecureStorage强杀冷启动验证；没有发布升级APK，也未部署NAS。

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
