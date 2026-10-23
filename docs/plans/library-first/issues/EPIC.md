## 目标

将现有 0.1.4+5 Android App 升级为已确认的「媒体库为中心、视频与图包分别管理」完整产品。用户于 2026-10-23 确认当前 `design/reference/library-first/` 原型方向并要求先确定框架、写规划和 GitHub issues。当前 LF0–LF2 已实现并验证，等待依赖 PR 合并；LF3 固定预览与原生兼容实施中，LF4–LF8 待实施，尚未发布新版。

这是后续升级，不覆盖 #1 的历史 V1 规格，也不把 #23 仍未完成的目标环境验收标记为已完成。

## 产品契约

- 默认进入媒体库；底部为媒体库 / 标签 / 最近 / 设置。视频与图包各自保存筛选和列表位置。
- 视频、图包从库或各自标签/最近的结果进入预览/阅读；完整范围在服务端固化，不能只预览已加载第一页，不能丢失名称搜索，不能自动跳全库。
- 视频与图包标签分开，同名独立。图包是一包一卡、整包标签，无单张管理。
- 图包支持横向翻页、纵向拼接、总览、沉浸、每包进度/偏好、限定范围手动换包；快速整理明确开启、逻辑回收、准确撤销。
- 设置完整保留连接、目录管理与扫描/缺失、批量回收/永久删除、任务查询、备份映射和恢复前快照，以及本机主题/相邻视频准备。
- 保留现有原生视频暂停、倍速、长按2倍、跟手滑动、横屏、亮度/音量和资源上限。
- 视觉沿用 P2：52 顶栏、49 导航内容+系统安全区、16侧距/12列距/18行距、390宽封面211、360宽185、16卡片标题、15设置标题。Android 不额外画 HTML 假 home indicator。

## 已确定的技术框架

继续 Flutter + ChangeNotifier、FastAPI + SQLite/Alembic、Docker 单服务。拆分 AppShell、LibraryQueryController、VideoPreview/PreviewSession、PackReadingSession、MaintenanceController；复用 PlaybackSession、鉴权传输、持久化任务与文件回执。Server 与 Demo 通过相同行为接口验证，页面不直接读 NAS。

旧视频模型、tags/video_tags、ID 与操作记录保留；新增 pack/pack_pages、独立 pack_tag_definitions/pack_tag_links、阅读进度/偏好、最近和包会话。roots 增加 kind/enabled，历史默认 video/true。查询草稿不再修改正在播放的轮次；新固定成员协议不因改标签重排，返回列表才重新查询。

图包首版以根直属文件夹为包，子目录递归归同包、相对路径自然排序；JPEG/PNG/WebP 静态图片。原图/缩略图按稳定 ID 授权读取，采用惰性列表、有限解码窗口和缓存。停用/离线不清理元数据，新图包首扫不阻塞可用视频。

正式备份升级 v2、校验转换旧 v1，显示完整替换影响；主题/相邻准备/凭据不入 NAS 备份。未知操作只读查询，不自动重发；整包永久删除限定确认的图片清单，核对版本与替换，非图片附件保留。先隔离迁移演练，后兼容服务端，再同包名/原签名/递增 versionCode 的 App；回退恢复旧管理快照。

## 实施任务

当前 PR：[LF0 #34](https://github.com/ShiJiJS/video_viewer/pull/34) → [LF1 #35](https://github.com/ShiJiJS/video_viewer/pull/35) → [LF2 #36](https://github.com/ShiJiJS/video_viewer/pull/36) → [LF3 草稿 #37](https://github.com/ShiJiJS/video_viewer/pull/37)。前序阶段实现完成不等于整体原型验收完成，子任务等待对应依赖合并。

- [ ] https://github.com/ShiJiJS/video_viewer/issues/25 — [LF0] 锁定原型基线与可运行的模块骨架
- [ ] https://github.com/ShiJiJS/video_viewer/issues/26 — [LF1] 兼容迁移数据模型：媒体类型、图包标签与服务能力
- [ ] https://github.com/ShiJiJS/video_viewer/issues/27 — [LF2] 图包扫描、分页目录与授权图片读取
- [ ] https://github.com/ShiJiJS/video_viewer/issues/28 — [LF3] 视频从入口范围进入固定预览会话，保留原生播放能力
- [ ] https://github.com/ShiJiJS/video_viewer/issues/29 — [LF4] 原生四入口外壳、双类型媒体库与独立标签页
- [ ] https://github.com/ShiJiJS/video_viewer/issues/30 — [LF5] 图包阅读器：横翻、纵向拼接、范围与续读
- [ ] https://github.com/ShiJiJS/video_viewer/issues/31 — [LF6] 图包快速整理、准确撤销及安全的回收站操作
- [ ] https://github.com/ShiJiJS/video_viewer/issues/32 — [LF7] 设置完整接线、统一任务与兼容的管理备份 v2
- [ ] https://github.com/ShiJiJS/video_viewer/issues/33 — [LF8] 原型一致性验收、真实服务联调与兼容升级包

依赖顺序：LF0 → LF1 → LF2/LF3 → LF4 → LF5 → LF6 → LF7 → LF8。LF4 可提前用 Demo 搭页面，但真实接口未接不能关闭。

## 防止最终偏离原型

- 本地 `docs/plans/library-first/PLAN.md` 是详细框架、源码差距和迁移方案；`ACCEPTANCE.md` 列出功能及视觉验收 ID；`baseline.json` 固定当前源码/依赖/截图 SHA-256。
- 方案与独立原型已随 LF0 纳入版本控制；参考 tag 为 `design-lf-2026-10-23`，不属于 App 构建。私人图包与密钥不上传。本 issue 及子任务已包含独立可读的范围和完成标准。
- 每个 PR 引用验收 ID、实现提交和实际证据。使用相同非私人素材与状态，390×844 原型/Flutter 并排，补 360×740、横屏、暗色、大字体、键盘。
- 旧功能回归、公开接口/迁移/故障恢复、原生真实服务流程、截图与动作录屏分开验收；关键完整路径连续3轮，不能用 HTML 或 Demo 成功替代真实服务。
- 真机/NAS记录首屏、翻页、p50/p95、内存、CPU/IO/网络；破坏性操作仅在可丢弃测试目录。历史环境记录不是新功能通过证据。
- 必要页面、入口、尺寸、范围、撤销、错误/恢复行为全部有证据，LF8 完成才关闭本任务；行为变动须在对应 issue 列明原因与原型差异。

## 本轮不做

无压缩包直读、单张图片标签/删除、AI标签、离线下载、自动文件夹归档、多用户或新微服务。当前开发与故障验证使用隔离实例和合成媒体，尚未部署 NAS 或发布升级 APK；正式交付按 LF8 验收与迁移流程推进。
