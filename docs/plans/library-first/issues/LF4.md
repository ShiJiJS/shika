总任务：#24

## 目标

当前底部仍以 browse 为主，视频库与标签直接修改播放范围。需要按确认原型形成完整产品导航，保证大小比例、分页和返回逻辑一致。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

## 依赖

LF2 (#27)、LF3 (#28)

## 实施范围

- 默认媒体库；底部媒体库/标签/最近/设置。库与标签内 video/pack 分类独立保存搜索、筛选、排序、选择与滚动位置。
- 视频/图包双列卡片、搜索、目录/交集筛选、排序、批量追加标签、空结果及加载错误；按真实接口分页。
- 标签 CRUD、名称搜索、独立计数；选条件先看结果或进入对应预览/阅读。最近按类型展示并从最近来源生成会话。
- 统一 P2 token：52顶栏，49导航内容+系统安全区，16侧距/12列距/18行距，390宽封面211、360宽185，标题16，设置行15。
- 复用 Paper 深浅主题；不画 HTML 的假 home indicator；透明扩触控区不放大视觉卡片。Demo可先搭页面，真实服务依赖完成后才关闭。

## 主要代码

- `apps/mobile/lib/app/（新增）`
- `apps/mobile/lib/features/library/（新增）`
- `apps/mobile/lib/features/recent/（新增）`
- `apps/mobile/lib/ui/home.dart`
- `apps/mobile/lib/ui/paper.dart`

## 完成标准

- [ ] NAV/LIB/TAG/REC 相关流程用真实分页接口走通，不从局部 snapshot 估全库。
- [ ] 390×844 并排原型截图，360×740/横屏/大字体无溢出；入口、密度和返回行为一致。
- [ ] 每个页面具备初载、空、失败、重试与旧数据保留状态。

验收 ID：NAV-01–03、LIB-01–03、TAG-01/02、REC-01、UI-01/05

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
