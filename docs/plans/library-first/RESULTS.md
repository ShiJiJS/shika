# LF0–LF8 逐项收口台账（进行中）

更新：2026-10-28。总任务#24、LF8/#33保持开放。此表把已有阶段证据与剩余工作放在同一入口；“有阶段证据”不代表整项通过。原生界面、业务行为、服务端安全、性能和发布分别核对，不能互相替代。

最新阶段：[复杂图包性能测量与诊断 PR #96（进行中）](https://github.com/ShiJiJS/video_viewer/pull/96)。新增两份公开摄影原图衍生的506页/约3.4GB夹具（500页长包含400页4K/100页8K），正常服务扫描无失败；profile重复计时、被动内核PSS/RSS/VmHWM与汇总工具已提交，生产App/服务/原型未改，正常安装包仍为PR #95配套版本。三处采集错误已修正并分开保留；SWANGLE/GLES出现bad color buffer/GL context异常，QEMU81429挂起并确认退出，该轮失败，不诊断为App OOM。现以同数据SwiftShader复测，另一次进度确认等待超时正补状态诊断；尚无完整30次分位数/三轮500页结论。真实手机/NAS与READ-06完整验收继续，#24/#33/#78/#89均不关闭。

共享布局阶段基线为a9da395；最新图包续读阶段源码为c4aaf3b，见[真实续读约定](LF8-PACK-CONTINUATION.md)与[原生证据](evidence/lf8-pack-continuation/README.md)。后续分类总数阶段源码910cfb2，见[库存约定](LF8-CATALOG-COUNTS.md)与[库存/横屏及续读回归证据](evidence/lf8-catalog-counts/README.md)。该段补同快照总数、未知重试和标签缩高布局；续读段新增真实续读、独立摘要读取与菜单收键盘；共享布局的设置开关、标签确认区和主题稳定证据继续作为历史基线。图包呈现/排序阶段为4e391a2，见[约定](LF8-PACK-PRESENTATION.md)与[69点同版证据](evidence/lf8-pack-presentation/README.md)；主标题/作者和完整范围排序已补，新增大字长操作行可达性修正。原型树1cbf605未改。各阶段链接中的实现提交、真实服务/Demo区分、操作步骤与原始证据继续有效，但未来修改后须按受影响路径复核，不能把历史全集视为当前HEAD所有组合已通过。

卡片/网格阶段固定e53e173，见[实现约定](LF8-CARD-LAYOUT.md)及[67点同版证据](evidence/lf8-card-layout/README.md)。共享标签12/1.6、4dp上距、作者/方向色及短横屏四列已补；501项客户端通过，服务生产树未改且本段未重跑服务端。其余验收仍按下表开放项推进。

最新最近记录固定b2ce2a8（生产界面树01bf735）、证据33b84f4，见[99点同版原生及三轮视觉复核](evidence/lf8-recent-history-final/README.md)。客户端518项、相关服务26项通过，两项视觉问题关闭；这些结果仅覆盖本段明确组合。

阅读器布局阶段固定0ab8a83（生产及组件测试树a00d12c）、证据e86726b，见[82点同版原生及两轮视觉复核](evidence/lf8-reader-chrome/README.md)。客户端530项通过；短横屏画布、固定面板动作及大字来源已补。本段服务树未改且未重跑服务测试。

最新视频预览固定bd40372，证据e97852d，见[范围与控件约定](LF8-PREVIEW-PANELS.md)及[125点同源原生与独立复核](evidence/lf8-preview-panels/README.md)。客户端540项通过；大字控件/整理、长来源滚动、完整来源与主题入口已补。该段静态清单关闭，但遗留短队列高度/横屏宽度/工具图标差异；下段几何100点记录了对应修正。

最新预览几何固定eee463a，证据5c711d6，见[实现约束](LF8-PREVIEW-GEOMETRY.md)及[100点同源原生与两轮视觉](evidence/lf8-preview-geometry/README.md)。客户端544项通过；前段短队列高度、横屏宽度和工具/播放轮廓差异已补，快速整理浅绿紧凑条与大字语义换行同清单复核关闭。平台字号/安全区差异明确保留，不据本段关闭完整预览。

最新设置表单固定81b598f（生产界面同57edbc8），客户端550项，见[实现边界](LF8-SETTINGS-FORMS.md)与[155点同版及独立复核](evidence/lf8-settings-forms/README.md)。连接/目录/默认偏好、真实键盘与错误已补；其它完整管理及手势继续。

最新缺失管理固定2369f0d，21项相关检查连续三轮通过，见[边界](LF8-MISSING-MANAGEMENT.md)及[39+4点原生与独立复核](evidence/lf8-missing-management/README.md)。补长列表错误显露、成功翻页起点、实际根状态与完整确认；服务生产树未改，本段未重跑全集。

| 验收ID | 当前证据状态 | 证据入口（含该阶段实现提交/步骤） | 尚需完成 |
| --- | --- | --- | --- |
| NAV-01 | 新增普通视频／全屏／图包内容页强停 / 明确组合通过 | [LF4契约](LF4.md)、[三来源84点](evidence/lf8-navigation-restart/README.md)、[同版内容页21点](evidence/lf8-fullscreen-restart/README.md) | 三类各一次真实强停、新PID免口令、媒体库与最近只读七表相同，明确点击后同一视频／图包页码偏移重开通过；全屏旧失败定位为测试误滚动，生产未改。其它来源下活跃内容强停／断线／目标安装继续。原三来源及设置页证据保留，未把共享启动配置等同正式main升级验证，且不宣称模拟器无中断稳定性。 |
| NAV-02 | 新增六来源与系统返回 / 明确组合通过 | [当前导航与位置](evidence/lf8-navigation-restart/README.md)、[全屏返回](evidence/lf8-preview-lifecycle/README.md) | 两类型×媒体库／标签／最近均实际进入返回；两类前两来源跨24分页、完整27成员与同卡片位置，系统返回先关队列／总览。其它目录／属性筛选、失效／空来源及目标终验继续，不将少量最近当长列表。 |
| NAV-03 | 新增双类型与三来源隔离 / 明确组合通过 | [LF4契约](LF4.md)、[当前导航／冷启](evidence/lf8-navigation-restart/README.md) | 搜索、同名独立标签、不同排序、各1项选择切换以及最近不继承媒体库条件已实测；三种最后来源的冷启动恢复分属对应入口。其它连接／异常组合与整体目标终验仍按相应条目推进。 |
| LIB-01 | 新增视频中文顺序证据 / 未收口 | [LF4阶段记录](LF4.md)、[权威总数](evidence/lf8-catalog-counts/README.md)、[中文顺序](evidence/lf8-video-name-order/README.md) | 分类总数及视频列表/锚点/全选/固定范围的中文顺序已补证；最近段补显示标题/时长和24项/120项窗口、页尾锚点；长列表其它来源/失败组合继续。 |
| LIB-02 | 新增卡片/网格证据 / 未收口 | [LF4阶段记录](LF4.md)、[续读](evidence/lf8-pack-continuation/README.md)、[总数](evidence/lf8-catalog-counts/README.md)、[呈现/排序](evidence/lf8-pack-presentation/README.md)、[卡片/网格](evidence/lf8-card-layout/README.md) | 标题/作者、完整范围中文排序、共享标签12/1.6与4dp间距及短横屏四列已补证；长列表完整来源/失败组合继续。 |
| LIB-03 | 新增视频跨页顺序证据 / 未收口 | [LF4阶段记录](LF4.md)、[摘要独立于分页](LF8-PACK-CONTINUATION.md)、[视频排序约定](LF8-VIDEO-NAME-ORDER.md) | 图包28项和视频27项分别补完整排序/锚点/全选/固定范围一致，新增/改名后不重排；补来源标签删除后的0结果不扩库、显式清除后3项与返回权威总数刷新；其它完整来源/跨页失败组合继续。 |
| TAG-01 | 新增视频定义完整操作及失败恢复 / 未收口 | [标签管理](LF8-TAG-MANAGEMENT.md)、[标签分配](LF8-TAG-ASSIGNMENT.md)、[视频定义75点](evidence/lf8-video-tag-definitions/README.md) | 视频真实创建409/201、跨类型同名独立、原ID改名保2关联、移除确认／取消草稿、改名／移除503同请求重试与重开读回已补；图包定义与关联保留。合并后的最终同版搜索／连接切换、更多受理后故障及目标手机组合继续。 |
| TAG-02 | 新增单项替换与跨页批量追加证据 / 未收口 | [标签管理](LF8-TAG-MANAGEMENT.md)、[标签分配](LF8-TAG-ASSIGNMENT.md)、[分配证据](evidence/lf8-tag-assignment/README.md) | 已补61标签跨50项失败保选择/同offset重试、SQL交集=1、结果503实际重试；本段两类单项替换与跨24项分页全选27再排除1项追加，精确成员／53关联和命名空间独立核对。组件补只剩1项仍追加及固定目标；更多匹配范围／分页失败组合继续。 |
| PRE-01 | 新增预览控件/范围证据 / 未收口 | [LF3](LF3.md)、[预览125点](evidence/lf8-preview-panels/README.md) | 已补真实单项/完整范围来源返回、暂停/拖进度/倍速/长按恢复和面板只读组合；完整手势录屏、全屏/后台/相邻解码异常及目标手机继续。 |
| PRE-02 | 新增预览控件/范围证据 / 未收口 | [LF3](LF3.md)、[预览125点](evidence/lf8-preview-panels/README.md) | 已补真实单项/完整范围来源返回、暂停/拖进度/倍速/长按恢复和面板只读组合；完整手势录屏、全屏/后台/相邻解码异常及目标手机继续。 |
| PRE-03 | 当前本地链路三轮通过 / 目标终验未收口 | [LF3](LF3.md)、[标签／固定范围与返回库存](evidence/lf8-preview-state-stability/README.md) | 76a2f95三轮补真实保存／重开读回、当前项与成员序号不变、真实扫描新增不进旧范围、来源标签删除不扩范围、返回重查／空结果与显式清除；当前完整版本合并、目标手机与NAS终验继续。 |
| PRE-04 | 新增当前预览全屏/后台行为三轮 / 未收口 | [LF3](LF3.md)、[当前链路](evidence/lf8-preview-lifecycle/README.md)、[绿边#78](https://github.com/ShiJiJS/video_viewer/issues/78) | 暂停/拖进度、倍速/临时2倍、真实全屏/系统返回及左右设备手势已补三轮；已用#79记录的本地配置验证固定样本画面；软解路径复现由#78保留，其它解码异常/格式与目标手机继续。 |
| PRE-05 | 新增当前预览全屏/后台行为三轮 / 未收口 | [LF3](LF3.md)、[当前链路](evidence/lf8-preview-lifecycle/README.md)、[绿边#78](https://github.com/ShiJiJS/video_viewer/issues/78) | 真实Home六次释放全部网络播放器、返回暂停/基础速度；当前及前后共3项、关闭准备后1项和离页释放已补三轮。其它迟到回执/重叠初始化、故障/强停及目标设备继续。 |
| PKG-01 | 已有阶段证据 / 未收口 | [LF2](LF2.md) | 最终同版重扫/离线/缺失/失败读取组合；真实NAS可丢弃样本复核。 |
| PKG-02 | 已有阶段证据 / 未收口 | [LF2](LF2.md) | 最终同版重扫/离线/缺失/失败读取组合；真实NAS可丢弃样本复核。 |
| PKG-03 | 新增容量／跨24页取消证据 / 未收口 | [LF2](LF2.md)、[传输重试与长包](evidence/lf8-reader-long-pack/README.md)、[缩略图恢复](evidence/lf8-thumbnail-recovery/README.md)、[容量与跨页](evidence/lf8-overview-pagination/README.md) | 本段24相关检查、普通三轮跨页33点＋六图故障回归8点：共享3下载、21排队取消，实际24→6→24解码、真实返回取消清单、重开保留第3页，明确点第30页才写一次进度。#83开发证据已补齐，草稿合并／终验继续；同版重扫／离线／缺失／其它失败及NAS复核仍开放。 |
| READ-01 | 新增长包/大图链路证据 / 未收口 | [LF5](LF5.md)、[阅读器82点](evidence/lf8-reader-chrome/README.md)、[500页三轮](evidence/lf8-reader-long-pack/README.md) | 新增真实总览跳页和普通/大字/短横屏画布证据；完整左右方向/缩放/手势及目标手机组合继续。 本段补实际500页单调滚动、末页横纵同页、固定范围/大图往返及重开末页和纵向偏好；未新增比例相等或其它组合证明。 |
| READ-02 | 新增长包/大图链路证据 / 未收口 | [LF5](LF5.md)、[阅读器82点](evidence/lf8-reader-chrome/README.md)、[500页三轮](evidence/lf8-reader-long-pack/README.md) | 新增真实纵向拖动及同页比例保持；组件保留惰性布局/双向旋转回归。长包间距/末尾与性能同版收口继续。 本段补实际500页单调滚动、末页横纵同页、固定范围/大图往返及重开末页和纵向偏好；未新增比例相等或其它组合证明。 |
| READ-03 | 新增长包/大图链路证据 / 未收口 | [LF5](LF5.md)、[阅读器82点](evidence/lf8-reader-chrome/README.md)、[500页三轮](evidence/lf8-reader-long-pack/README.md) | 新增模式设置初始完整主动作、同图切纵向及每包偏好重开恢复；全局默认/已设置包隔离与其它方向/适配组合继续。 本段补实际500页单调滚动、末页横纵同页、固定范围/大图往返及重开末页和纵向偏好；未新增比例相等或其它组合证明。 |
| READ-04 | 新增长包/大图链路证据 / 未收口 | [LF5](LF5.md)、[阅读器82点](evidence/lf8-reader-chrome/README.md)、[500页三轮](evidence/lf8-reader-long-pack/README.md) | 新增真实沉浸/恢复、快速整理显隐、同页比例与重开续读，工具/面板完整进度只读；删页回退、其它异常与完整手势继续。 本段补实际500页单调滚动、末页横纵同页、固定范围/大图往返及重开末页和纵向偏好；未新增比例相等或其它组合证明。 |
| READ-05 | 新增长包/大图链路证据 / 未收口 | [LF5](LF5.md)、[阅读器82点](evidence/lf8-reader-chrome/README.md)、[500页三轮](evidence/lf8-reader-long-pack/README.md) | 新增两次完整4包固定成员/序号、范围分页收尾及返回稳定锚点/偏移；缺失/停用/空范围和前后包完整组合继续。 本段补实际500页单调滚动、末页横纵同页、固定范围/大图往返及重开末页和纵向偏好；未新增比例相等或其它组合证明。 |
| READ-06 | 复杂摄影像素测量进行中 / 未收口 | [LF5](LF5.md)、[纯色500页三轮](evidence/lf8-reader-long-pack/README.md)、[复杂图片诊断与原始样本](evidence/lf8-reader-performance/README.md) | 先前软件GPU三轮500页及4K/6K/8K通过仅覆盖纯色debug夹具。新profile采用两张摄影原图衍生506页/约3.4GB；attempt-6收齐4K/8K各30次首图与相邻翻页，但长包第157页采样失败，整轮不通过。后续第124页连接超时尚未归因；修正驱动采样/Slider并补专用请求观察继续定位。失败轮的120个计时保留，不能代替最终三轮、正常release、手机/SMB峰值和NAS CPU/IO。 |
| REC-01 | 新增修后99点中的85个最近点 / 未收口 | [最近约定](LF8-RECENT-HISTORY.md)、[最终证据](evidence/lf8-recent-history-final/README.md) | 两类真实最近、固定范围、返回、503保留/重试与媒体库草稿已补同源五轮；回收/恢复和三来源其它组合继续。 本段补新视频实际相邻解码但未被打开，最近API／SQL仍只含两个实际打开的旧视频。 |
| DEL-01 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-02 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-03 | 已有阶段证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-04 | 新增双类型回收站证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md)、[回收站45点](evidence/lf8-trash-management/README.md) | 各类原操作与连接/重开组合继续；截图不替代源文件/回执的已有精确证据。 |
| DEL-05 | 新增永久删除复核与部分失败证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md)、[本轮36点](evidence/lf8-purge-management/README.md) | 精确计划／一次删除／同任务重试与27附件保留已核对；更多批次、断电和连接／重开组合继续。 |
| DEL-06 | 新增双类型回收站证据 / 未收口 | [LF6](LF6.md)、[LF7](LF7.md)、[缺失39+4点](evidence/lf8-missing-management/README.md)、[回收站45点](evidence/lf8-trash-management/README.md) | 已受理丢回执后同进程重建仅GET原请求、不重放清理已补；各类原操作/连接/真实强停组合继续。 |
| SET-01 | 新增连接表单证据 / 未收口 | [LF7](LF7.md)、[设置155点](evidence/lf8-settings-forms/README.md) | 真实端口错误/输入保留和普通、大字、横屏IME已补；完整旧服务/升级组合继续。 |
| SET-02 | 新增默认表单证据 / 未收口 | [LF7](LF7.md)、[设置155点](evidence/lf8-settings-forms/README.md) | 模式/方向/间距/适配、取消零写、保存读回恢复与固定当前范围已补；全部新范围入口/迁移/故障和备份v2组合继续。 |
| SET-03 | 已有阶段证据 / 未收口 | [LF7](LF7.md) | 设置入口已有阶段证据；长管理页、键盘/错误/旧服务组合和完整视觉继续。 |
| SET-04 | 新增目录与缺失管理证据 / 未收口 | [LF7](LF7.md)、[设置155点](evidence/lf8-settings-forms/README.md)、[缺失39+4点](evidence/lf8-missing-management/README.md) | 类型冲突、目录表单、实际根状态、停用保留25/清理24保留返回1及确认已补；旧服务/扫描异常与其它完整组合继续。 |
| SET-05 | 新增旧视频任务状态修正及三轮读取 / 未收口 | [LF7](LF7.md)、[任务修正/三轮](evidence/lf8-upgrade-rollback/README.md) | #93已在分支修正：新结果保留计数、旧结果据持久成员只读补足，原JSON/回执不改；三轮实际旧任务已完成/成员1项、只读区间相同。未知/部分失败保护及完整462服务通过；长管理页、其它错误/重开和目标终验继续。 |
| BAK-01 | 公开入口／系统文件及两类原请求找回已补 / 未收口 | [公开完整备份](LF8-PUBLIC-BACKUPS.md)、[系统文件24点](evidence/lf8-native-backup-roundtrip/README.md)、[失败与重开26点](evidence/lf8-backup-upload-diagnostics/README.md) | 开发入口已开放，旧服务／v1原任务与默认32 MiB保留。672客户端／28相关检查，真实拒绝连接重建对象只读查询，以及已受理回复截断后的安全存储／旧PID强停／移除输入／新PID找回同任务均已补；普通完整恢复同源码另一次通过。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复、连续稳定与目标手机／云文档／NAS／覆盖升级及回退仍待验收；格式旧问题已在PR #92处理，当前服务462项通过；原始#89原因仍待定位。 |
| BAK-02 | 公开入口／系统文件及两类原请求找回已补 / 未收口 | [公开完整备份](LF8-PUBLIC-BACKUPS.md)、[系统文件24点](evidence/lf8-native-backup-roundtrip/README.md)、[失败与重开26点](evidence/lf8-backup-upload-diagnostics/README.md) | 开发入口已开放，旧服务／v1原任务与默认32 MiB保留。672客户端／28相关检查，真实拒绝连接重建对象只读查询，以及已受理回复截断后的安全存储／旧PID强停／移除输入／新PID找回同任务均已补；普通完整恢复同源码另一次通过。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复、连续稳定与目标手机／云文档／NAS／覆盖升级及回退仍待验收；格式旧问题已在PR #92处理，当前服务462项通过；原始#89原因仍待定位。 |
| BAK-03 | 公开入口／系统文件及两类原请求找回已补 / 未收口 | [公开完整备份](LF8-PUBLIC-BACKUPS.md)、[系统文件24点](evidence/lf8-native-backup-roundtrip/README.md)、[失败与重开26点](evidence/lf8-backup-upload-diagnostics/README.md) | 开发入口已开放，旧服务／v1原任务与默认32 MiB保留。672客户端／28相关检查，真实拒绝连接重建对象只读查询，以及已受理回复截断后的安全存储／旧PID强停／移除输入／新PID找回同任务均已补；普通完整恢复同源码另一次通过。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复、连续稳定与目标手机／云文档／NAS／覆盖升级及回退仍待验收；格式旧问题已在PR #92处理，当前服务462项通过；原始#89原因仍待定位。 |
| UP-01 | 新增三轮真实旧数据迁移及服务回退 / 未收口 | [预览包](../../library-first-preview.md)、[覆盖安装](evidence/lf8-preview-package/README.md)、[三轮升级回退](evidence/lf8-upgrade-rollback/README.md) | APK5→6覆盖及旧服务兼容已有证据；本轮相同公开非空0004→0014、完整恢复旧数据/原镜像三轮通过，原凭据/记录/回执保留、新标签消失。当前新服务配旧客户端完整终验、禁用根其它组合、目标手机/NAS继续。 |
| UP-02 | 本机覆盖升级、服务/客户端回退已补 / 未正式发布 | [安装说明](../../library-first-preview.md)、[服务回退](evidence/lf8-upgrade-rollback/README.md)、[App回退](evidence/lf8-app-rollback/README.md) | 配套App新8/旧8沿用原签名，同AVD实际6→新8→旧8→新8→旧8→新8、五次覆盖/六次免口令冷启；设置、独立标签、图包第2页纵向及旧视频回收/撤销结果保留。99项本轮检查、148输入复核通过；服务三轮停机恢复为前阶段证据。code>8需重建配套包，真实目标安装及正式发布继续。 |
| UI-01 | 新增标签分配与真实IME证据 / 未收口 | [共享差异审计](LF8-SHARED-GEOMETRY.md)、[最近最终证据](evidence/lf8-recent-history-final/README.md) | 最近两类111dp行、空态、显示标题/时长已补同状态原型对照，保留真实总数兼容差异；标签顺序/图标和其它完整页面继续。  标签段补20dp锚线/描边选择、外置字段、单层确认、失败草稿、浅暗编辑和三视口45点；[证据与边界](evidence/lf8-tag-management/README.md)。 标签分配段补三尺寸42点、真实IME、单项来源读回与批量追加；低高度操作及体量固定清单闭合，[证据](evidence/lf8-tag-assignment/README.md)。 |
| UI-02 | 本地画面与预览状态补证 / 未收口 | [阅读器82点](evidence/lf8-reader-chrome/README.md)、[预览125点](evidence/lf8-preview-panels/README.md)、[几何100点](evidence/lf8-preview-geometry/README.md)、[长包原生录屏](evidence/lf8-reader-long-pack/README.md)、[当前预览45点/12录屏](evidence/lf8-preview-lifecycle/README.md)、[本地画面配置](evidence/lf8-video-rendering/README.md)、[固定范围／返回库存](evidence/lf8-preview-state-stability/README.md) | 普通/大字/短横屏画布、四工具/来源、范围与设置两轮视觉问题清单完成；完整预览/整理全链及手势录屏继续。 预览段补同源普通三轮/大字/短横屏、控制条避让与结束返回；几何段100点补短队列高度、横屏全宽、Paper轮廓及紧凑整理条，大字孤字/动作权重复核关闭；普通软件GPU500页阅读另补6段实际手势录屏与39前台点；当前预览另补实际全屏/系统返回、两次Home/轮和设备手势三轮；右侧绿边[#78](https://github.com/ShiJiJS/video_viewer/issues/78)未解决，画面完整性不通过。完整预览/整理、大字/横屏其它动作及状态继续。 |
| UI-03 | 新增永久删除管理证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md)、[设置155点](evidence/lf8-settings-forms/README.md)、[回收站45点](evidence/lf8-trash-management/README.md) 、[备份与任务管理](evidence/lf8-backup-task-management/README.md) | 连接、媒体目录、默认偏好与缺失页指定浅暗状态已复核；缺失另补39+4点同生产源码，1问题/1提升关闭；回收站指定流程另补45点；更多管理状态组合继续。  本段补备份开放行、短／长恢复、任务同一正文滚动与详情，真实IME／三视口／失败保页，静态证据边界见本段说明。 本段补永久删除短复核与完整清单／结果、三视口36点、翻页失败保页和稳定浅暗动作；[原始证据与边界](evidence/lf8-purge-management/README.md)。 |
| UI-04 | 新增标签分配与真实IME证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md)、[设置155点](evidence/lf8-settings-forms/README.md)、[回收站45点](evidence/lf8-trash-management/README.md) 、[备份与任务管理](evidence/lf8-backup-task-management/README.md) | 共享16项针对检查含设置开关语义；新增续读错误/重试、多选收键盘与大字/短横屏证据；库存段补未知重试与标签61dp缩高/恢复。最近段补两类503保留/重试及真实键盘，错误提示问题复核关闭；完整表单与其它恢复组合继续。 阅读段补设置/范围固定底部动作和长正文滚动检查、四视口设置语义及HTTP图片错误回归。 预览段补长来源滚动/当前定位、偏好文件保存读回与失败保留、面板覆盖禁用播放/速度。 设置段补真实IME与可见焦点、错误滚入、默认值保存读回及三种视口同清单复核，完整其它状态继续。  缺失段补四视口组件、同源39+4点与完整确认末尾，长列表错误/原请求显露和成功翻页起点已修正。  本段补备份开放行、短／长恢复、任务同一正文滚动与详情，真实IME／三视口／失败保页，静态证据边界见本段说明。 本段补永久删除短复核与完整清单／结果、三视口36点、翻页失败保页和稳定浅暗动作；[原始证据与边界](evidence/lf8-purge-management/README.md)。  标签段补20dp锚线/描边选择、外置字段、单层确认、失败草稿、浅暗编辑和三视口45点；[证据与边界](evidence/lf8-tag-management/README.md)。 标签分配段补三尺寸42点、真实IME、单项来源读回与批量追加；低高度操作及体量固定清单闭合，[证据](evidence/lf8-tag-assignment/README.md)。 |
| UI-05 | 新增标签分配与真实IME证据 / 未收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md)、[卡片/网格](evidence/lf8-card-layout/README.md)、[设置155点](evidence/lf8-settings-forms/README.md)、[回收站45点](evidence/lf8-trash-management/README.md) 、[备份与任务管理](evidence/lf8-backup-task-management/README.md) | 最近段同源普通三轮/大字/短横屏及真实键盘已补，双倍字号完整按钮裁切修正复核关闭；120项两类组件验证旋转/字号变更锚点及不重查，原生固定视口不冒充深列表旋转。完整状态与目标设备继续。 阅读段另补同源码普通三轮/大字/短横屏，组件双向旋转保持同页比例；固定视口原生不冒充实际旋转。 预览段补同源普通三轮/大字/短横屏、控制条避让与结束返回；几何段100点补短队列高度、横屏全宽、Paper轮廓及紧凑整理条，大字孤字/动作权重复核关闭；完整动作/其它状态继续。 设置段补真实IME与可见焦点、错误滚入、默认值保存读回及三种视口同清单复核，完整其它状态继续。  缺失段补四视口组件、同源39+4点与完整确认末尾，长列表错误/原请求显露和成功翻页起点已修正。  本段补备份开放行、短／长恢复、任务同一正文滚动与详情，真实IME／三视口／失败保页，静态证据边界见本段说明。 本段补永久删除短复核与完整清单／结果、三视口36点、翻页失败保页和稳定浅暗动作；[原始证据与边界](evidence/lf8-purge-management/README.md)。  标签段补20dp锚线/描边选择、外置字段、单层确认、失败草稿、浅暗编辑和三视口45点；[证据与边界](evidence/lf8-tag-management/README.md)。 标签分配段补三尺寸42点、真实IME、单项来源读回与批量追加；低高度操作及体量固定清单闭合，[证据](evidence/lf8-tag-assignment/README.md)。 |
| UI-06 | 视频减少动画修复已提交 / 待完整动作收口 | [本轮差异审计](LF8-SHARED-GEOMETRY.md)、[共享布局证据](evidence/lf8-shared-geometry/README.md)、[独立PR #98检查证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reduced-motion/docs/plans/library-first/evidence/lf8-reduced-motion/README.md) | #97 / PR #98修正四处视频控件固定160ms动画，开启系统偏好后首帧直接到位，关闭时保持原动画。相同四断言旧模块2失败/2通过，修后4通过，加13相关检查共17项及analyze通过。现有正常APK尚不含此修复；组件证据不代替原生完整动作时长/手势录屏或目标手机验收。 |

## 下一段推进顺序

1. 最近记录、阅读画布与预览控件本段证据分别保留99/82/125点边界；视频范围几何及整理条差异已补100点；设置表单与目录另补155点；缺失及回收站指定流程分别补39+4/45点；下一段继续永久删除复核、备份及任务管理和完整预览其它异常/方向/手势，不重复把局部图标收口当成整页一致。
2. 按验收ID复核视频/阅读/管理页面的同状态视觉、键盘和动作，修复影响内容理解或操作的偏差。
3. 自动化继续覆盖可独立完成的性能样本和升级前置；需要真实手机/NAS配合的部分保留待验证，按用户授权暂时跳过。
4. 只有全部必要项目逐项通过才关闭#24与LF8，之后交付原签名、递增versionCode的配套版本和回退说明。

### 2026-10-28：复杂长包的服务端挂起与观察方式修正

PR #96的attempt-10连续覆盖了285张实际解码图片（索引0–284，无缺页），在第286张失败。请求阶段显示progress正文已收完，进度/图片/library-state随后不返回；健康检查和数据库文件头可读，容器内SQL及容器停止挂起。不能据此定性App故障或宣称READ-06通过。失败后正常重启本机OrbStack（未使用force），原四服务ID/镜像保留并恢复运行，专用数据库完整性ok；本机曾短暂中断，NAS服务未动。

Mac直接读取活跃绑定SQLite、后半段失败SMB只读挂载均列为干扰，后续取消。失败挂载容器已清理，未实际开始真实图包检查。旧资源观察器在服务重建后仍指向旧ID，attempt-9/10分别27/185份统计全部失败，明确不可用；新runner绑定每轮实际容器ID并将环境采集错误纳入失败。完整原始帧、请求阶段、恢复及观察缺口见[诊断证据](evidence/lf8-reader-performance/README.md)，新报告收尾顺序和资源采集还需下一轮运行验证。现有预览APK及独立原型未改，父任务保持开放。


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

## 2026-10-26：最近视频/图包历史行（PR #64，首次阶段记录；修后结果见下节）

[Draft PR #64](https://github.com/ShiJiJS/video_viewer/pull/64)基于#63。最近记录初次固定点2e971ac，键盘/错误提示修正bd2b34f，阶段证据12a3a8d。视频与图包统一为单列历史行，64×78封面、18/13dp标题/说明、普通111dp行高；普通空态对齐原型。视频显示标题隐藏已知扩展名、时长按播放器整秒显示，原名/路径/ID保留。视频分页补24项/120项窗口、前补/淘汰补偿、页尾锚点及分页变化后的定位重试。

客户端516项、相关服务26项、analyze/Ruff通过。2e971ac的15个真实普通字号点验证实际视频首帧与最近固定1项范围、两条历史、图包续读与最近2包范围、返回、两类503保留/重试、独立媒体库草稿；只读区间完整进度不变，26份源字节不变。101份manifest输入的只读复核通过；这只证明所列阶段边界。

普通/双倍字号独立存量评审未见列表/空态/返回裁切重叠，仅提出错误提示边距/颜色不一致。最新实现已统一本轮错误提示，并针对短横屏键盘暂时收起标题/导航、保留分类/搜索，组件检查覆盖280dp键盘及恢复。修后原生复核尚未通过：最后测试Android的window/settings系统服务退出，ADB仍连接，自动配置恢复失败，专用8768容器已清理，未重启/卸载/清数据。不能以旧版15图或516项组件检查冒充新版普通三轮、大字/短横屏或手势验收。

[设计与限制](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/LF8-RECENT-HISTORY.md) / [阶段证据与只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/evidence/lf8-recent-history/README.md)。继续先恢复本轮模拟器配置并补最新原生证据、同一问题复核，再推进其它完整页面/手势、500页4K/8K、目标手机/NAS和原签名升级。冻结原型1cbf605独立未改，backup_v2仍关闭；未改生产8760/NAS/SDK或发布APK，LF8/#33与总任务/#24保持开放。

## 2026-10-26：最近记录修后原生复核（PR #64）

[Draft PR #64](https://github.com/ShiJiJS/video_viewer/pull/64)基于#63，最终取证源b2ce2a8、生产界面源01bf735，证据提交33b84f4。视频和图包均为111dp普通历史行；显示标题、时长、真实阅读位置和24项/120项视频窗口已补齐。最近分别使用各自真实打开记录及完整固定范围，返回保留来源位置和独立媒体库草稿。

客户端完整518项、相关服务26项、analyze及夹具/脚本Ruff通过。lib/test及本轮integration文件format通过；全量integration另有既存server_files_test.dart格式差异，诊断单列且未修改。普通三轮、大字、短横屏各17点共85点；同源视频顺序8点及卡片6点回归，共99个原生前台检查点。323份manifest输入的只读校验通过：原始图/窗口、源码、SQL成员/序号、503到重试只读与完整进度相等、26个媒体源SHA及七轮设备恢复均核对。26项不是服务端全集，小夹具不是目标机性能证明。

同一独立存量视觉问题清单共三轮：两类失败提示边距/颜色已复核关闭；双倍字号真实键盘下操作按钮裁切已修正并复核关闭。键盘可用高度判断包含完整搜索摘要及工具行，大字临时收起标题、保留分类/搜索与完整动作，关闭后恢复；新增两项组件检查在旧实现均失败、修正后通过，原生等待实际IME并断言整个按钮位于键盘上方。短横屏最近视频scrollOffset=98是原锚点恢复，保留正常视口裁界，不强制回顶。

此前Android系统服务退出后，按开发文档受控重启同一AVD并使用host图形后端，保留userdata、没有wipe/卸载/清数据；确认window/settings服务恢复及原显示配置，再完成七轮。Binder报错不能证明磁盘或GPU根因，恢复证据单列。旧101份阶段证据保持原样，不能代替本轮修后材料。

[最终证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/evidence/lf8-recent-history-final/README.md) / [设计与来源约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-recent-history/docs/plans/library-first/LF8-RECENT-HISTORY.md)。本段补REC-01、来源返回及UI-01/04/05的明确组合，不关闭整项。继续完整预览/阅读/管理同状态对照、手势录屏、其它异常/旧服务、500页4K/8K；目标手机/NAS、原签名覆盖升级仍待配合，按授权暂跳过。MemoryCredentialStore不新增强杀/安全存储证明。冻结原型1cbf605独立未改，backup_v2仍关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。

## 2026-10-26：阅读画布、工具与固定面板操作区（PR #65）

[Draft PR #65](https://github.com/ShiJiJS/video_viewer/pull/65)基于#64。

短横屏采用冻结原型的完整画布、浮动顶栏与360dp窄底栏，快速整理最多430dp；隐藏的总览/沉浸从更多菜单可达。竖屏保留既有顺序，收拢页码/工具/来源比例；双倍字号来源与包切换分行，保留完整来源及自然字体。设置的“继续阅读”和范围分页固定在面板底部，正文独立滚动，普通/大字分组分别留16/24dp。

最终取证源码0ab8a83，生产及组件测试树与a00d12c相同，证据提交e86726b。客户端完整530项、analyze、lib/test及本轮integration文件format和脚本Ruff通过；服务端生产/测试树与基线68f90bb相同，本段未重跑服务端测试。普通三轮、大字及短横屏各13点共65点，加最近17点回归，同源码82个原生前台检查点全部通过；303份manifest输入只读复核通过。

真实四包范围中完成总览跳页、纵向拖动、沉浸/恢复、范围查看、快速整理/退出、返回及重开。工具/面板只读区间完整进度对象相等；同一pageId与页内比例、返回锚点/偏移、两次完整4包会话成员及顺序、最近去重、纵向偏好均核对。26个源文件SHA和六轮设备配置恢复保持一致；无文件操作/回收项/扫描提交。组件另补双向旋转保持页内位置与不重建范围，以及长正文滚动时固定底部动作；固定视口原生截图不能冒充真实设备旋转或手势录屏。

独立存量视觉评审首轮及同清单复核：短横屏设置按钮裁切、大字标签边界冲突、大字来源省略、横屏分页收尾四项均在静态范围完成，没有新增必须修正项。正文超出时仍需滚动，不声称所有设置或四个成员均在横屏首屏显示。与实际浏览器冻结参考并排仅去真实安全区、按DPR等比降采样并补中性空白，不拉伸或挪动元素；真实平台行高差异保留。

[设计与实现约束](LF8-READER-CHROME.md) / [固定源码、原图、诊断和只读复核](evidence/lf8-reader-chrome/README.md)。本段补READ-01–05及UI-02/04/05的明确组合，不关闭完整验收项。继续完整预览、阅读其它异常/方向/手势、完整管理、500页4K/8K和目标手机/NAS及原签名覆盖升级；需用户配合部分按授权暂跳过。原型1cbf605独立可移除、backup_v2生产能力仍关闭，MemoryCredentialStore不新增强杀/安全存储证明；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。


## 2026-10-26：设置表单、媒体目录与真实键盘（PR #68）

[Draft PR #68](https://github.com/ShiJiJS/video_viewer/pull/68)基于#67，最终源码81b598f（生产界面同57edbc8）。连接/目录保持全高度管理页，文字输入恢复外置标签与近白输入面，类型/方向/适配使用开放设置行；保留图片适配、显式保存和原请求核对。正常完成扫描收为可展开摘要，异常仍显示详情；错误滚入可见区，极短键盘窗口允许动作随正文滚动，当前值与焦点保持可见。共享Paper短面板全宽，修正短媒体库状态区消息/重试可达。

完整客户端550项、analyze、181个Dart文件format与runner Ruff通过。普通三轮/大字/横屏105个设置点，另阅读13/预览20/最近17个短横屏回归，共155个同源码原生前台图。设置核对端口错误、真实目录类型409、草稿取消、默认值保存/重开读回/恢复；活动2成员视频范围、根记录和夹具原进度不变，阅读默认只两次写入/revision2、播放默认未写。八轮源SHA及显示配置恢复核对；阅读/最近回归产生的会话和进度按各自预期另核对。服务生产/测试树同8b68804，本段未重跑服务测试。

独立存量首轮与同清单复核，2问题/2提升均关闭：横屏连接焦点遮挡、表单还原、大字时间行首分隔点、类型冲突重复说明。原始图与不拉伸的并排、先行不稳定截图、真实溢出修正及两次QEMU自身崩溃/恢复分开归档；中断不计最终通过。主题文件IO测试改为等待真实保存/错误，相关两分支连续三轮及最终550通过，不隐藏原失败。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/LF8-SETTINGS-FORMS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/evidence/lf8-settings-forms/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/RESULTS.md)。本段补SET-01/02/04与UI-03/04/05明确组合，完整其它管理、预览/阅读异常与手势录屏、500页4K/8K、目标手机/NAS及原签名升级继续；需配合部分按授权暂跳过。原型1cbf605独立未改且可移除，backup_v2仍关闭，MemoryCredentialStore不新增强停/安全存储证明；未改正式8760/NAS/SDK或发布APK。#33/#24保持开放。

## 2026-10-26：缺失内容管理与待核对结果（PR #69）

[Draft PR #69](https://github.com/ShiJiJS/video_viewer/pull/69)基于 #68，生产及主流程源码固定 2369f0d，证据提交 8813c78。缺失内容改为 Paper 全高度页，视频/图包继续分别读取；名称、完整路径、类型/标签、实际根目录状态分层，保留 24 条分页、刷新、原请求和任务详情。危险清理位于列表之后，短确认层保留完整风险说明；普通/大字标题为 52/72dp，正文 20dp，次级色与原型浅暗色一致。

修正两个真实长列表问题：底部提交后先揭示顶部错误/原请求入口，避免惰性项未挂载而滚动失效；显式翻页成功回到新页开头，读取失败仍保留原页、成员及偏移。通用联调的原型元数据改为可空，不再要求独立设计目录一定存在；未据此声称已完成删除原型后的构建演练。

21 项相关客户端检查连续三轮、analyze、变更 Dart 格式与 Ruff 通过。普通/大字/短横屏各 13 点，同源码 39 个原生前台检查点；另同生产源码补大字/短横屏页尾与确认末尾共 4 图。每轮真实 27 包→25 缺失，停用清理保留 25 包及标签/进度/偏好/最近；返回一包后明确清理 24 条管理记录、保留返回包与原历史成员身份。两次 POST、一次原请求 GET、当前完整视频范围、源图片 SHA、数据库投影及五轮显示恢复均核对。第二次丢回执后的 App/Repository 重建发生在同进程，不冒充强停证明。本段未重跑客户端或服务端全集，服务生产树与 #68 相同。

独立存量首轮、中间普通复核、最终三视口及页尾补充复核，冻结 1 问题/1 提升已关闭：次级色过浅和分页到清理的间距已处理，完整页尾与确认末句可读。保留原生字体/真实安全区差异，静态图不作为完整动效或手势证明。失败脚本前置、真实结果不可见、分页起点修正和两次 QEMU 崩溃/恢复均单列诊断，不计最终成功点。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/LF8-MISSING-MANAGEMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/evidence/lf8-missing-management/README.md)。本段补 SET-04、DEL-06 与 UI-03/04/05 的明确组合，完整其它管理、旧服务/扫描异常、预览/阅读手势、500 页 4K/8K、目标手机/NAS和原签名升级继续；需配合部分按授权暂跳过。冻结原型 1cbf605 独立未改且可移除，backup_v2 仍关闭，未发布 APK 或改正式 8760/NAS/SDK。#33/#24 保持开放。


## 2026-10-26：双类型回收站、逐行恢复与待核对选择（PR #70）

[Draft PR #70](https://github.com/ShiJiJS/video_viewer/pull/70)，证据提交f5493f4。本段基于#69，最终生产及主流程固定88a45ec。视频／图包回收站统一为Paper全高度管理页：20dp正文、名称／完整路径、左侧勾选、逐行恢复和底部选择动作。短列表动作跟随内容；长列表保留可见收尾，真实IME或极短高度时随正文滚动。24项分页、图包搜索、刷新、原请求与任务入口继续保留；成功翻页回到新页开头，读取失败保持成员、偏移和选择。

原生核查修复两处实际状态问题：查询原请求成功后只释放对应26个选择，后来新选成员保留；ListView保持同一视口类型，避免键盘弹出切布局时丢失焦点。核实前显示“保留选择N／恢复结果待核对”，阻止相交内容的重叠恢复与删除；逐行确认写“恢复1个图包”，与批量选择区分。恢复确认和任务终态说明精简，真实停止结果仍保留。

47项相关客户端检查连续三轮、analyze、13个变更Dart文件格式及Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏同源码各15点，共45个原生前台检查点。每轮真实27包81张图片，跨页选26、确认取消零写、受理丢回执只GET原请求一次、再逐行恢复剩余1包；两次POST(503/202)、精确26+1成员、SQL计数、81张源SHA、首包进度／偏好／标签、完整当前视频范围及设备显示恢复单列核对。

独立存量评审沿冻结2问题/1提升复核页签锚线与通栏细线、未知选择语义、单项确认及终态减字，三视口可见项已静态闭合。另同生产补横屏unknown页尾1图，确认保留选择／核对说明／禁用动作完整；补轮原生只提交一次26恢复、零原GET，源SHA与视频响应保持。原始基线首阶段通过但旧runner误启动第二阶段，整体失败；旧选择问题、键盘焦点及惰性列表脚本等待失败另归诊断，不计最终成功点。

[实现与边界](LF8-TRASH-MANAGEMENT.md) / [原图、固定源码及只读复核](evidence/lf8-trash-management/README.md)。本段补DEL-04/06与UI-03/04/05明确组合，完整永久删除复核／部分失败、备份／任务管理、其它预览／阅读异常与手势、500页4K/8K、目标手机/NAS及原签名升级继续。MemoryCredentialStore不新增安全存储或真实强停证明；冻结原型1cbf605独立未改且可移除，backup_v2仍关闭，未发布APK或改正式8760/NAS/SDK。#33/#24保持开放。

## 2026-10-27：备份、恢复预览与操作任务管理（PR #71）

[Draft PR #71](https://github.com/ShiJiJS/video_viewer/pull/71)基于#70，证据提交b9ccf92；生产及13点主流程固定e10bbbc，archive等待修订30bc9d7的生产字节相同。备份采用Paper开放操作行；两目录短面板、27目录完整分页表单保留外置标签、完整路径、空映射与明确确认。任务说明、筛选、回执、记录和分页归入同一正文，详情使用相同页头与筛选样式。成功翻页归位，失败保留原页和草稿；真实IME时动作随正文可达。

修正保存取消仍显示“已下载”、同次格式错误重复、确认框顺序及不限行输入截获正文滚动。37项相关客户端检查连续三轮、analyze、14个变更Dart文件格式及Ruff通过，未重跑客户端或服务端全集。普通／双倍字号／短横屏各13个旧备份／任务点与8个完整archive点，共63个最终原生前台点；521份输入逐字节纳入manifest并只读复核通过。

任务阶段零POST、唯一原回执GET、两次原备份下载与81张源SHA独立核对；前置备份准备写入不称只读。完整archive仅在既有隔离8762夹具，每轮核对27目录、明确恢复一次，实际epoch及两类新增标签替换、当前任务完成，恢复前快照仅预览，源SHA保持。文件边界为注入／Android私有文件，不冒充系统文档提供器。大字初轮异步分页脚本失败已保留，等待27/27就绪后重新取齐最终三组；旧基线整体失败与中间成功样本均单列。

独立存量六份静态报告按冻结2问题／2提升复核，可见项已闭合；v1响应式确认行、暗色跨页详情和部分archive字段不在对应帧内，未扩大为所有组合或手势／动效通过。原始日志的尾随空白保留，源文件与文档另通过diff检查。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-task-management/docs/plans/library-first/LF8-BACKUP-TASK-MANAGEMENT.md) / [原图、固定源码及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-task-management/docs/plans/library-first/evidence/lf8-backup-task-management/README.md)。本段补BAK-01/02/03与UI-03/04/05明确组合，不勾选整体验收。永久删除复核／部分失败、大文件／更多备份故障与实际选择器、完整预览／阅读手势、500页4K/8K、目标手机/NAS及原签名升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760/NAS/SDK。#24/#33保持开放。


## 2026-10-27：永久删除复核、完整清单与部分失败（PR #72）

[Draft PR #72](https://github.com/ShiJiJS/video_viewer/pull/72) 基于#71，最终源码35a29d4，证据提交adeb1e2及527份manifest输入已逐字节复核。视频采用短底部前置勾选确认，图包保留精确图片清单／摘要／有效期和附件保留；保存选择、图包／图片清单及结果改为完整Paper管理页，20dp正文、52／72dp页头、单一正文滚动、真实分页和原请求／原任务重试。成功翻页归位，失败保页并揭示错误，完成空态移除零项页控。

90项相关客户端检查连续三轮、analyze、11个变更Dart文件格式与Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏各12点，同源码36个原生前台点。每轮108份真实源文件，取消／保存重开零物理提交；两次准备503/202、一次删除503、一次原任务重试202。相同task/plan逐项结果与SHA核对，最终差集恰为清单3张图片，其余105份SHA不变，27份附件保留、目录retained。视频原生仅取消确认；勾选分发与代次变化由组件边界检查，不外推真实视频源删除。

独立存量首轮冻结1问题／1提升，三视口36张最终PNG均已亲看，原1问题／1提升在可见范围闭合；静态图不认证动效／手势与行为。初次暗色图捕到主题与嵌套文字过渡中间帧，最终等待过渡结束并检查三个实际按钮文字／背景对比≥4.5，未更换主题色板。失败脚本定位、busy无限加载、长清单揭示距离和Demo队列测试诊断单列保留，不计最终成功点。

[实现与边界](LF8-PURGE-MANAGEMENT.md) / [原图、固定源码与只读复核](evidence/lf8-purge-management/README.md)。本段补DEL-05与UI-03/04/05明确组合，不关闭整体验收。更多批次／断电、备份大文件／故障／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机/NAS与原签名覆盖升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760/NAS/SDK。#24/#33保持开放。

## 2026-10-27：两套标签目录、定义编辑与交集结果（PR #73）

[Draft PR #73](https://github.com/ShiJiJS/video_viewer/pull/73)基于#72，证据提交[d710b33](https://github.com/ShiJiJS/video_viewer/commit/d710b33)，生产客户端固定4e905aa；普通完整脚本2cde25c、大字核心4e905aa、横屏核心c7e9799，结果专项补充79de2d9，完整生产字节一致。标签目录沿用Paper开放行、20dp正文锚线与描边选择，视频／图包继续独立。新建／改名复用外置字段、类型范围和明确动作；同名错误只留在表单。移除在同一面板独立确认，取消保留未保存草稿；写入中防重复及关闭，连接身份变化禁止旧ID写入。

46项相关客户端检查连续三轮、analyze、6个Dart文件格式与Ruff通过；未重跑客户端或服务端全集。生产字节相同的普通完整15点、大字核心13+结果专项2点、短横屏核心13+结果专项2点，共45个有效原生前台点。结果补充各自使用独立夹具，不冒称同一次全流程；旧弱门槛结果图不计。真实图包同名409保草稿、创建201、原ID改名保关联与移除取消／确认、视频61项跨50分页503／重试均核对。结果页另注入503并实际点击重试，核对唯一视频ID、total=1及两个标签条件，未以页面标题代替加载成功。四次UI定义写尝试、61视频定义／3关联、81图片SHA、27视频路径／大小／SHA和完整播放响应分别核对；前置准备写入不称只读。

独立存量评审沿冻结唯一提升将双层确认收敛为单层，浅暗编辑与普通完整15图／大字和横屏各新增2图复核；13核心图沿已亲看且字节未变的结论，不称再次重跑；静态图不认证完整动效／手势。原14点弱结果门槛、夹具遗漏代次头、短视口惰性定位与QEMU退出／同AVD恢复均单列，不计最终成功点。真实视频UI定义CRUD、批量追加／完整范围等其它TAG组合继续，不以共享组件分发代替完整业务验收。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/LF8-TAG-MANAGEMENT.md) / [固定源码、原图与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/evidence/lf8-tag-management/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，不关闭整体验收；更多备份故障／大文件／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机／NAS及原签名升级继续，需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS／SDK。#24/#33保持开放。


## 2026-10-27：视频／图包标签分配与批量追加（PR #74）

[Draft PR #74](https://github.com/ShiJiJS/video_viewer/pull/74)基于#73，生产客户端固定94c7292，最终原生脚本94c7292。标签分配统一Paper面板、21dp标题及20dp正文；视频／图包分别读取、创建与关联标签。单项保存替换整项标签，跨页批量仅追加，即使最后只剩一个目标也保留原标签。搜索与新建字段分离；创建／关联错误保留草稿，分页与名称核对沿原协议；提交中阻止重复、返回和拖动关闭，连接／恢复变化拒绝旧回调。小目录去除重复已选区，新建与添加同行；短横屏字段并排，系统字号保持。短横屏只在所选标签不在当前候选中时显示独立已选区，避免重复挤占首行。覆盖媒体库的弹层自行避让IME，背景保持原视口及读取错误，修复74dp剩余窗口中的29dp溢出。

48项相关客户端检查连续三轮、另31项共享导航／设置／面板检查、analyze及Ruff通过；Linux隔离服务10项标签／名称／全范围选择契约检查通过，未重跑客户端或服务全集。普通／双倍字号／短横屏同生产与最终脚本各14点，共42个原生前台点，包含两类单项替换、新建同名409保草稿、真实IME、保存返回实际来源模型读回，以及跨24项分页全选27再排除1项的批量追加。请求ID、单项其余26项未变、批量精确26成员、最终每类53条关联、两套命名空间、81图片SHA及显示配置恢复分别核对。

独立复核沿冻结1问题／1提升检查最终42图，可见范围内低高度操作截断与面板体量均闭合；静态图不外推动效或完整手势。截图保持状态并由宿主完成采集后确认，初始等待真实候选、保存等待来源模型读回；旧错位、加载中、未刷新图和失败轮单列诊断。普通使用默认Android渲染，大字／短横屏用测试专用Skia以绕过QEMU默认渲染崩溃，未修改应用或SDK默认，不冒称三组默认渲染全部通过。

[实现与边界](LF8-TAG-ASSIGNMENT.md) / [原图、固定源码与只读复核](evidence/lf8-tag-assignment/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，#24/#33及整体验收保持开放。真实视频定义CRUD的完整UI组合、更多备份故障／大文件／系统选择器、预览／阅读异常与手势、500页4K/8K、目标手机／NAS与原签名升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS。

## 2026-10-27：原型可移除构建演练与当前整合回归（PR #75）

[Draft PR #75](https://github.com/ShiJiJS/video_viewer/pull/75)基于#74，固定源码7c70e59。将整个Git提交导出到新建副本，仅移除副本内72份`design/reference/`文件，12,145份保留文件与固定提交全部blob独立逐字节核对；App package root实际指向副本，Git discovery上界避免借用父仓库。构建后保留源码与原仓库参考文件SHA均未变，副本参考目录保持不存在。冻结原型树1cbf605在原仓库独立保留。

同一副本Flutter analyze、完整643项客户端测试、debug/release APK构建、服务镜像Ruff check和完整Linux pytest 447项通过；初次pub解析离线且强制锁文件，构建使用标准Flutter模式注册。两包Flutter资产清单不含原型路径，Flutter引擎仅ARM64，JNI依赖另含armeabi-v7a/x86_64；release DEX无integration_test插件路径。APK仅本机构建，沿现有开发签名、未递增版本，不作为原签名升级包。服务格式检查仍有27份存量文件失败，单列保留，未误报全部门禁通过。

首轮debug后错误复用`--no-pub`使release残留测试插件注册而失败，`complete:false`与原始日志保留；同副本标准release通过只作诊断，修正脚本后按7c70e59重新完整跑第二轮。未修改SDK或移除开发测试依赖。输出安全检查拒绝仓库根目录、整个.dev及已有目录；实际只删除一次性导出副本。

[实施与边界](LF8-REFERENCE-ISOLATION.md) / [固定源码、原始日志与只读复核](evidence/lf8-reference-isolation/README.md)。此段证明实际移除参考目录后的构建/测试隔离，服务用例覆盖大于32MiB HTTP备份和500页4K/8K扫描，但不证明Android长包渲染、真机/NAS性能、系统选择器、完整手势或原签名覆盖升级。#24/#33及整体验收保持开放；需用户配合项按授权暂跳过。原型树独立未改，backup_v2生产仍关闭，未发布APK或修改正式8760/NAS。

## 2026-10-27：图包瞬断重试与500页/大图阅读（PR #76）

[Draft PR #76](https://github.com/ShiJiJS/video_viewer/pull/76)基于#75。真实大图响应头前连接关闭暴露自动恢复缺口，生产固定f8631ae：SocketException/HttpException沿现有400/800ms、最多两次自动重试；持续失败仍可手动重试/跳过，失败不记进度，离页取消定时器。布局、服务业务、SDK和冻结原型均未改。新增3项回归在修复前两项失败、修后通过；12项相关与完整646项客户端测试、analyze/格式/Ruff通过。服务447项全集仍归属#75，本段未重跑。

最终驱动/采集固定df9d80c，生产与组件测试字节同f8631ae。同一API36 ARM64专用AVD、软件GPU/headless、390×844/DPR3/字号1、App无渲染覆盖，连续三轮均从媒体库进入500页，经730次实际拖动覆盖所有页；末页横纵切换、固定4包范围、三次4K/6K/8K实际解码往返、返回媒体库再续读及纵向偏好，均核对实际可见帧、HTTP与只读SQL。共39个前台点、6段原生录屏（全帧解码通过），源SHA相同，显示基线恢复。宿主GPU退出139、长扫描准备、旧图像传输失败及驱动/采样就绪问题分别留档，不拼为成功。

元数据峰值120、provider 6项/估算24.4MiB、Flutter缓存约26.8MiB/待解码4；全部采样与检查点PSS最高480.8/631.4/462.9MiB。不同指标不互作上限，debug驱动节奏及高压缩纯色合成图不代表真实照片、SMB或目标手机/NAS性能。第一轮一次已处理离屏长包预读HttpException保留；没有原生当前大图故障注入，自动恢复/重试上限由组件检查证明。标准ARM64 release编译成功，资产无原型路径且release DEX无integration_test；仅本机构建、开发签名和原版本，不发布或冒称原签名升级。

[实施与边界](LF8-READER-LONG-PACK.md) / [固定源码、原始证据与只读复核](evidence/lf8-reader-long-pack/README.md)。本段补READ-01..06、PKG-03与UI-02的明确组合，未据此关闭整项。目标手机/NAS峰值与30次p50/p95、其它方向/缩放/大字/手势及异常、系统选择器和原签名覆盖升级继续；需配合部分按授权暂跳过。原型树1cbf605独立未改且可移除，backup_v2生产仍关闭，未改正式8760/NAS。#24/#33保持开放。

## 2026-10-27：当前视频预览的全屏/后台原生链路（PR #77）

[Draft PR #77](https://github.com/ShiJiJS/video_viewer/pull/77)基于#76，最终驱动/采集98507ea。生产App、组件测试及服务业务树与605badb相同；新增当前媒体库→二级预览→实际全屏/系统操作的演练，修正采集器录屏回收失败后仍应恢复设备并清理精确自建容器的问题，原型元数据可空。

独立8768的公开三视频变体（第三项复用公开横屏字节，普通原型场景仍2项）、4包/24PNG，API36 ARM64专用AVD、software GPU/headless、关闭宿主HardwareDecoder、App无渲染覆盖。固定98507ea连续三轮行为通过：45个前台截图/焦点/内存点、21次1600逻辑px/s fling、6次实际Home往返、12段旋转分段录屏（全帧解码通过）。同一控制器/暂停位置跨真实旋转保持；1.5倍/临时2倍、左右原生亮度/音量、后台释放与前台暂停、系统返回先退全屏、当前±1共3控制器/仅当前playing且volume>0、真实设置关闭准备后1控制器及离页释放，分别分别核对实际UI暂停意图、可见VideoPlayer与原生值。两轮固定3成员/序号、最近3实际视频、27源SHA和显示/音量恢复经请求、API与只读SQL核对。

15项相关客户端检查、App/最终驱动analyze、变更Dart格式和Python Ruff通过；完整646/447分别保留#76/#75源码归属，本段未重跑全集或构建release。早期随机默认/当前锚点假设、队列异步挂载、显示控件时重复切换的驱动失败、历史成功、QEMU实际139退出/恢复均分开留档，不计最终三轮。关闭宿主视频解码是本地启动条件，未改SDK；成功不证明旧宿主解码路径崩溃根因。

**实际画面仍有未解决问题：**关闭宿主解码后的横屏右侧绿边已与源帧和相同生产树的宿主解码原图对照，登记[渲染/稳定性 #78](https://github.com/ShiJiJS/video_viewer/issues/78)。根因尚未证明，不能以行为通过或录屏可解码判定UI-02画面完整性通过；保留原图继续定位，不裁边或换素材掩盖。

[实施范围](LF8-PREVIEW-LIFECYCLE.md) / [原始证据与只读复核](evidence/lf8-preview-lifecycle/README.md)。本段补PRE-04/05、NAV-02及UI-02的明确行为组合；实际三个小视频不证明重叠初始化/迟到回执、全部格式/来源/主题/字体或目标手机/NAS性能。MemoryCredentialStore/内存偏好与Home不新增强停/凭据/落盘证明。原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未改正式8760/NAS或发布APK。#24/#33/#78保持开放，需用户配合项按授权暂跳过。


## 2026-10-27：本地视频画面与开发启动配置（PR #79）

[Draft PR #79](https://github.com/ShiJiJS/video_viewer/pull/79)已创建并附于任务。

对应#78/#33/#24，基于#77，当前完整App采集固定7740f4d。最小同源比较确认：关闭宿主解码时，Flutter textureView在Impeller/Skia均复现129列绿条；platformView与原生MediaPlayer两入口无该条。byte-buffer codec逻辑/裁切960×540、stride1024仅为独立路径数据，不证明Surface根因。选择software GPU、Vulkan关闭、GLDMA关闭、宿主解码开启的本地配置，保留产品播放器实现；实际AVC属性2、日志c2.goldfish.h264.decoder。

同源当前App连续三轮通过，共45前台点、21次fling、6次真实Home往返、12段录屏全帧解码。新增15个横屏原图的已知绿条/非黑帧检查，实际抽查每轮截图正常。阅读相邻13点通过。设置相邻两次IME超时经实际宿主截图/Window/IME确认：键盘和表单正常，旧驱动取了弹层下刻意归零的来源页insets；eb5cc46仅改integration_test从真实FlutterView读取，保留键盘/焦点/遮挡断言，最终21点通过。失败与修后源分别留存，不把两个源码说成同一采集。

启动器修复离线ADB残留阻止启动和短暂前置shell生命周期问题：真实进程判断、现有配置核对、其它AVD保留、独立session；6项CLI契约有旧失败/修后通过记录，真实启动命令结束后持续运行并成功复用。原有VS Code前置任务调用此脚本；本段实际验证脚本入口，未冒称再次点击F5。显示/字号/原生音量恢复后，专用AVD正常退出，未清userdata。

flutter analyze与变更Python Ruff通过。正常release构建、manifest/DEX诊断Activity与integration_test排除、原型页面资产排除及原证书核对通过；仍0.1.4+5，只在本地构建。Flutter应用/引擎为ARM64，依赖另携带其它ABI的libdartjni.so辅助库，不当作完整跨ABI应用。相关15项组件与646/447全集沿用既有固定业务树证明，本段未重跑全集。

[方案](LF8-VIDEO-RENDERING.md) / [原始证据与只读复核](evidence/lf8-video-rendering/README.md)。本地固定样本的画面通过不关闭完整UI-02/05、目标手机/NAS、其它格式/异常/迟到回执、完整主题字号与来源组合。短队列收高、横屏范围宽度和工具形态已由#67完成；本轮后续以当前源码/原生画面复核，转而推进标签变更与固定范围稳定性等剩余状态组合。原型树1cbf605独立未改可移除，backup_v2生产仍关闭；未改正式8760/NAS、SDK或发布APK。#24/#33/#78保持开放，需配合项按授权暂跳过。


## 2026-10-27：预览标签与固定范围、来源返回库存（PR #80）

[Draft PR #80](https://github.com/ShiJiJS/video_viewer/pull/80)已建立并关联本任务。

基于#79，最终生产/驱动固定76a2f95。当前b94754f完整预览20点确认#67已完成的队列390×435dp与工具形态，修正最新段落将旧留白/640dp差异重新当余项的过时描述，不重复改已对齐布局。

新原生链路实际从标签筛选进入，预览内保存／重开读回标签；当前项、范围身份、成员和序号不变。专用目录真实复制公开样本并扫描，已鉴权API为新增项加同一标签，旧范围不吸收；返回原筛选看到更新后的匹配项。再从新匹配结果进入固定范围，外部删除来源标签定义，旧范围仍保留；返回后保留0项而非扩库，明确清除才显示全部3项。新增项真实相邻初始化、未播放且音量0，最近API／SQL仍仅两个实际打开的旧视频；同名图包标签与原进度未改。

先行三轮的实际原图另发现返回列表已新、顶部库存仍旧。新增视频/阅读器返回、即时/延迟库存四项组件旧版全失败；最终两个来源页返回时独立刷新权威库存，不阻塞列表/锚点恢复、不由筛选数推算库存。4新增与21相关共25项、analyze/Ruff通过。修后同76a2f95三轮42原生点、阅读相邻13点通过；返回图等真实库存3及新封面解码，429项证据只读复核通过。

原先26个源文件SHA不变，唯一新增文件为固定路径公开flower-landscape副本，SHA和scanner真实ID单列；不是伪称前后文件完全相同。三轮各两个固定范围的成员/序号/游标、精确标签写入／定义删除、返回结果与历史由API/SQL分别核对。源控制入口错误键403且只在专用场景标志下启用，生产服务无此测试入口。早期采集上下文／嵌套滚动错误、先行未核对库存的三轮与组件中间失败均保留，不计修后成功。

[实施边界](LF8-PREVIEW-STATE-STABILITY.md) / [原图、请求、SQL、源码与只读复核](evidence/lf8-preview-state-stability/README.md)。本段补PRE-03及LIB-03/NAV-02/REC-01明确组合；阅读器返回同类修正有组件和相邻原生证明，不冒称新增图包的NAS场景。没有新视觉方向或布局变更，旧#67视觉评审保留源码边界，本段未重做独立视觉评审。未重复全集或release构建、未发布APK；其它格式/异常与目标手机/NAS及原签名升级继续。原型树1cbf605独立可移除未改，正式8760/NAS/SDK未改，#24/#33/#78仍开放。下一步继续视频标签定义真实改名／删除及失败读回等明确余项。

## 2026-10-27：视频标签定义与失败恢复（PR #81）

[Draft PR #81](https://github.com/ShiJiJS/video_viewer/pull/81)基于#80，补视频标签目录真实创建／改名／移除及失败读回。生产6f7ce97增加计数入口mounted／active检查：关闭面板后列表迟到，已离开或销毁页面不继续计数。两类型×离开／销毁四项在旧码真实四败，修后与定义／分页／分配组件合计51项通过，analyze／格式／Ruff通过。

普通同驱动三轮45点；大字68ce0fb、短横屏a40dc0f各完整15点，共75点，生产和组件树相同。真实409保草稿、视频“和服”201与图包同名独立、改名503原请求重试保原ID／2关联、移除确认取消回原草稿／关闭零写、移除503重试200、重开目录／返回媒体库均补证。每轮7次UI写请求、3条成功命令，图包完整5定义／8关联和种子进度保留，26源文件SHA不变，无播放轮次／会话／最近写入。

旁路取消域、惰性定位、未稳定IME图及外层字段留白检查失败均单列诊断，不计最终点；最终横屏亲看输入文字露出，不称键盘下所有动作同时可见。292项输入清单与只读复核通过，首批和追加AVD均恢复并关闭。未重跑全集或release、未发布APK。

[实施范围](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-tag-definitions/docs/plans/library-first/LF8-VIDEO-TAG-DEFINITIONS.md)／[固定源码、原图、API／SQL与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-tag-definitions/docs/plans/library-first/evidence/lf8-video-tag-definitions/README.md)。本段补TAG-01及相关UI组合；历史记录保留各自版本边界，当前验收表不再列视频定义真实CRUD为未做。原型1cbf605独立可移除未改；正式8760／NAS／SDK和签名／版本未改，#24/#33/#78及整体验收仍开放。后续继续合并后的完整来源／冷启组合、更多异常与目标手机／NAS及原签名升级；需用户配合部分按授权暂跳过。

## 2026-10-27：六来源导航与三种真实冷启动（PR #82）

[Draft PR #82](https://github.com/ShiJiJS/video_viewer/pull/82)基于#81，固定生产／驱动c994273，生产和组件树未改。当前整合分支两类型×媒体库／标签／最近六条路径均实际进入内容并返回；两类前两来源跨24分页点击index25、完整27成员／序号和原卡片位置，队列／总览第一次系统返回只关面板。搜索、同名独立标签、排序、手动选择及最近条件隔离均核对。

三轮最后保存来源分别library／tags／recent，均停在设置页后真实强停活PID、确认消失，新PID通过专属生产安全凭据键免口令初始化；媒体库只恢复所属范围，标签条件留在标签，最近不污染媒体库，不自动播放。普通390×844每轮28点共84点；25项相关组件、analyze／格式／Ruff通过。每轮189源SHA保持，重启只GET且无新登录／stream，播放／最近／阅读七表前后逐行相同；301项输入只读复核通过，显示配置恢复、专属AVD已关闭。

首段有意强停导致工具失联／临时目录清理错误，不作普通绿灯；第二段完整通过。8次开发尝试的旁路参数／权威默认顺序／弱就绪／错误入口和过渡坐标均单列，不计最终点。没有重跑全集／release、大字／横屏，未发布APK。此段不是正式main发布包升级或正在播放／阅读中强停证明，其他目录／属性／故障组合及目标终验继续。

原图另发现两张总览缩略图503后停在“重试”，已新建[#83](https://github.com/ShiJiJS/video_viewer/issues/83)补有界自动恢复、关闭后取消、持续失败与手动读回；本轮只通过面板返回，不把这些缩略图算成功解码。当前RESULTS.md已替换NAV旧待办并记录PKG-03这个具体缺口。

[实施范围](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/LF8-NAVIGATION-RESTART.md)／[固定源码、原图、PID、接口／SQL与复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/README.md)。原型1cbf605独立可移除未改；正式8760／NAS、默认凭据键、SDK和签名／版本未改。#24/#33/#78及整体验收保持开放，下一步先处理#83这个实际图片加载缺口，再继续其它明确余项；需用户配合部分按授权暂跳过。

## 2026-10-27：总览缩略图有界恢复与在途取消（PR #84）

[草稿 PR #84](https://github.com/ShiJiJS/video_viewer/pull/84)基于#82，固定源码／驱动7dbf3fd，[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/LF8-THUMBNAIL-RECOVERY.md)及[104输入只读证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/evidence/lf8-thumbnail-recovery/README.md)。复查#82原始请求，旧代码已有两次退避，503后200发生于关闭阶段；修正此前“没有自动恢复”的初步判断。本段让缩略图单元格独立拥有可取消HTTP客户端，关闭动画、分页读取或地址／凭据／版本／图包变化时取消旧请求和计时器，手动重试重置预算，保留三列比例与重试入口。

22项组件检查、分析／格式／Ruff通过；普通390×844原生8点：六张503后各2–3次内真实解码，持续失败恰3次后停止并实际手动恢复；真实Android返回取消6个未完成响应，3秒无额外请求，重开6张再次解码。固定范围、当前第3页、横向模式和API图包详情相同，总览无新增写请求，26公开源文件SHA不变；5张面板矩形一致。没有SQL七表快照，不把这项读回称SQL逐行验证。

三轮原生开发失败及组件诊断单独保留，不计最终8点；原型树1cbf605仍独立可移除。AVD显示恢复并关闭，未发布APK。本段未重跑全集／release／大字／横屏／目标手机，超过24页分页目前为组件取消信号与接线检查，仍待实际原生跨页。#83及#24/#33保持开放，下一步继续该跨页与其余LF8终验。

## 2026-10-27：总览容量与跨24页实际取消（PR #85）

[草稿 PR #85](https://github.com/ShiJiJS/video_viewer/pull/85)基于#84，增加共享3许可的缩略图下载队列，等待时不创建socket，分页／关闭取消排队项、在途连接，完成／错误释放许可，保留原两次退避和三列比例。两个新增真实HTTP组件旧版基线失败（峰值24、63次仍未全解码），修正后24项相关检查通过；分析／格式／Ruff通过。

[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-pagination/docs/plans/library-first/LF8-OVERVIEW-PAGINATION.md)／[207输入只读证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-pagination/docs/plans/library-first/evidence/lf8-overview-pagination/README.md)。固定26aceab普通390×844同版连续三轮，各11点共33点：30页目标包实际24→6→24，清单等待阶段3下载取消、21排队无GET；真实Android返回取消未完成清单，重开仍第3页／横向／原范围，API详情及写请求相同。明确点第30页才新增一次正确进度写入，主图实际显示30/30。每轮50公开源文件SHA相同。

随后只调整未被跨页路径使用的六图驱动pending预期，56b2a74再过8点：六图503自动／恰3次上限／手动恢复、3在途＋3排队取消及重开；26源SHA不变。两提交生产／跨页驱动／夹具相同，非docs差异仅六图驱动，复核脚本明确审计，共41原生点，不称同一完整源码提交。没有SQL快照／全集／release／大字／横屏／目标手机结论。

一次footer滚动驱动失误和一次QEMU图形／主循环挂起退出均另存，不计成功；原配置重启恢复显示后完成三轮，最终AVD已恢复并关闭。原型树1cbf605继续独立可移除，未发布APK。#83跨页开发证据已补齐，issue保留草稿合并／终验状态；#24/#33继续其余验收，下一步内容页强停恢复与其它组合。

## 2026-10-27：内容页强停部分验证与暂停（PR #86）

[草稿 PR #86](https://github.com/ShiJiJS/video_viewer/pull/86)基于 #85，当前按用户“做完手头内容先停一下”要求收尾暂停。434278a 的普通视频／纵向图包各一次真实双进程，各7点共14个认可点；专用安全凭据新PID免口令、默认媒体库且不自动打开内容。到媒体库／最近的只读边界七表逐行一致，无写请求／视频流／阅读原图；明确点开后才新建范围。图包第4张、纵向模式、约15.41%偏移及相对几何恢复。18项相关组件、analyze／格式／Ruff与188输入只读复核通过；不是全集或每例三轮。

全屏仍未验收：5秒样本在准备期间已换到下一条，第一份原始runner成功被独立身份核查拒绝；395bf7c加同一视频断言并调整暂停／旋转准备后明确失败，尚未强停。两提交仅驱动不同，生产App／服务／runner相同，证据保留两份诊断与审计；不将其直接定性为产品恢复缺陷。后续先隔离自然结束与准备时序，再补全屏目标身份验证。现有视频协议未保存秒数，不声称按秒续播。

[整体进度](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-content-restart/docs/plans/library-first/PROGRESS-2026-10-27.md)／[阶段边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-content-restart/docs/plans/library-first/LF8-CONTENT-RESTART.md)／[原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-content-restart/docs/plans/library-first/evidence/lf8-content-restart/README.md)。LF0–LF7已有阶段实现，LF8及目标手机／真实NAS、原签名覆盖／回滚和正式发布仍未终验；backup_v2生产仍关闭、#78保留开放。专用AVD已恢复显示并关闭，原型1cbf605独立可移除，未发布APK。#24/#33保持开放，暂停不等于完成，不再启动下一阶段。

## 2026-10-27：恢复推进、全屏目标身份与误滚动修正（PR #87）

[草稿PR #87](https://github.com/ShiJiJS/video_viewer/pull/87)基于#86。生产播放器本来循环；旧“短视频自然换片”解释撤回。fb663a6的操作探针证明暂停按钮本已可点，ensureVisible却把视频page从0滚到0.8916、点击后约0.9709，后续服务收到位置PATCH、播放器释放，探针以No element失败；旧#86另记录实际当前ID改变。仅修测试为可见目标原位点击，禁止借滚动视频容器显露控件，并逐步核对原生URL／video_id。

f6a565e同版普通视频、横向全屏、纵向图包各一次双进程，共21点：活跃内容强停、旧PID消失、新PID免口令回媒体库、无自动内容；最近和媒体库只读区间七表逐行相同，无写入／stream／阅读image。明确点开才新范围；全屏各时点同ID，图包第4张／约15.41%偏移／纵向模式及相对画布几何恢复。4项既有播放生命周期组件和静态检查通过，[177输入只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-fullscreen-restart/docs/plans/library-first/evidence/lf8-fullscreen-restart/README.md)通过；不与旧14点累加，不称全集或每例三轮。

全屏完整通过后首个普通视频轮遭QEMU图形／主循环挂起退出，ADB消失与显示恢复失败原样保存；确认旧launcher和QEMU PID消失后按原配置重启，先恢复原显示，再完成普通视频／图包。不是App通过或已证明的App恢复缺陷，也不是连续无中断稳定性结果。最终设备已关闭。#78仍保留其它渲染／环境稳定性问题。

[阶段边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-fullscreen-restart/docs/plans/library-first/LF8-FULLSCREEN-RESTART.md)。用户已明确恢复推进，#24/#33继续开放。下一步把现有真实系统保存／选择与HTTP备份／完整恢复串成同一次流程，随后补大文件／故障组合；独立系统40MiB文件处理早已实现并测试，不再笼统标为未编写或把分段结果拼成整路通过。生产backup_v2仍关闭，原型1cbf605独立可移除，正式8760／NAS／签名／SDK／APK未操作。

## PR #88：系统文件、完整恢复与大文件取消

[系统文件备份往返与取消 PR #88](https://github.com/ShiJiJS/video_viewer/pull/88)。固定5373baa，小文件19,207字节与大文件40,964,503字节各一次真实系统保存／选取、HTTP上传、27目录确认及完整恢复，共24点、26张PNG；取消保存保留原任务与日志，取消选取没有导入或恢复。18,000条记录摘要、恢复后SQL投影及媒体SHA核对，271输入只读复核通过。生产代码未改、backup_v2仍关闭；下一步审计并开放正式完整备份能力、保留旧服务／v1兼容，再做发布前整版回归。不是三轮稳定性、客户端／服务端全集或目标手机验收，未发布APK；#24/#33/#32保持开放。

[实现边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-native-backup-roundtrip/docs/plans/library-first/LF8-NATIVE-BACKUP-ROUNDTRIP.md)／[固定源码与原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-native-backup-roundtrip/docs/plans/library-first/evidence/lf8-native-backup-roundtrip/README.md)。保留host文件读取引号、同名文档拒绝和遗留选择器启动诊断，中间流程不计最终24点；最终两例无需手动启动。图包版本按既有恢复规则＋1，SQL只比较明确投影，不称整库字节相同；Android实际处理未压缩文件，Git仅gzip保存同字节证据。独立原型与原四个服务未改，临时容器／显示／AVD已归还。

## PR #90：完整备份公开入口与旧版兼容

[完整备份公开入口 PR #90](https://github.com/ShiJiJS/video_viewer/pull/90)。开发源码已声明backup_v2、移除测试额外注入，旧服务入口／v1任务协议与默认32 MiB保留。2f62dd0完整回归：客户端670项、服务端447项通过；27个既有文件格式未过，与基线相同。6287cc4正式原生一轮14点／15图、283输入只读复核通过，公开入口、真实系统文件与完整恢复走通。偶发上传连接失败尚未定位，已登记[#89](https://github.com/ShiJiJS/video_viewer/issues/89)，一次成功不能算修好。下一步定位该失败并验证原请求保留／重开只读核对；仍为草稿，未部署正式8760／NAS或发布APK，#24/#33/#32/#89保持开放。

[实现／后续](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/LF8-PUBLIC-BACKUPS.md)／[固定源码与原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/evidence/lf8-public-backups/README.md)。原生19,204字节同文件保存／读回SHA一致，27目录明确恢复、代次变化、两类后来标签移除与快照只预览通过；系统两种取消不新建导出／不上传。此前桌面无响应、上传失败、初扫409及文档XML未就绪分别保留；临时日志诊断通过不并入正式14点，通用传输未改、无自动重发。原型独立未改，容器／显示／自有AVD归还、原四服务ID不变。目标手机、云文档提供器、NAS及原签名覆盖升级仍待验收。

## PR #91：上传失败记录与真实进程找回

[上传失败原因与原任务找回 PR #91](https://github.com/ShiJiJS/video_viewer/pull/91)。App保留底层异常／等待阶段，提示及不重发写命令的规则不变；672客户端、28相关检查通过。848a1b8正式受控回复中断／双进程找回12点和普通完整恢复14点，共26点／28图，325输入复核通过；旧PID停止并移除本机输入后，新PID免口令只GET原任务、27目录预览且确认关闭。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复仍未完成，不把已受理回复中断当作原始问题。先前host归还显示失败已修，原配置恢复后重新验证通过；服务生产源码未改，27个旧格式问题待处理。原型独立未改、资源已归还，未部署NAS／发布APK，#24/#33/#32/#89保持开放。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/LF8-BACKUP-UPLOAD-DIAGNOSTICS.md)／[原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/evidence/lf8-backup-upload-diagnostics/README.md)。组件的真实拒绝连接／重建对象／缺少本机输入／两次原请求404，日志保留且零POST；明确区分内存日志与原生安全存储。受控样本读取回复时HttpException，重开14次GET、零POST、原键／同任务／SQL回执／代次相符；普通样本完整替换及快照只预览。中间d22d6fc覆盖屏幕配置变量导致归还失败，两例单列不计最终点，修正并使归还失败非零后重新验证。两类各一次，不称三轮稳定性；原始偶发原因、目标手机／NAS／云文档及覆盖升级继续。

## PR #92：正常入口预览包与原签名覆盖升级

最新阶段：[原签名预览包与覆盖升级 PR #92](https://github.com/ShiJiJS/video_viewer/pull/92)。固定cf992025，27个旧格式文件已修，139份服务Python前后AST相同；原型移除副本十步全部通过，客户端672项／服务447项。正常入口0.2.0-preview.1+6沿用Windows原签名，独立AVD实际APK5→6覆盖安装：免口令、原地址／设置及七表选定投影／登录摘要保留，新服务下启动进媒体库且零自动播放。两套标签、图包第2页横向转纵向／返回已实测；实际旧服务0004按原兼容模式保留视频UI。APK与Linux ARM64配套镜像仅输出本机预览，原型独立未改，未正式发布或部署NAS。完整服务迁移／回退、App回退、目标手机／NAS及其它验收继续；#89原始故障未复现、#78保持开放，#24/#33不关闭。

[安装与回退说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/library-first-preview.md)／[源码、原始记录和只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/plans/library-first/evidence/lf8-preview-package/README.md)。产物源码cf992025、证据4f82213，APK的SHA256为d87e98c70d4999b50165ce854f2e4f7156d25cc378f0431ed885f061c1cb9f87。旧／新包首次安装时间及数据目录相同，新PID启动26次GET、没有登录或自动流请求；深色开／相邻准备关保留。图包合成三图2/3实测，不冒充高分辨率长图包或真实手机验收。旧服务兼容可能按旧逻辑直接播放，完整新媒体库需要配套新服务。独立5556及8771/8772已归还，原四服务ID和运行状态不变；服务归档仅linux/arm64，正式NAS部署还需核对实际环境。

## PR #94：视频任务状态与真实旧数据升级回退

[草稿PR #94](https://github.com/ShiJiJS/video_viewer/pull/94)基于#92。服务源码b79da7b9、证据1b31995，正常runtime为preview.2，App仍是cf992025的正常release APK6，客户端生产源码未改、未重跑客户端全集。真实旧任务成功1/失败0却显示待核对，已登记#93并修正；旧JSON/回执不改，异常与部分成功保持原分类。最终15项新增检查在旧代码5失败/10通过，修正后相关21项、完整服务462项及Ruff/格式通过。

`accepted-1/2/3`三轮同一公开样本全部完成：2视频（可用1/回收1）、1标签2关联、原轮次2成员及3请求记录，正常启动迁移0004→0014，自动快照旧表相同；原凭据免口令，新媒体库无自动内容，旧任务已完成、原回执不变。UI新建标记标签后停机恢复完整基线，核对容器内版本/完整性/SHA，再启动原旧镜像，旧UI及原记录保留、标记消失。六个App PID、51成功图（另3基线/5诊断）、336输入只读复核通过；控制登录窗口单列，不冒充整份trace零登录。

首次cf任务问题、一次QEMU退出与一次旧容器首启报告0014而宿主恢复为0004的失败均保留，未计入最终三轮；后者原因未确定。最终驱动关闭SQLite连接，在原绑定目录和数据库文件内恢复内容，并先做容器侧核验。当前三轮通过不等于#78已修复。最终自有AVD关闭、11容器移除，原四服务ID/状态、上一阶段数据与媒体SHA未变。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/LF8-UPGRADE-ROLLBACK.md)／[固定源码、原始记录与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/evidence/lf8-upgrade-rollback/README.md)／[配套安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/library-first-preview.md)。本段补UP-01/02和SET-05明确组合；App回退包、真实手机/NAS、当前新服务配旧客户端完整终验、禁用根其它组合及其余原型验收继续。#89原始上传故障未复现，#78仍开放；原型1cbf605保持独立可移除，未正式发布或部署NAS，#24/#33/#32保持开放。

## 2026-10-28：App回退包与反复覆盖安装（PR #95）

最新阶段：[原签名App回退与反复覆盖安装 PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)。固定a3c7659a，配套新媒体库0.2.0-preview.2和旧界面0.1.4-rollback.2均code8、原Windows签名。旧界面窄适配保留新版偏好/多范围日志及凭据代次，未知v2备份任务保留并要求回新版核对；85旧版/兼容+14新版相关检查、双方analyze及正常release通过。独立Android36同一QEMU实际6→新8→旧8→新8→旧8→新8，五次install -r、首次安装时间/身份/数据目录保持、六次免口令冷启，新版零自动播放。旧UI主题/相邻准备修改后新版顺序/迁移标记保留；旧视频回收/菜单撤销完成，升回任务可核对；图包第2页纵向/两套标签保留。148输入及两包只读复核通过，22组原生截图；一容器/自有AVD已归还，原四服务及前阶段数据/媒体未动。配套服务仍b79da7b9 preview.2，原型1cbf605独立未改；未正式发布/部署，目标手机/NAS、500页高分辨率和其余终验继续，#78/#89与#24/#33保持开放。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/LF8-APP-ROLLBACK.md)／[固定构建、两轮实际安装与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/evidence/lf8-app-rollback/README.md)／[安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/library-first-preview.md)。本段只补UP-02的本机App回退组合。内部code相同可反复替换已在该AVD实测；不能覆盖code>8，后续版本需同步生成回退包。切换前先完成/核对管理任务，进行中或未知v2任务不交旧版接管。偏好扩展字段使用明确公开文件样本，再经真实UI写当前迁移标记；不把文件样本称为全由UI生成。原旧界面、播放器和API业务保留，属于附兼容存储的回退包，不是原Windows APK字节复刻。当前新服务配旧客户端只核对列明组合，完整旧功能/禁用根其它组合、目标手机/NAS和其它终验继续。

## 2026-10-28：复杂图包性能测量（PR #96，进行中）

两份公开NASA/JSC摄影图以原像素裁切拼接为506页/3,423,051,928字节：500页长包中400页4000×6000、100页8000×8000，另两类各3页。是摄影像素压力样本，不是506张独立照片，不代替真实图包/SMB。正常runtime preview.2完整扫描无失败，解码子进程峰值152624KiB；生产App/服务及原型未改，普通安装包仍按PR #95。

新增独立profile入口，计划每类30次Flutter缓存冷首图、正常相邻翻页、连续拖过500页、内核PSS/RSS/VmHWM和帧时序；静态检查通过，原型独立。前三次采集错误（异步tester保护、控制消息分块协议、Tooltip类型）分别修正/留档，不算产品故障。随后SWANGLE/GLES在8次4K重复后bad color buffer/GL context异常、QEMU81429挂起并离开进程表；内核PSS采样最大196416KiB、RSS高水位297432KiB，不能据此诊断App OOM。只在确认进程消失后换官方CLI支持的SwiftShader复测；另一次进度确认等待超时，正在加完整状态诊断，尚未归因。所有失败均不算成功轮次，不用8次样本冒充30次分位数。

[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/LF8-READER-PERFORMANCE.md)／[当前诊断记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/evidence/lf8-reader-performance/README.md)。完整30次、三轮500页、普通release入口与目标手机/NAS仍待完成；#78/#89与#24/#33保持开放。指定SMB目录在Mac可读，目前只确认路径可达；未把它当成真实图包已验收，未扫描/修改真实收藏或NAS服务。
