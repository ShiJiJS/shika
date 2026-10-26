总任务：#24

## 目标

功能有按钮或APK能启动不等于实现了原型。最终需要同状态原生截图、完整真实服务流程和现有版本升级证据。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，当前实现和阶段证据见下方更新；整项尚未验收完成。

## 依赖

LF0 (#25), LF1 (#26), LF2 (#27), LF3 (#28), LF4 (#29), LF5 (#30), LF6 (#31), LF7 (#32)

## 实施范围

- 按 ACCEPTANCE.md 的 NAV/LIB/TAG/PRE/PKG/READ/REC/DEL/SET/BAK/UP/UI ID 填 RESULTS.md，每项附实现提交、步骤、证据、残余差异。
- 复用VS Code/F5与8760/8761隔离环境，旧视频回归+新图包API/迁移/任务故障测试；关键原生路径连续3轮。
- 同非私人素材、同状态做390×844并排，补360×740/横屏/暗色/大字体/键盘；动作与手势另录屏。
- 真实手机+NAS测首屏/首帧/翻页、p50/p95、内存、NAS CPU/IO/流量；破坏性测试仅可丢弃样本；模拟器不冒充真机性能。
- 先兼容服务端再App，保存升级前快照；原包名/签名、递增versionCode覆盖安装。回退服务用旧快照，不能旧二进制直接读新schema。

## 主要代码

- `docs/plans/library-first/ACCEPTANCE.md`
- `apps/mobile/integration_test/`
- `services/server/tests/`
- `scripts/run-client-connection-test.py`
- `docs/macos-development.md`

## 完成标准

- [ ] 所有验收ID有证据；必要功能、尺寸层级和返回行为与原型一致，偏差具体说明。
- [ ] 旧ID/标签/回执/连接/本机偏好保留，旧版覆盖升级可重复。
- [ ] 总任务只有此验收完成才关闭；未实测或仅Demo完成的项目保持未完成。

验收 ID：全部验收项；真实目标环境验证是独立门槛。

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与冻结原型已由LF0纳入Git；独立参考现位于`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。

## 2026-10-25：PR #47 原生截图复查项

#47的目录类型/启停、分类型缺失页、固定清理与原回执路径在固定59f78b6原生三轮通过，27检查点的窗口/请求/文件/数据库与源码已独立复核；不等于LF8整项通过。证据：[目录与缺失管理](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-roots-missing/docs/plans/library-first/evidence/lf7-roots-missing/README.md)。

- [ ] 新建目录尚未首次扫描时，当前沿用红色“目录暂不可用”；统一未扫描、离线、停用状态与提示，避免混淆。
- [ ] 任务详情SelectableText编号在部分普通/双倍字号截图中缺字或裁剪；需复查实际渲染与采集时序并修正，不能以接口任务ID正确替代文本显示验收。
- [ ] 继续完整深浅色、横屏、视频手势与目标手机/NAS验收；当前App/Repository重建是在同一进程，不算新增强停证据。

系统ANR曾真实遮挡早期截图，已保留诊断和受控恢复记录。正式三轮每个截图均要求App持有Android前台焦点，系统窗口遮挡会让宿主验收失败。原型基线保持独立未改，未发布APK。
## 2026-10-26：共享比例与原型收口台账（PR #58）

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)基于#57。固定App与最终原生源码a9da395，证据提交6b71cd1：两类库统一搜索55dp/输入42dp/文字16dp、范围工具60dp，顶栏与300dp居中导航对齐；设置开关约40×24可见、整行至少64dp可点，保留原回调/存储并覆盖键盘/单一开关语义；设置分组、标签确认区及文案密度已调整。

真实8768新库的2视频/4包/24图，普通字号三轮、360双倍字号与844短横屏各一轮通过，共40个前台ADB检查点。16项针对组件检查、analyze/Ruff通过，235份manifest输入的源码、实际背景像素、窗口、源字节、SQLite数量及设备配置恢复独立核对通过。两轮独立存量视觉评审后，本轮问题已复核处理；早期主题过渡帧和屏外懒加载前置失败均单列诊断。没有重跑所有业务/服务端全集。

[45项收口台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/RESULTS.md) / [具体差异与尺寸边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/LF8-SHARED-GEOMETRY.md) / [原始证据和只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-prototype-fidelity/docs/plans/library-first/evidence/lf8-shared-geometry/README.md)。HTML390×844去掉12px假系统区、原生390×905去掉实际49/24dp系统区后比较390×832内容，不拉伸Android画面；大字和横屏按各自实测安全区分别记证。

尚需推进（不关闭LF8或总任务）：
- [x] 图包库真实继续阅读区与原范围返回。
- [x] 权威两类库存计数；不能用分页缓存或当前筛选数冒充。
- [ ] 可识别的图包标题/作者与保守回退，以及服务端排序/分页/范围一致性。
- [ ] 预览、阅读、管理、键盘和动作的完整同版对照；500页4K/8K性能、目标手机/NAS与原签名升级发布。

冻结原型树1cbf605仍独立可移除，未改正式8760/NAS/SDK或发布正式APK；生产backup_v2仍关闭。#33与#24保持开放。


## 2026-10-26：图包库真实继续阅读（PR #59）

[Draft PR #59](https://github.com/ShiJiJS/video_viewer/pull/59)基于#58，固定源码c4aaf3b，证据提交daf1863。图包媒体库在无筛选/搜索且非多选时显示真实最近打开包与页码；摘要独立于24条分页和列表取消通道，只读且不创建历史。点击从该包续读，保持原媒体库完整范围，返回原位置。搜索、多选、最近来源不展示全库续读条；失败保留列表并就地重试。

普通三轮、360双倍字号及844短横屏共五轮同源码通过，每轮10个真实前台检查点，共50图；公开2视频/4包/24PNG，实际打开后从3/6翻到4/6，续读仍为完整4包范围。两次显式opened、SQL最近/进度/会话投影、只读区间、26个源文件SHA与设备配置恢复均核对。202份manifest输入只读校验通过。客户端471项、服务端续读/阅读16项、analyze/Ruff通过；不是服务端全集或目标设备性能证明。

原生字体的实际行高取代估算，普通续读86dp（参考85）、双倍字号147dp，无裁切；共享“更多”菜单收起搜索键盘，修复短横屏进入多选时的4.7dp溢出。两轮独立存量视觉复核后无本段必须修正项；首轮材料、字体/键盘失败诊断与最终五轮分别保存。长标题/错误说明省略仍是已知显示边界，未缩字号或缩短压力输入。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/LF8-PACK-CONTINUATION.md) / [原始证据与可重跑校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/evidence/lf8-pack-continuation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/RESULTS.md)。本段补LIB-02、NAV-02、READ-04/05、REC-01与UI-01/04/05的明确组合，不关闭整项；使用MemoryCredentialStore，不新增强杀/安全存储或覆盖升级证明。

下一步继续权威两类总数、保守标题/作者与服务端排序，再核对完整预览/阅读/管理、键盘和手势；500页4K/8K、目标手机/NAS和原签名升级仍待验证。冻结原型1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：媒体库权威分类总数（PR #60）

[Draft PR #60](https://github.com/ShiJiJS/video_viewer/pull/60)基于#59，固定实现910cfb2、证据提交b927026。媒体库“视频 N / 图包 N”复用library-state中的同一SQLite只读快照，按实际完整可浏览目录计数；搜索零结果和分页不改写全库数，标签/最近隐藏标记。失败显示“—”并可点分类重试，旧服务隐藏；连接代次和请求顺序拒绝旧响应，图包操作后只读重取。

客户端485项、服务端相关75项、analyze/Ruff通过。普通三轮、大字、短横屏五轮同源码共45个库存检查点，真实逻辑回收/恢复2/4→2/3→2/4，完整进度不变、最近/阅读会话0；同源码另10个续读回归检查点通过。215份manifest输入核对源码、55个前台窗口/原始图、SQL投影、26个源SHA与设备恢复；并发提交测试证明两个总数来自同一快照。75项是相关服务回归，不是服务端全集或目标机性能。

受影响147dp顶栏与4785a69已实际渲染的冻结参考同状态并排；图包正文历史、标题/作者与排序仍有差异，不宣称整页完全一致。横屏键盘过渡暴露非当前标签页61dp可用高度下的79dp溢出，改为按实际空间约束并滚动操作区；两类标签缩高/恢复与原生横屏通过。正式取证不忽略Flutter异常，早期失败日志单列；本段未新增独立视觉评审或手势录屏。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/LF8-CATALOG-COUNTS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/evidence/lf8-catalog-counts/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/RESULTS.md)。本段补LIB-01/02、UI-01/04/05的明确组合，不关闭整项。管理网关用于验证计数更新，不替代删除确认UI验收；MemoryCredentialStore不新增强杀/安全存储证明。

下一段继续保守标题/作者与服务端一致排序，随后完整预览/阅读/管理、键盘手势、500页4K/8K、目标手机/NAS和原签名覆盖升级。冻结原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。
