总任务：#24

## 目标

图包需快速移除并继续下一包，但源文件不能因为逻辑回收被移动，未知回执不能报成功，整包永久删除必须限定本次确认的文件清单。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，LF6 已开始实施，首批后端逻辑操作见下文，完整阶段保持开放。

## 依赖

LF3 (#28)、LF5 (#30)

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

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。


## 当前实施进度

[草稿PR #40](https://github.com/ShiJiJS/video_viewer/pull/40)，基于LF5 #39。逻辑后端、卡片与阅读器快速整理/准确撤销/待核对、设置内视频与图包独立回收站、跨页全选排除和批量恢复已接线。图包恢复使用独立trash IDs，24项分页、完整选择后按每批最多1000项提交；先持久化再POST，未知结果停止后续批次并只读核对原命令，失败项保留供重试。

实现524e89f及其大字号排布收尾：完整271项客户端测试/静态检查通过，30项图包服务端专项/Ruff通过。本轮生产后端未改，完整182项服务端基线来自上一检查点。Android真实HTTP回收站三轮44/49/46秒通过，覆盖首次读取503/重试、跨页27包选择排除、恢复已受理后503、GET原回执、阅读位置/偏好/标签/最近恢复和视频回收独立；各阶段81张合成图片哈希相同。阅读整理每轮8次的三轮67/68/67秒通过。大字号排布收尾另有一次完整原生流程及全量复核，分开标注来源。

Flutter 3.47.7 Slider跨帧弹层保存的语义断言已用延迟保存测试确定复现并以可交互状态Key修正，保留语义与实际滑动断言；SDK临时诊断后按原哈希恢复。该问题与两次历史下一包图片失败不同，后者仍未定位，不以复跑通过称已修复。

[实施记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/LF6.md)与[回收站证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf6-pack-cleanup/docs/plans/library-first/evidence/lf6-trash-client/README.md)保留源文件SHA、APK哈希、原始日志、请求和截图。真实NAS/正式8760未修改，未发布新版APK，原型继续隔离。

仍须继续：限定确认图片清单的永久删除/双确认/逐文件故障恢复；整份多批次计划持久化与统一任务（当前离页会停止后续未提交批次，关闭App未保留整份选择）；Android安全存储强杀重开、历史图片失败定位及DEL/REC/UI完整验收。issue与PR保持开放/Draft，不能把每批命令日志当作完整后台续作。
