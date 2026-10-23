总任务：#24

## 目标

已确认设置原型补回当前客户端必要能力。正式实现不能只复刻页面：目录启停、任务核对、图包备份和恢复映射必须接真实服务。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

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
