总任务：#24

## 目标

现有数据库只有视频模型，roots 没有类型/启停，标签名称全局唯一；新原型要求视频与图包标签独立，并保留旧库。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

## 依赖

LF0 (#25)

## 实施范围

- roots 新增 kind/enabled，旧根默认 video/true；停用与离线分开，保留索引/标签/进度；已有内容的根不允许直接改类型。
- 旧 tags/video_tags 不变；新增 pack_tag_definitions/pack_tag_links，按类型校验读写与计数，跨类型同名合法。
- 定义 packs/pack_pages、进度/偏好、最近、包会话/条目及图包回收执行表；稳定 ID 和外键，不把图包页伪装成视频。
- 增量 Alembic 迁移保留视频、标签、轮次、历史物理回收与未确认命令；/info 增加 capabilities；固化查询/会话/读取/维护契约。
- 旧客户端新服务保留现有视频协议；新客户端旧服务能使用视频并明确图包能力不可用。

## 主要代码

- `services/server/video_viewer/models.py`
- `services/server/migrations/`
- `services/server/video_viewer/app.py`
- `apps/mobile/lib/library/models.dart`

## 完成标准

- [ ] 带标签/轮次/回执的 0004 库升级后数量和 ID 对照一致。
- [ ] 同名视频/图包标签独立，跨类型关联整次拒绝；停用不变成缺失清理。
- [ ] 迁移失败可恢复旧快照；新接口 OpenAPI 与客户端模型有契约测试。

验收 ID：TAG-01、PKG-02、SET-03/04、UP-01

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
