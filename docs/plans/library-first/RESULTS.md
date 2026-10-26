# LF0–LF8 逐项收口台账（进行中）

更新：2026-10-26。总任务#24、LF8/#33保持开放。此表把已有阶段证据与剩余工作放在同一入口；“有阶段证据”不代表整项通过。原生界面、业务行为、服务端安全、性能和发布分别核对，不能互相替代。

共享布局阶段基线为a9da395；最新图包续读阶段源码为c4aaf3b，见[真实续读约定](LF8-PACK-CONTINUATION.md)与[原生证据](evidence/lf8-pack-continuation/README.md)。后续分类总数阶段源码910cfb2，见[库存约定](LF8-CATALOG-COUNTS.md)与[库存/横屏及续读回归证据](evidence/lf8-catalog-counts/README.md)。该段补同快照总数、未知重试和标签缩高布局；续读段新增真实续读、独立摘要读取与菜单收键盘；共享布局的设置开关、标签确认区和主题稳定证据继续作为历史基线。图包呈现/排序阶段为4e391a2，见[约定](LF8-PACK-PRESENTATION.md)与[69点同版证据](evidence/lf8-pack-presentation/README.md)；主标题/作者和完整范围排序已补，新增大字长操作行可达性修正。原型树1cbf605未改。各阶段链接中的实现提交、真实服务/Demo区分、操作步骤与原始证据继续有效，但未来修改后须按受影响路径复核，不能把历史全集视为当前HEAD所有组合已通过。

最新卡片/网格阶段固定e53e173，见[实现约定](LF8-CARD-LAYOUT.md)及[67点同版证据](evidence/lf8-card-layout/README.md)。共享标签12/1.6、4dp上距、作者/方向色及短横屏四列已补；501项客户端通过，服务生产树未改且本段未重跑服务端。其余验收仍按下表开放项推进。

| 验收ID | 当前证据状态 | 证据入口（含该阶段实现提交/步骤） | 尚需完成 |
| --- | --- | --- | --- |
| NAV-01 | 已有阶段证据 / 未收口 | [LF4设计与阶段记录](LF4.md) | 合并当前分支后复跑完整来源/筛选/冷启组合，并记录实际系统返回路径。 |
| NAV-02 | 已有阶段证据 / 未收口 | [LF4设计与阶段记录](LF4.md) | 合并当前分支后复跑完整来源/筛选/冷启组合，并记录实际系统返回路径。 |
| NAV-03 | 已有阶段证据 / 未收口 | [LF4设计与阶段记录](LF4.md) | 合并当前分支后复跑完整来源/筛选/冷启组合，并记录实际系统返回路径。 |
| LIB-01 | 新增视频中文顺序证据 / 未收口 | [LF4阶段记录](LF4.md)、[权威总数](evidence/lf8-catalog-counts/README.md)、[中文顺序](evidence/lf8-video-name-order/README.md) | 分类总数及视频列表/锚点/全选/固定范围的中文顺序已补证；文件名/时长显示、完整最近和长列表最终来源/失败组合继续。 |
| LIB-02 | 新增卡片/网格证据 / 未收口 | [LF4阶段记录](LF4.md)、[续读](evidence/lf8-pack-continuation/README.md)、[总数](evidence/lf8-catalog-counts/README.md)、[呈现/排序](evidence/lf8-pack-presentation/README.md)、[卡片/网格](evidence/lf8-card-layout/README.md) | 标题/作者、完整范围中文排序、共享标签12/1.6与4dp间距及短横屏四列已补证；长列表完整来源/失败组合继续。 |
| LIB-03 | 新增视频跨页顺序证据 / 未收口 | [LF4阶段记录](LF4.md)、[摘要独立于分页](LF8-PACK-CONTINUATION.md)、[视频排序约定](LF8-VIDEO-NAME-ORDER.md) | 图包28项和视频27项分别补完整排序/锚点/全选/固定范围一致，新增/改名后不重排；完整来源/跨页失败组合继续。 |
| TAG-01 | 已有阶段证据 / 未收口 | [LF1](LF1.md)、[LF4](LF4.md) | 两套真实标签已有阶段证据；名称排序、跨页/编辑/失败和完整视觉仍需最终同版复核。 |
| TAG-02 | 已有阶段证据 / 未收口 | [LF1](LF1.md)、[LF4](LF4.md) | 两套真实标签已有阶段证据；名称排序、跨页/编辑/失败和完整视觉仍需最终同版复核。 |
| PRE-01 | 已有阶段证据 / 未收口 | [LF3](LF3.md) | 最终同版手势录屏、全屏/后台/相邻解码与范围组合；目标手机验证。 |
| PRE-02 | 已有阶段证据 / 未收口 | [LF3](LF3.md) | 最终同版手势录屏、全屏/后台/相邻解码与范围组合；目标手机验证。 |
| PRE-03 | 已有阶段证据 / 未收口 | [LF3](LF3.md) | 最终同版手势录屏、全屏/后台/相邻解码与范围组合；目标手机验证。 |
| PRE-04 | 已有阶段证据 / 未收口 | [LF3](LF3.md) | 最终同版手势录屏、全屏/后台/相邻解码与范围组合；目标手机验证。 |
| PRE-05 | 已有阶段证据 / 未收口 | [LF3](LF3.md) | 最终同版手势录屏、全屏/后台/相邻解码与范围组合；目标手机验证。 |
| PKG-01 | 已有阶段证据 / 未收口 | [LF2](LF2.md) | 最终同版重扫/离线/缺失/失败读取组合；真实NAS可丢弃样本复核。 |
| PKG-02 | 已有阶段证据 / 未收口 | [LF2](LF2.md) | 最终同版重扫/离线/缺失/失败读取组合；真实NAS可丢弃样本复核。 |
| PKG-03 | 已有阶段证据 / 未收口 | [LF2](LF2.md) | 最终同版重扫/离线/缺失/失败读取组合；真实NAS可丢弃样本复核。 |
| READ-01 | 已有阶段证据 / 未收口 | [LF5](LF5.md) | 最终同版横纵/方向/恢复/缩放/范围组合及手势、性能和目标手机验证。 |
| READ-02 | 已有阶段证据 / 未收口 | [LF5](LF5.md) | 最终同版横纵/方向/恢复/缩放/范围组合及手势、性能和目标手机验证。 |
| READ-03 | 已有阶段证据 / 未收口 | [LF5](LF5.md) | 最终同版横纵/方向/恢复/缩放/范围组合及手势、性能和目标手机验证。 |
| READ-04 | 已有阶段证据 / 未收口 | [LF5](LF5.md) | 最终同版横纵/方向/恢复/缩放/范围组合及手势、性能和目标手机验证。 |
| READ-05 | 已有阶段证据 / 未收口 | [LF5](LF5.md) | 最终同版横纵/方向/恢复/缩放/范围组合及手势、性能和目标手机验证。 |
| READ-06 | 待性能实测 | [LF5](LF5.md) | 500页及4K/8K：目标机峰值、p50/p95与NAS开销尚未实测；小型模拟器图包不能替代。 |
| REC-01 | 新增最近形态阶段证据 / 未收口 | [LF5最近](LF5-RECENT-DESIGN.md)、[LF4](LF4.md) | 最近行和显示信息已实现，2e971ac新增15个真实点；bd2b34f键盘/错误修正仍待最终同版原生重复与视觉复核，回收/恢复和三来源组合继续。 |
| DEL-01 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-02 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-03 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-04 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-05 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-06 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| SET-01 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| SET-02 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| SET-03 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| SET-04 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| SET-05 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| BAK-01 | 已有阶段证据 / 未收口 | [LF7](LF7.md)、[原生完整恢复](evidence/lf7-archive-restart/README.md) | backup_v2生产能力仍关闭；真实选择器/大文件有界传输、更多故障与最终整条流程继续。 |
| BAK-02 | 已有阶段证据 / 未收口 | [LF7](LF7.md)、[原生完整恢复](evidence/lf7-archive-restart/README.md) | backup_v2生产能力仍关闭；真实选择器/大文件有界传输、更多故障与最终整条流程继续。 |
| BAK-03 | 已有阶段证据 / 未收口 | [LF7](LF7.md)、[原生完整恢复](evidence/lf7-archive-restart/README.md) | backup_v2生产能力仍关闭；真实选择器/大文件有界传输、更多故障与最终整条流程继续。 |
| UP-01 | 已有阶段证据 / 未收口 | [LF1](LF1.md)、[本机开发配置](../../macos-development.md) | 目标手机原签名覆盖安装、同版旧服务/客户端组合和发布回退演练继续。 |
| UP-02 | 待发布演练 | [LF1](LF1.md)、[本机开发配置](../../macos-development.md) | 迁移原签名的授权与准备不等于已覆盖安装；未发布本轮APK。 |
| UI-01 | 新增视频中文顺序对照 / 未收口 | [共享差异审计](LF8-SHARED-GEOMETRY.md)、[卡片/网格](evidence/lf8-card-layout/README.md)、[视频中文顺序](evidence/lf8-video-name-order/README.md) | 共享尺寸、续读/分类总数、两类中文顺序及卡片已补证；新视频对照等真实ready后采集。文件名/时长显示、标签顺序/图标、完整最近及其它完整页面继续。 |
| UI-02 | 阶段证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md) | 沿用LF3/LF5/LF6局部原生证据；本轮未重新验证阅读器/预览/整理全链和手势录屏。 |
| UI-03 | 局部证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md) | 设置普通/暗色/页底与共享密度已补证；目录、缺失、回收、备份、任务等完整管理页继续。 |
| UI-04 | 阶段证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md) | 共享16项针对检查含设置开关语义；新增续读错误/重试、多选收键盘与大字/短横屏证据；库存段补未知重试与标签61dp缩高/恢复。完整原生表单、恢复和其它错误组合继续。 |
| UI-05 | 新增网格重排证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md)、[卡片/网格](evidence/lf8-card-layout/README.md) | 本段普通三轮/大字/短横屏实际窗口另补；120项两类组件验证旋转/字号变更锚点及不重查，原生固定视口不冒充深列表旋转。完整状态与目标设备继续。 |
| UI-06 | 待完整动作收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md) | 沿用已有路由/加载与减少动态效果；新增续读有逐步点击/回读，但尚无完整动作时长/手势录屏。 |

## 下一段推进顺序

1. 先恢复本轮模拟器配置与系统服务可用性，补bd2b34f最近记录的普通三轮、大字/短横屏、错误提示同项复核。15张2e971ac阶段图不能替代最新版本验收；然后继续其余页面/动作。
2. 按验收ID复核视频/阅读/管理页面的同状态视觉、键盘和动作，修复影响内容理解或操作的偏差。
3. 自动化继续覆盖可独立完成的性能样本和升级前置；需要真实手机/NAS配合的部分保留待验证，按用户授权暂时跳过。
4. 只有全部必要项目逐项通过才关闭#24与LF8，之后交付原签名、递增versionCode的配套版本和回退说明。


## 2026-10-26：媒体库权威分类总数（PR #60）

[Draft PR #60](https://github.com/ShiJiJS/video_viewer/pull/60)基于#59，固定实现910cfb2、证据提交b927026。媒体库“视频 N / 图包 N”复用library-state中的同一SQLite只读快照，按实际完整可浏览目录计数；搜索零结果和分页不改写全库数，标签/最近隐藏标记。失败显示“—”并可点分类重试，旧服务隐藏；连接代次和请求顺序拒绝旧响应，图包操作后只读重取。

客户端485项、服务端相关75项、analyze/Ruff通过。普通三轮、大字、短横屏五轮同源码共45个库存检查点，真实逻辑回收/恢复2/4→2/3→2/4，完整进度不变、最近/阅读会话0；同源码另10个续读回归检查点通过。215份manifest输入核对源码、55个前台窗口/原始图、SQL投影、26个源SHA与设备恢复；并发提交测试证明两个总数来自同一快照。75项是相关服务回归，不是服务端全集或目标机性能。

受影响147dp顶栏与4785a69已实际渲染的冻结参考同状态并排；图包正文历史、标题/作者与排序仍有差异，不宣称整页完全一致。横屏键盘过渡暴露非当前标签页61dp可用高度下的79dp溢出，改为按实际空间约束并滚动操作区；两类标签缩高/恢复与原生横屏通过。正式取证不忽略Flutter异常，早期失败日志单列；本段未新增独立视觉评审或手势录屏。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/LF8-CATALOG-COUNTS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/evidence/lf8-catalog-counts/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/RESULTS.md)。本段补LIB-01/02、UI-01/04/05的明确组合，不关闭整项。管理网关用于验证计数更新，不替代删除确认UI验收；MemoryCredentialStore不新增强杀/安全存储证明。

下一段继续保守标题/作者与服务端一致排序，随后完整预览/阅读/管理、键盘手势、500页4K/8K、目标手机/NAS和原签名覆盖升级。冻结原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：图包标题、作者与完整范围排序（PR #61）

[Draft PR #61](https://github.com/ShiJiJS/video_viewer/pull/61)基于#60，固定源码4e391a2、证据提交614b135。图包卡片分开标题/作者，未知格式回退原名；原name/path/ID保留。续读、阅读器、范围、详情和最近复用显示标题，阅读头显示作者/编号；阅读角标补实际页码并移到左上，多选隐藏。

能力pack_presentation将App图包名称排序统一映射为title；SQLite内同一ICU中文标题键贯穿分页、锚点、完整全选和创建阅读范围。保留name/默认旧调用、旧固定会话及newest/recent；不在App只重排一页。Docker固定已有ICU运行库，裸环境缺依赖不广告能力；无schema迁移或重扫要求。双倍字号切最近加入曾向右溢出51dp，现大字操作行可横向滚动，保留字号与两端完整动作。

客户端494项、服务端8文件相关111项、analyze/Ruff通过。普通三轮、大字、短横屏共50个展示/排序检查点，另库存9点与续读10点回归；262份manifest输入核对69个前台窗口/原始图、同版源码、SQL范围ID/ordinal、26个源SHA及设备恢复。服务含28包跨页与创建后改名/新增不重排。续读回归的显式refresh沿用一次扫描，标题/库存流程无扫描；不是服务端全集或目标机性能证明。

实际浏览器和原生四包顺序一致；参考以未保存snapshot配置冷库history为空、保留第三张页码，加载的HTML/CSS/运行脚本与冻结Git字节核对。完整并排不挪列或拉伸，已明确保留差异：桌面滚动条使参考列167.5dp/原生173dp，共享标签仍11dp，参考12dp/1.6行高和4dp上距；标签顺序、次要文字颜色、菜单图标与横屏列数继续复核。视频中文排序及完整管理/阅读/预览、手势、500页4K/8K、目标手机/NAS和原签名升级也仍开放。

[设计与兼容约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/LF8-PACK-PRESENTATION.md) / [原始证据及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/evidence/lf8-pack-presentation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/RESULTS.md)。本段补LIB-02/03及UI-01/04/05局部组合，不关闭整项；未新增独立视觉评审或手势录屏，MemoryCredentialStore不新增强停/安全存储证明。早期验证预期、指标锚点/懒加载与真实大字溢出日志均单列，失败轮次不计正式图。

下一段继续共享卡片标签密度与横屏排布、视频中文排序，再收口完整页面和动作。原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。


## 2026-10-26：卡片标签密度与短横屏网格（PR #62）

[Draft PR #62](https://github.com/ShiJiJS/video_viewer/pull/62)基于#61，固定源码e53e173、证据提交8812d24。视频/图包标签统一12dp/1.6和元信息后4dp间距，作者/方向色对齐参考；卡片按实际字形测量高度。媒体库及标签结果短横屏四列，其余两列，键盘高度不改变列数；重排和返回共用实际几何，保存稳定成员与行内偏移，不重排或重查服务结果。最近视频完整形态继续核对。

客户端501项、analyze/Ruff通过。普通三轮、大字和短横屏30个卡片点，另共享8点、排序10点、续读10点、库存9点，共67张同源码原生前台图；277份manifest输入只读核对通过。120项组件样本验证两类双向重排及真实查询次数不增加；原生固定视口不冒充深列表旋转。26个公开源SHA、进度/会话SQL和设备恢复均保留。服务生产树未改，本段未重跑服务端测试；续读显式refresh沿用一次扫描，其余场景无扫描。

独立存量视觉评审一轮及修正复核一轮：作者/方向偏浅的唯一问题已修正，相邻标题/标签/网格未损坏。首轮大字续读脚本等屏外摘要挂载超时，现先核对真实返回锚点，再实际滚回顶部；失败与首轮图片单列，不忽略异常。并排复用已核对冻结字节的冷库浏览器参考，仅移除真实安全区并按DPR等比降采样，不挪列或拉伸。

[设计与返回约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/LF8-CARD-LAYOUT.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/evidence/lf8-card-layout/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/RESULTS.md)。本段补LIB-02及UI-01/04/05局部组合，不关闭整项。标签顺序/菜单图标、桌面滚动条列宽、视频中文排序、完整最近/预览/阅读/管理及手势、500页4K/8K、目标手机/NAS和原签名升级继续。冻结原型1cbf605独立可移除，backup_v2仍关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：视频中文名称顺序与预览退出（PR #63）

[Draft PR #63](https://github.com/ShiJiJS/video_viewer/pull/63)基于#62。实现a769d28、固定取证a8e94b2，生产树相同；证据提交8d65cb0。视频名称顺序在服务端贯穿分页、锚点、完整全选和固定播放范围，公开样本为“风里的花园→水边的花”。新客户端附可选name_locale=zh-CN，公共sort仍为name，旧请求和旧App可解析性保留；已有范围不因改名/新增或随机后恢复而改变原序。

真实回归同时修复退出时先销毁播放器、退场页面仍绘制导致的“No active player with ID”。现先卸载原生视图、等待本帧结束，再释放和返回；界面/系统返回两项检查在旧源码均失败、修正后通过。完整客户端505项、9个相关服务文件88项、analyze/Ruff通过；普通三轮/大字/短横屏40个视频点，加卡片6、共享8、图包呈现10，共64张同版原生图、256份manifest输入复核通过。27项跨页/固定成员与序号、实际解码/队列跳转/原筛选返回/最近去重、公开源SHA和设备恢复均核对。

首屏等真实ready及可用动作后与实际浏览器冷库参考并排，冻结源字节核对，不挪列或拉伸。旧销毁异常、末尾面板固定帧等待不足、原生空字符串输入未生效的诊断单列；最终通过可见“清除”按钮验证实际查询清空。未新增独立视觉评审或完整手势录屏，88项非服务端全集，2视频夹具非真机/NAS性能证明。

[设计与兼容约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/LF8-VIDEO-NAME-ORDER.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/evidence/lf8-video-name-order/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-name-order/docs/plans/library-first/RESULTS.md)。本段补LIB-01/03、预览/返回和UI局部组合；完整最近形态、视频文件名/时长显示、其它完整页面/手势、500页4K/8K、目标手机/NAS及原签名升级继续。原型1cbf605独立未改，backup_v2仍关闭；未发布APK或改正式8760/NAS/SDK，LF8/#33与总任务/#24保持开放。

## 2026-10-26：最近视频/图包历史行（PR #64，原生收口待补）

[Draft PR #64](https://github.com/ShiJiJS/video_viewer/pull/64)基于#63。最近记录初次固定点2e971ac，键盘/错误提示修正bd2b34f，阶段证据12a3a8d。视频与图包统一为单列历史行，64×78封面、18/13dp标题/说明、普通111dp行高；普通空态对齐原型。视频显示标题隐藏已知扩展名、时长按播放器整秒显示，原名/路径/ID保留。视频分页补24项/120项窗口、前补/淘汰补偿、页尾锚点及分页变化后的定位重试。

客户端516项、相关服务26项、analyze/Ruff通过。2e971ac的15个真实普通字号点验证实际视频首帧与最近固定1项范围、两条历史、图包续读与最近2包范围、返回、两类503保留/重试、独立媒体库草稿；只读区间完整进度不变，26份源字节不变。101份manifest输入的只读复核通过；这只证明所列阶段边界。

普通/双倍字号独立存量评审未见列表/空态/返回裁切重叠，仅提出错误提示边距/颜色不一致。最新实现已统一本轮错误提示，并针对短横屏键盘暂时收起标题/导航、保留分类/搜索，组件检查覆盖280dp键盘及恢复。修后原生复核尚未通过：最后测试Android的window/settings系统服务退出，ADB仍连接，自动配置恢复失败，专用8768容器已清理，未重启/卸载/清数据。不能以旧版15图或516项组件检查冒充新版普通三轮、大字/短横屏或手势验收。

[设计与限制](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/LF8-RECENT-HISTORY.md) / [阶段证据与只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/evidence/lf8-recent-history/README.md)。继续先恢复本轮模拟器配置并补最新原生证据、同一问题复核，再推进其它完整页面/手势、500页4K/8K、目标手机/NAS和原签名升级。冻结原型1cbf605独立未改，backup_v2仍关闭；未改生产8760/NAS/SDK或发布APK，LF8/#33与总任务/#24保持开放。
