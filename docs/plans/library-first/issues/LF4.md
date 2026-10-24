总任务：#24

## 目标

当前底部仍以 browse 为主，视频库与标签直接修改播放范围。需要按确认原型形成完整产品导航，保证大小比例、分页和返回逻辑一致。

本任务属于 LF-2026-10-23 媒体库/图包改造；持续实施中。原生四入口、真实双类型分页、独立标签与来源、固定预览/返回、设置保留均已接线；视频标签独立分页、完整匹配范围全选/排除及每1000项追加已分别验证。图包名称与首50项外初选已补齐。

最新 `310482f`/`be7be51` 接入图包深列表稳定定位：原完整筛选下优先当前项/后邻居/前邻居，有限120项窗口前补与丢页补偿，失败/取消保留原列表和重试意图，迟到响应不移动新查询。当前171项客户端测试/静态检查、43项本次定位/图包/类型/选择相关服务端回归/Ruff通过；同提交真实Android完整路径连续三轮通过（360字号2一次、390两次）：73包、两标签交集+目录+搜索+未读，编辑移出交集、503重试、邻居定位48/24并保持37dp行内偏移、前补页及新增包后返回。此前图包名称、56项选择及工作区等证据各保留原提交，不混成同次验收。剩余来源/错误组合与旧流程回归继续验证，最近图包依赖LF5，因此不关闭issue。见 [LF4记录](../LF4.md)、[图包深列表证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf4-media-library/docs/plans/library-first/evidence/lf4-pack-anchor/README.md) / [草稿PR #38](https://github.com/ShiJiJS/video_viewer/pull/38)。

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
