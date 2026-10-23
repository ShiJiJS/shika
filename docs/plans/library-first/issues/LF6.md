总任务：#24

## 目标

图包需快速移除并继续下一包，但源文件不能因为逻辑回收被移动，未知回执不能报成功，整包永久删除必须限定本次确认的文件清单。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

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
