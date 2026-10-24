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
