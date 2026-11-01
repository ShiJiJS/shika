# 媒体库与图包改造实施方案

> 最新源码：扫描详情展开按[#120](https://github.com/ShiJiJS/video_viewer/issues/120)接入160ms/实时减少动画，12针对/32组像素/789完整客户端与分析通过；[实现和边界](LF8-EXPANSION-MOTION.md)。真实Android/正常新包继续，当前code17候选不含该段。

> 最新候选：preview.11/rollback.11同code17已完成本机覆盖/回退与复选框正常业务核对，见[配套包结果](LF8-CHECKBOX-PACKAGE.md)和[357份原始输入](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-checkbox-package/README.md)。旧code16保留；完整原型/目标环境继续。

> 当前进度（2026-10-30）：正常preview.10/rollback.10同code16已完成本机候选交付，菜单/下拉源码、独立Android三轮和媒体库主业务已补齐；原版0.1.4服务首页菜单组合已由[补证](LF8-LEGACY-HOME-MENU.md)完成。完整766客户端/分析、覆盖保留登录/偏好/21表、主动业务差量和环境恢复通过，见[PR #114](https://github.com/ShiJiJS/video_viewer/pull/114)及[结果](LF8-MENU-DROPDOWN-PACKAGE.md)。真实手机/NAS、有声/云提供器、其余UI-06与完整45项终验继续；[RESULTS.md](RESULTS.md)为当前入口。下文旧“最新阶段”保留当时记录，原规划范围与验收条件继续适用。

最新阶段：[复杂图包性能测量与诊断 PR #96（进行中）](https://github.com/ShiJiJS/video_viewer/pull/96)。新增两份公开摄影原图衍生的506页/约3.4GB夹具（500页长包含400页4K/100页8K），正常服务扫描无失败；profile重复计时、被动内核PSS/RSS/VmHWM与汇总工具已提交，生产App/服务/原型未改，正常安装包仍为PR #95配套版本。三处采集错误已修正并分开保留；SWANGLE/GLES出现bad color buffer/GL context异常，QEMU81429挂起并确认退出，该轮失败，不诊断为App OOM。现以同数据SwiftShader复测，另一次进度确认等待超时正补状态诊断；尚无完整30次分位数/三轮500页结论。真实手机/NAS与READ-06完整验收继续，#24/#33/#78/#89均不关闭。

## 2026-10-26：缺失内容管理与待核对结果（PR #69）

[Draft PR #69](https://github.com/ShiJiJS/video_viewer/pull/69)基于 #68，生产及主流程源码固定 2369f0d，证据提交 8813c78。缺失内容改为 Paper 全高度页，视频/图包继续分别读取；名称、完整路径、类型/标签、实际根目录状态分层，保留 24 条分页、刷新、原请求和任务详情。危险清理位于列表之后，短确认层保留完整风险说明；普通/大字标题为 52/72dp，正文 20dp，次级色与原型浅暗色一致。

修正两个真实长列表问题：底部提交后先揭示顶部错误/原请求入口，避免惰性项未挂载而滚动失效；显式翻页成功回到新页开头，读取失败仍保留原页、成员及偏移。通用联调的原型元数据改为可空，不再要求独立设计目录一定存在；未据此声称已完成删除原型后的构建演练。

21 项相关客户端检查连续三轮、analyze、变更 Dart 格式与 Ruff 通过。普通/大字/短横屏各 13 点，同源码 39 个原生前台检查点；另同生产源码补大字/短横屏页尾与确认末尾共 4 图。每轮真实 27 包→25 缺失，停用清理保留 25 包及标签/进度/偏好/最近；返回一包后明确清理 24 条管理记录、保留返回包与原历史成员身份。两次 POST、一次原请求 GET、当前完整视频范围、源图片 SHA、数据库投影及五轮显示恢复均核对。第二次丢回执后的 App/Repository 重建发生在同进程，不冒充强停证明。本段未重跑客户端或服务端全集，服务生产树与 #68 相同。

独立存量首轮、中间普通复核、最终三视口及页尾补充复核，冻结 1 问题/1 提升已关闭：次级色过浅和分页到清理的间距已处理，完整页尾与确认末句可读。保留原生字体/真实安全区差异，静态图不作为完整动效或手势证明。失败脚本前置、真实结果不可见、分页起点修正和两次 QEMU 崩溃/恢复均单列诊断，不计最终成功点。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/LF8-MISSING-MANAGEMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-missing-management/docs/plans/library-first/evidence/lf8-missing-management/README.md)。本段补 SET-04、DEL-06 与 UI-03/04/05 的明确组合，完整其它管理、旧服务/扫描异常、预览/阅读手势、500 页 4K/8K、目标手机/NAS和原签名升级继续；需配合部分按授权暂跳过。冻结原型 1cbf605 独立未改且可移除，backup_v2 仍关闭，未发布 APK 或改正式 8760/NAS/SDK。#33/#24 保持开放。


## 2026-10-26：图包库真实继续阅读（PR #59）

[Draft PR #59](https://github.com/ShiJiJS/video_viewer/pull/59)基于#58，固定源码c4aaf3b，证据提交daf1863。图包媒体库在无筛选/搜索且非多选时显示真实最近打开包与页码；摘要独立于24条分页和列表取消通道，只读且不创建历史。点击从该包续读，保持原媒体库完整范围，返回原位置。搜索、多选、最近来源不展示全库续读条；失败保留列表并就地重试。

普通三轮、360双倍字号及844短横屏共五轮同源码通过，每轮10个真实前台检查点，共50图；公开2视频/4包/24PNG，实际打开后从3/6翻到4/6，续读仍为完整4包范围。两次显式opened、SQL最近/进度/会话投影、只读区间、26个源文件SHA与设备配置恢复均核对。202份manifest输入只读校验通过。客户端471项、服务端续读/阅读16项、analyze/Ruff通过；不是服务端全集或目标设备性能证明。

原生字体的实际行高取代估算，普通续读86dp（参考85）、双倍字号147dp，无裁切；共享“更多”菜单收起搜索键盘，修复短横屏进入多选时的4.7dp溢出。两轮独立存量视觉复核后无本段必须修正项；首轮材料、字体/键盘失败诊断与最终五轮分别保存。长标题/错误说明省略仍是已知显示边界，未缩字号或缩短压力输入。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/LF8-PACK-CONTINUATION.md) / [原始证据与可重跑校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/evidence/lf8-pack-continuation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/RESULTS.md)。本段补LIB-02、NAV-02、READ-04/05、REC-01与UI-01/04/05的明确组合，不关闭整项；使用MemoryCredentialStore，不新增强杀/安全存储或覆盖升级证明。

下一步继续权威两类总数、保守标题/作者与服务端排序，再核对完整预览/阅读/管理、键盘和手势；500页4K/8K、目标手机/NAS和原签名升级仍待验证。冻结原型1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：共享比例与45项原型收口台账（PR #58）

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)基于#57。固定App/最终取证源码`a9da395`，证据提交`6b71cd1`：两类库统一搜索55dp/输入42dp/文字16dp、范围工具60dp，顶栏与300dp居中导航对齐；设置分组和约40×24可见开关收回原型比例，整行至少64dp可点，支持单一开关语义与键盘，原回调和存储保留。标签确认区去掉过多留白，输入填色和设置说明已调整。

真实8768新库的2视频/4包/24图，普通三轮、360双倍字号与844短横屏各一轮通过，共40个ADB检查点；16项针对组件检查、analyze/Ruff通过，235份manifest输入独立复核通过。独立存量视觉评审两轮后，本轮布局项已复核处理；早期主题过渡帧、屏外懒加载前置和组件测试清理失败单列诊断，不混入正式成功。服务端/全部业务全集本轮未重跑。

新增[45项收口台账](RESULTS.md)、[尺寸与明确差异](LF8-SHARED-GEOMETRY.md)和[原始证据/只读校验](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-shared-geometry/README.md)。正常原生窗口390×905，实测49/24dp安全区，和HTML390×844移除12px模拟区后按390×832内容比较，不拉伸全屏。大字/横屏另按实测安全区记录。

下一步按台账补图包继续阅读区、权威类型计数、保守标题/作者呈现与服务端排序/分页一致性，再收口完整预览/阅读/管理/键盘/动作。500页4K/8K、目标手机/NAS和原签名覆盖升级仍待验证。原型树1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：按实际点中的可见末张跳过（PR #57）

[Draft PR #57](https://github.com/ShiJiJS/video_viewer/pull/57) 基于 #56，固定源码 `07d1cad`，证据提交 `92f08b8`。纵向视口顶部仍在倒数第二张时，可以点击下方可见的失败末张。旧逻辑按顶部index拒绝该点击；现按所点图片进入原末尾页，不自动换包，不把失败图片记成首帧或完成进度。

新真实HTTP组件检查在旧逻辑失败，修正后与原五项图片检查共6项通过；完整客户端457项、analyze及夹具/脚本Ruff lint通过。服务端生产代码未改，402项全集沿用#55且本段未重跑。原生390×844普通字号三轮59.20/39.59/38.89秒，顶部index=1、点击图片index=2、比例约70.94%，关键点击没有先滚动对齐；进度前后完整对象相等，包含revision与更新时间，返回原失败末张、退出重开恢复原页/比例，明确下一包才推进。独立SQL仍是上一张真实图片、未完成。

另按同源码跑既有末张/损坏图片844横屏回归一次35.93秒。三轮加兼容回归共21张实际窗口截图、6张源图前后SHA、原始HTTP与SQL投影已保存；119份manifest输入独立复核通过。普通字号三轮不冒充其它视口组合或安全存储强杀验收。

[核查与修复说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/LF5-VISIBLE-PAGE-SKIP-AUDIT.md) / [固定源码与证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/evidence/lf5-visible-page-skip/README.md)。本段补READ-02/04/05与PKG-03的明确组合，不关闭整项。接下来推进整体原型对照；其它异常/连接恢复/迟到图片、500页4K/8K性能、目标手机/NAS及原签名发布仍开放。生产backup_v2仍关闭，冻结原型1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24保持开放。


## 2026-10-26：失败末张与横屏错误操作（PR #56）

[Draft PR #56](https://github.com/ShiJiJS/video_viewer/pull/56) 基于 #55，固定源码 `e68f487`，证据提交 `fc97f17`。原型 advance(1) 越过末张会进入 finished；App 原来把“跳过这一张”截回失败末张，且禁用了末张“下一张”。现已接到原生现有本包末尾页，可返回末张/来源，只有明确点击下一包才切换原固定范围；失败图片没有首帧，不写opened、最近、进度或完成状态。

沉浸中到达末尾显示工具，返回动作在黑色画布用白色保持可读。真实844横屏发现17像素溢出，失败/末尾区改为短视口可滚动，保留字体和操作。五项真实HTTP 404/HTTP200非图片解码及完整阅读路由检查回放旧生产代码全部失败，修正后通过。

完整客户端456项、analyze和新夹具/脚本Ruff lint通过。客户端全集在bc3c9fb执行，lib/test树与最终源码相同，最后仅改取证滚动；服务端生产树未改，402项全集沿用#55且本段未重跑。固定源码三轮（360双倍字号37.84秒、390普通36.09秒、844横屏38.74秒）通过，18张实际前台截图、六张源PNG前后SHA、原始轨迹及独立SQL投影保存，253份manifest输入已复核。SQL证实异常包没有progress行、recent只有手动进入且真实显示首帧的正常包。旧源码成功、17像素溢出、测试等待/取证偏移等开发记录单独保留。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/LF5-IMAGE-ERROR-DESIGN.md) / [固定源码及证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/evidence/lf5-image-errors/README.md)。本段补PKG-03、READ-01/02/04/05、UI-04/05的失败末张路径，不关闭整项。其余图片错误码/连接恢复/迟到图片、500页4K/8K性能、全原型与目标手机/NAS、原签名发布仍开放；本段使用MemoryCredentialStore，不作为强杀/安全存储证明。生产backup_v2仍关闭，冻结原型树1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24继续开放。


## 2026-10-26：原历史删除清单与逐项结果（PR #55）

[Draft PR #55](https://github.com/ShiJiJS/video_viewer/pull/55) 基于 #54，固定源码 `cabbc68`，证据提交 `0e0c1a5`。设置→操作任务→历史详情现可查看原确认清单、包内精确文件及永久删除的原图片/目录结果。三个认证 GET 绑定原 graph、父任务、计划与包条目；缺失或无效关联不退回当前库。文件 manifest 在 SQLite 内分页，App 专用网关没有执行、重试删除或结算能力，旧服务及缺失原图明确说明。

原生隔离8763真实扫描27包/153图，0101.png权限失败后实际126图已删、27图未完成；完整恢复后读回原历史。27包末3包、127图末页、54项目录、查询503保留原页再同GET重试及原预览入口均通过。固定源码三轮（360双倍字号64.96秒、390普通55.14/58.00秒），21张实际窗口截图、54份剩余源文件、原历史SQLite与三份真实安全日志前后核对；274份manifest输入已入库并独立校验。Paper比例延续既有页面，两尺寸目录结果及“图包根目录”文案复核通过。

完整客户端451项、服务端402项、analyze、Ruff lint和132份Python语法检查通过。服务端全集启动于9199f31、客户端全集于619033c，其完整服务端/客户端lib及test树均与固定源码相同。Ruff format继承23份、Dart format继承2份既有文件，未误报全量格式通过。实际43,806,720字节SQLite/18,000条manifest的分页Python分配峰值2,550,992字节，不能当作进程RSS、Android内存或NAS性能。首次Docker未加仓库规定shm参数的401通过/1失败、原生定位/等待失败和旧源码成功均单独留存。

[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/LF7-PURGE-HISTORY-DESIGN.md) / [原始证据与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/evidence/lf7-purge-history/README.md)。本段补齐BAK-03、SET-05、DEL-04/06的历史读取部分；其它命令/来源强停、历史图片解码/资源不可用、全原型暗色/横屏/手势、目标手机/NAS及原签名发布仍继续。生产backup_v2仍关闭，冻结原型树1cbf605独立未改；未改正式8760/NAS/SDK或发布APK。LF7/#32及总任务/#24保持开放。


## 2026-10-25：v2 App 三处真实强停与原日志重开（PR #54）

[Draft PR #54](https://github.com/ShiJiJS/video_viewer/pull/54)基于#53，固定源码2839c5d。真实v2完整替换在snapshot_written、after_replace_before_commit、restore_committed三个服务位置扣留202，安全日志先落盘；宿主强停活跃PID并确认消失后，服务在App缺席时完成同一任务，新PID免口令自动重连新代次。六条旧本机意图、原私有文件和两个真实受理的图包任务/原graph成员都保留；重开只GET和既有启动扫描，不重发原写入。实际系统快照保存取消后不结算旧记录，历史未提交选择不能继续删除。

固定源码三轮（360双倍字号115.47秒、390普通79.17/81.29秒）通过，164份manifest输入已入库并独立核对；首段有意强停的非零退出和开发失败日志分开保留。analyze/Ruff/Python语法及24项服务端针对检查通过。App/服务端生产树未改，433/398项全集沿用#53且本轮未重跑；这里不是40MiB全路恢复、Android内存或整机断电验证。[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/LF7-ARCHIVE-RESTART-DESIGN.md) / [固定源码、原始日志与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/evidence/lf7-archive-restart/README.md)。

接下来继续历史专用永久删除精确清单/逐页结果及只读页面（原graph绑定、有界分页、不得借用当前投影或执行/结算接口），然后其它命令/来源强停、历史图片失败、暗色/横屏/手势、目标设备/NAS和原签名发布。生产backup_v2仍关闭；原型树1cbf605独立未改，未改SDK/正式8760/NAS或发布APK。LF7/#32、总任务/#24保持开放。

用户已确认以当前完整原型为实施方向。本次先确定框架、拆分任务和验收依据，后续分阶段实现。总任务和子任务链接见 [ISSUES.md](ISSUES.md)。

## 1. 交付目标与依据

交付现有 Android App 的一次兼容升级：打开进入媒体库，视频与图包分别筛选；选定内容或范围后进入视频预览或图包阅读；返回保留来源。视频与图包的标签独立，图包管理以整包为单位。设置保留现有 0.1.4+5 能力，并扩展图包管理。

依据及优先级：本次用户要求 → 当前 `design/reference/library-first/` 完整原型与 `SETTINGS-AUDIT.md` → 本方案与验收表 → 旧 V1 文档。旧规格中“默认打开浏览播放”“图包不进入第一版”仅描述历史版本，不再限制本次升级。旧文档保留，不无声改写历史。

- 业务代码基线：Git `137ad0e7b02643d463c7e0f17365d23c06806036`；Mac 工具链改动作为开发前置单独提交；LF0 的原型、规划和骨架分别有提交锚点，详见 LF0 记录。
- 原型入口：`design/reference/library-first/app.html`，总览 `index.html`，设置补齐记录 `SETTINGS-AUDIT.md`。
- [baseline.json](baseline.json) 保存当前原型源码、运行依赖及参考截图的 SHA-256。原素材版哈希仅作历史对照；当前隔离版本由 `design/reference/library-first/baseline-sha256.json` 锁定源码和合成素材。私人图包、密钥和原素材截图不提交。
- [ACCEPTANCE.md](ACCEPTANCE.md) 是逐项验收清单，不能用“接口成功”替代“原生页面与完整路径一致”。

“与原型一样”指信息结构、尺寸层级、入口位置、操作结果与返回行为一致。Android 系统状态栏、系统文件选择器和字体栅格差异可保留；不得借平台差异省略页面、设置项、错误状态或范围语义。模拟数据中的标题、作者与页数不是正式数据协议。

## 2. 现有代码与差距

| 位置 | 当前能力 / 发现 | 改造方式 |
| --- | --- | --- |
| `apps/mobile/lib/ui/home.dart`，2624 行 | 同一 State 承担浏览、库、标签、设置、回收、备份；连接后进 browse；筛选直接改播放范围 | 拆成导航外壳、入口查询状态、功能页和管理页；视频预览作为二级 route |
| `library/models.dart` / `repository.dart` | 仅 LibraryVideo、VideoQuery、MediaRoot；同步 snapshot 只含局部网络缓存 | 保留视频实体，增加图包/页/阅读状态；所有库、计数、全选都走分页权威接口 |
| `library/server_repository.dart`，1722 行 | setScope / openVideo 修改全局轮次；列表搜索另传 search | 查询与会话命令分离；把名称搜索、排序、来源带入创建范围，不能丢失搜索或只预览已加载页 |
| `ui/browsing_session.dart` | 跟手选中与迟到回执隔离、有界元数据窗口、异步删除 | 复用机制；补来源恢复和固定范围契约，不把图包页塞入视频会话 |
| `ui/player.dart` / `playback_session.dart` / `device_controls.dart` | 原生播放、最多 3 个解码器、倍速/暂停/横屏/亮度音量 | 保留，入口改变时验证生命周期，不重写播放器引擎 |
| `ui/preferences.dart` / `paper.dart` | 本机主题、相邻准备、P2 颜色字体 | 复用，增加集中尺寸 token；本机偏好不进入 NAS 管理备份 |
| 服务端 `models.py` / `catalog.py` | roots 无类型/启停，所有扫描与查询针对 videos；视频标签名称全局唯一 | 旧记录默认 video/enabled；图包、图包标签和关联采用独立表 |
| `app.py` PlaybackScope / `playback.py` | scope 无 search；eligible 每次重新套标签条件；删除标签会重建轮次 | 新会话协议保存完整候选；开始后不因改标签重排，只有不可用/回收/停用条目不再可选 |
| `scanner.py` / `identity.py` / `streaming.py` | 视频稳定性、身份、授权文件读取已有机制 | 保留；新增图包扫描与图片读取，复用路径校验和受控后台调度 |
| `file_operations.py` / `file_command_store.dart` | 逻辑回收、幂等命令、待确认只读核对、旧物理回收兼容 | 沿用协议语义，新增图包执行逻辑和整包清单，保留原视频安全机制 |
| `backup_format.py` / `backups.py` / `server_backups.dart` | 正式备份 v1 / schema 0004，完整性/映射/前快照/断线恢复 | 引入正式 v2 导入导出；支持 v1 转换，保留现有恢复保障 |
| 最近与图包阅读 | 没有正式实现 | 新增最近记录、按包页码/偏好、横翻/纵向/总览/沉浸与整包整理 |

源码优先于过时说明：服务 README 中仍有“物理回收”历史叙述，现行逻辑以 `file_operations.py`、`docs/logical-trash-and-browsing.md`、0.1.4 补充为准。当前行为与本次新决定冲突时，在对应 issue 和测试中明确迁移，不靠旧测试文案继续旧导航。

## 3. 确定的模块框架

继续 Flutter + ChangeNotifier/不可变状态、FastAPI + SQLite/Alembic、Docker 单服务。没有为此次改造引入新的状态管理框架或后台微服务的必要。

```text
AppShell（媒体库 / 标签 / 最近 / 设置；默认媒体库）
 ├─ LibraryPage / TagsPage / RecentPage → LibraryQueryController
 ├─ VideoPreviewRoute → PreviewSession → 现有 BrowsingSession + PlaybackSession
 ├─ PackReaderRoute → PackReadingSession + ImageWindow
 └─ Settings / Roots / Trash / Backups / Tasks → MaintenanceController
                         ↓ 同一行为接口
              Server adapters / Demo adapters
                         ↓ ServerApi
 Catalog / Playback / Packs / Reading / Tags / FileOperations / Backups
                         ↓
             SQLite 管理数据 + 授权 NAS 文件读取
```

建议目录（在迁移中逐页拆出，不一次性移动全部旧代码）：

```text
apps/mobile/lib/
  app/app_shell.dart, navigation_state.dart
  library/                    # 现有 transport、凭据、命令回执、视频兼容入口
  features/library/           # MediaKind、各类型查询、分页、列表位置、标签页
  features/preview/           # 来源、候选范围、视频预览 route
  features/packs/             # 图包模型/查询、阅读 session、图片窗口与页面
  features/recent/            # 最近列表
  features/settings/          # 连接、目录、回收、备份、任务
  ui/                         # Paper、共享控件、现有播放器及设备控制
services/server/video_viewer/
  packs.py, pack_scanner.py, images.py, reading.py, pack_operations.py
  # 现有 catalog/playback/tags/backup 等按职责扩展，不复制整套服务器
```

接口按行为划分为四个模块：Catalog（查询）、Viewing（进入/推进会话）、PackReader（按页读取/存进度）、Maintenance（管理命令/任务核对）。每个模块隐藏分页取消、版本冲突和任务轮询细节；页面不调用 SQL、HTTP 或 NAS 路径。读取可取消且迟到结果不发布；命令返回已受理任务或明确失败，未知结果保持可查询；分页计数是服务端权威值，禁止同步查询全库作为 UI 前置条件。Server 与 Demo 是实际存在的两个 adapter；不为假想扩展引入额外接口层。现有 LibraryRepository 暂作兼容入口，等各页迁完后删去重复方法，不长期双写两套状态。

### 状态归属与接口契约

| 状态 | 权威归属 | 契约 |
| --- | --- | --- |
| 视频/图包元数据、两类标签、根目录、回收、缺失 | 服务端 | 稳定 ID；类型匹配；计数来自接口，不从已加载卡片估算 |
| 页面类型、两个搜索/筛选草稿、滚动位置、批选 | App 的 BrowseContext | video / pack 独立；切 tab 或退出阅读不丢来源；不写正在播放的轮次 |
| 视频预览 / 图包阅读范围 | 服务端会话 | begin(scope, source, order, anchor, requestId) 固化完整范围；分页取 entries；revision 防旧回执覆盖 |
| 当前视频播放意图与解码器 | App 播放模块 | 复用暂停/倍速/静音/资源上限，离开预览暂停释放；预加载不产生历史记录 |
| 每包进度与偏好、最近访问、默认顺序/阅读默认值 | 服务端管理数据 | 单用户本次就持久化并进入管理备份；客户端可缓存并节流同步 |
| 主题、相邻视频准备、连接凭据、窗口亮度 | 本机 | 不随 NAS 备份覆盖；口令不保存，token 仍在加密存储 |
| 未确认写命令 | 服务端任务 + 本机受保护回执 | 服务地址+实例 ID+request ID；重开只读查询，不自动重放删除/恢复 |

关键类型：`MediaKind(video, pack)`、`BrowseContext(kind, source, query, sort, scrollAnchor)`、`VideoQuery`、`PackQuery`、`PreviewScope`、`PackReadingProgress(packId, pageId, offsetRatio, revision)`、`ReadingPreferences(mode, direction, gap, fit)`。不把图片页当成可独立打标签/回收的媒体。

## 4. 数据与兼容策略

### 4.1 数据库

采用增量迁移，保留旧视频 ID、标签 ID、关联、轮次和文件操作回执。

- `roots` 增加 kind、enabled；历史根默认为 video / true。available 表示可访问，enabled 表示用户开关，两者不能混用。停用保留标签、进度及记录，排除普通列表/新会话/自动扫描；停用不能触发缺失清理。已有内容的根禁止直接改类型，需新建正确类型的接入范围。
- 保留 `tags` / `video_tags` 为视频标签；新增 `pack_tag_definitions` / `pack_tag_links`。同名跨类型合法，写入必须核对类型；这是比重写旧标签表风险更低的本轮选择。
- 新增 `packs`、`pack_pages`：稳定 ID、root、路径、可用/缺失/回收状态、封面页、页数、自然排序键和内容版本。页保存尺寸/格式/文件签名及其包 ID；缩略图是可重建缓存。
- 新增 `pack_progress`、`pack_preferences`、`recent_entries`（kind+entityId，最后实际打开时间）、`pack_sessions` / `pack_session_entries`。分页清单由服务端维护，不把全库 IDs/所有原图塞进 App。
- 图包回收索引、文件执行步骤独立存放；共用 Task 和受控执行队列。旧视频 FileStep/TrashItem 不改成无约束 polymorphic ID。
- 默认播放顺序、阅读默认值加入管理 settings 白名单；旧库从现有播放选择初始化默认顺序，旧数据没有的新字段使用明确默认值。

### 4.2 图包发现与图片服务

首版以配置根目录的直属文件夹作为包；包内子目录递归归属同一包。平铺图片不自动合为未知包，需提示调整接入根。页按相对路径各段做自然排序，数字 2 在 10 前，使用稳定 ID 作最终同序兜底；不依赖 mtime。文件夹名为默认标题，作者/编号解析可选且失败回退原名，不作为身份依据。

先支持 JPEG/PNG/WebP 常见静态图片，损坏/不支持文件返回可定位原因；压缩包直接阅读、动态图片播放、单张标签/删除、AI 标签、离线下载均不在此次范围。格式扩展不阻塞目录图包主路径。

扫描沿用完整成功范围才判缺失、离线不清理、变动文件延迟、后台并发受控原则。同目录新增/删页保持包 ID，尽量保留 pageId；同文件系统目录改名有唯一身份依据时保留；跨盘移动要有唯一完整清单/内容证据，歧义则保留旧缺失记录，不按名字或封面猜测继承标签。刷新清单后按 pageId 找阅读位置，页已删除时选择最近有效页并告知。

封面、分页缩略图和原图走鉴权接口；只接受受控 ID，不接收任意磁盘路径。缩略图失败不封锁整包；单页失败可重试或继续。纵向采用惰性列表和已知宽高占位，横向只保留当前/相邻图片；切包、离页、换连接时取消过期读取。缓存按字节设上限，具体值在 LF5 以 4K/8K 样本测定，不把无限 precache 当优化。

### 4.3 会话与接口演进

保留 `/api/v1` 现有视频协议，增加 `/info.capabilities`，新 App 遇旧服务给出兼容提示，视频路径可继续使用，图包功能明确不可用。新增路径为实施约定，LF1 落定 OpenAPI 后由接口测试锁定：

| 接口能力 | 方向 |
| --- | --- |
| roots / directories / library-state | 返回 kind/enabled，进度按类型区分；新图包首扫不阻塞已可用视频 |
| videos / rounds | 查询与创建范围都支持 search、sort、source；新会话带固定成员协议标记，旧调用保留旧默认行为 |
| packs、packs/{id}/pages | 分页包摘要、分页页清单、明确总数与内容版本 |
| packs/{id}/cover、pages/{id}/thumbnail、pages/{id}/image | 同源鉴权、版本缓存、流取消、受限并发 |
| pack-tags、pack-tag-links | 独立 CRUD/搜索/计数/交集、追加/替换语义 |
| pack-sessions / entries / position | 创建固定包范围、分页队列、revision 更新；全范围在服务端求值 |
| packs/{id}/progress、preferences；recent?kind=… | 进度/偏好和最近记录；实际进入才记历史，重复更新幂等 |
| pack-trash / operations；tasks | 按包标记、恢复、永久删除；任务按已有 request ID 查询机制扩展 |
| backups / imports / restores | 保留异步完整性校验、映射、确认与前快照，新增正式格式 v2 |

搜索按原型匹配视频名称与目录；图包匹配标题、目录及可用的作者字段，缺作者仍可正常按标题查找。新会话创建时，搜索、目录、标签交集、属性、排序和来源（媒体库/标签/最近）必须全部生效。最近来源按最近列表取候选，不偷用媒体库筛选。会话内改标签不重筛候选；删标签不会自动建立新会话。目录停用/离线、文件失效、回收后可跳过不可用项，但不添加新候选。模式切换只重排本范围；主动重新从入口进入才重新查询。旧轮次迁为已存在的条目快照，不默认扩大为全库。

App 保存来源 BrowseContext，离开二级页时恢复它并按新标签重新查结果；保存滚动 anchor，条目消失时选最近仍在的相邻项。系统返回、界面返回和横屏退出有同一约定：先退出全屏/面板，再返回来源；无来源的冷启动进媒体库。

### 4.4 删除、未知结果与备份

普通菜单移入回收站先确认；快速整理明确开启后直接整包回收，8 秒撤销绑定该操作。按当前原型，图包成功后才进入本范围下一包，已知失败留在原包，最后一包回到来源。视频保留现有跟手切换与异步提交机制：已知失败恢复条目；未知结果不显示成功。两者都保留待查询任务，撤销恢复原 ID、包内页码、队列位置与模式。

图包永久删除按确认时的已索引图片清单执行，执行前核对版本/路径/签名；目录中出现新文件、替换或身份不确定时停止并要求重新核对，不能无限递归删除。非图片附件保留；仅清理已空目录。部分成功逐项可见，重试只处理未完成项。具体确认文案在 LF6 与清单一起验收，不把永久删除伪装成逻辑回收。所有删除故障测试使用可丢弃样本。

管理备份 v2 包含两类标签、图包页身份、进度/偏好、最近、目录启停、会话、回收与回执；不含媒体字节、可再生缩略图、token、口令、主题、预加载开关。旧 v1 经校验后转换成 video 根/标签和空图包状态；这是完整替换，若当前已有图包记录必须明确展示将被替换，不静默合并。新备份不给旧服务强行导入。

升级先留旧管理快照，跑隔离实例迁移演练，再发布兼容服务端、最后 App。保留包名、原签名并提高 versionCode。回退新服务必须恢复升级前管理快照，不能拿旧二进制直接打开已迁移数据库；会明确提示回退会舍弃升级后管理修改。图包会话/备份不能复用 HTML localStorage JSON 作为正式协议。

## 5. 实施顺序与阶段完成标准

| 任务 | 交付 | 依赖 | 完成标志 |
| --- | --- | --- | --- |
| LF0 | 原型基线、接口清单、模块拆分及可运行骨架 | 无 | 保存参考证据，旧行为回归；无破坏式大重写 |
| LF1 | 增量 schema、类型根、独立图包标签、capabilities | LF0 | 旧库身份/标签/回执保留，类型隔离测试通过 |
| LF2 | 图包扫描、分页、封面/图片授权读取 | LF1 | 合成多层目录成包，变更/离线/坏图/大包通过 |
| LF3 | 视频入口范围、固定轮次、最近视频与兼容 | LF1 | 搜索/分页完整范围，改标签不跳位，播放器旧能力不退化 |
| LF4 | 四入口外壳、两类媒体库/标签/最近与 P2 比例 | LF2、LF3（骨架可先用 Demo） | 原生页面/返回路径与原型对应，真实分页不靠演示数组 |
| LF5 | 图包阅读、范围会话、进度与阅读偏好 | LF2、LF4 | 横翻/纵向/总览/沉浸/续读完整，内存有界 |
| LF6 | 图包快速整理、撤销、批量回收与永久删除 | LF3、LF5 | 操作 ID 与结果核对、原位置恢复、源文件保护通过 |
| LF7 | 设置全量接线、统一任务、v2 备份与迁移 | LF1、LF2、LF6 | 设置对照无遗漏；v1/v2 恢复、断线及前快照通过 |
| LF8 | 原型逐页验收、原生联调、升级包与目标设备 | LF0–LF7 | 验收表全部证据齐全，无“界面完成但 API 未接” |

按 LF 编号推进，不先堆阅读 UI 再猜数据契约。LF4 可提前做 Demo 页面，但不能在 LF2/LF3 未通过时标记完成。每个 PR 在正文写验收 ID、实际证据和剩余限制。Epic 只有 LF8 验收完成才能关闭。

## 6. 验证与风险控制

先建兼容夹具：含现有视频/标签/随机轮次/逻辑与历史物理回收/未确认操作的 0004 管理库，以及无私人内容的四个测试图包（自然排序、深层目录、坏图、空包、横竖混排、超长包、超大图片）。单元/接口测试覆盖不变量，原生 Android 集成测试覆盖完整路径，截图单独核对布局；不以 Demo 或 HTML 测试代替真实服务。

统一参考视口为 390×844，补 360×740 和 844×390；按逻辑像素比较 App 内容区，系统安全区单独计算。使用同一非私人素材、页码、标签、筛选和时间状态。关键尺寸：52 顶栏、49 导航内容区加系统安全留白、16 横向内容边距、12 列距、18 行距、211 封面（390 宽；360 宽 185）、16 卡片标题、15 设置行标题。禁止在 Android 底部额外画 HTML 的假 home indicator。需要增大点击区时可透明扩展，不扩大视觉卡片。

本机继续 `scripts/dev.sh`、VS Code F5、8760 开发 / 8761 可复位联调环境。Flutter analyze/unit、服务端 API/迁移/故障恢复、Android 集成、目标设备与 NAS 资源测量分层报告。当前 Mac 记录为 68 项客户端、98 项服务端历史通过，另有 12 个服务端 Ruff 格式文件基线失败；这些是历史依据，本次规划未重跑，不能作为新功能已通过。LF0 重新记录基线，后续不掩盖基线或新增失败。

主要风险及应对：

- 数据模型绑定视频太深：图包用独立表和接口，保留旧视频路径，逐模块迁移。
- 搜索/标签变动让范围泄漏：服务端固定成员 + 全量分页范围 + 明确最近来源测试。
- 新图包首扫拖慢视频：按类型准备状态、后台小并发、前台读取优先；量测再调缓存。
- 大包图片耗尽内存：惰性列表、按显示尺寸解码、有界窗口/缓存、取消旧请求；用真实机测峰值。
- 替换源文件和响应丢失：清单/版本核对、已持久化命令、只读查询、不自动重发。
- 完成后偏离原型：锁基线 + 每阶段原生截图 + [逐项验收](ACCEPTANCE.md)，行为变化先改方案/issue 并说明，不能只提交“类似的 UI”。

## 7. 范围与待实施决定

LF0–LF6 对应实现与验证见各阶段文档。LF7 任务中心见 [LF7记录](LF7.md) 和 [任务中心设计](LF7-TASKS-DESIGN.md)。各阶段保留未完成项，整份批次、完整设置、v2备份及 LF8 继续推进。尚未迁移或写入真实 NAS、发布新版 App。

技术选择（独立图包表、管理偏好服务端保存、静态格式范围、按清单永删）是本方案的实施建议，用户已确认的是产品方向与现有原型。若实施发现必须改变用户可见行为，需把差异具体列在对应 issue；无须为了普通命名/目录组织再次让用户选框架。


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

[设计与实现约束](LF8-READER-CHROME.md) / [固定源码、原图、诊断和只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-reader-chrome/README.md)。本段补READ-01–05及UI-02/04/05的明确组合，不关闭完整验收项。继续完整预览、阅读其它异常/方向/手势、完整管理、500页4K/8K和目标手机/NAS及原签名覆盖升级；需用户配合部分按授权暂跳过。原型1cbf605独立可移除、backup_v2生产能力仍关闭，MemoryCredentialStore不新增强杀/安全存储证明；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。

## 2026-10-26：视频预览范围、播放控件与操作面板（PR #66）

[Draft PR #66](https://github.com/ShiJiJS/video_viewer/pull/66)基于#65。

控制条按实际文字宽度排布，空间不足时分行，保留至少88dp拖动轨道及原字号；短横屏中央播放按钮避让控制条，空间不足时保留明确的控制条播放入口。面板覆盖期间禁用播放/速度，关闭后恢复原播放意图。范围正文统一滚动，保留有界读取和当前项定位；补完整筛选来源、浅/暗色切换及大字整理动作排布。

固定取证源码bd40372（生产与组件测试树bd40372），客户端完整540项、analyze、lib/test及本轮integration文件format、脚本Ruff通过。服务生产与测试树同基线40b85e1，本段未重跑服务测试。普通三轮、大字和短横屏各19点共95个视频点，另阅读器13点与最近17点同源码回归，共125个原生前台检查点；442份manifest输入只读复核通过，证据提交e97852d。

真实服务路径完成单项搜索预览和返回筛选、完整范围内暂停/拖进度/速度选择、长按2倍及松手回1.5倍；整理显隐、标签取消、更多/详情、主题切换恢复、顺序队列、末尾返回及最近去重。SQL核对两轮固定1/2项来源与成员/序号、完整范围结束，工具/面板未改候选或提交标签/删除；26个源SHA及七轮设备显示配置恢复相同。组件补四种视口/字号的长来源滚动与当前定位，以及真实偏好文件读回/写入失败保留旧值。

独立存量评审一轮、同清单三次追加；暗色取图等实际主题与图标颜色完成，稳定态低对比项关闭；大字结束计数和队列说明孤字项关闭。保留原始观察和全部修后材料，不外推动态结论。普通短队列83%固定高度留白、横屏640dp面板宽及工具图标仍与冻结原型不同，继续列入UI-02/05，不能以本次评审关闭代替整页一致。

[实现约束](LF8-PREVIEW-PANELS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview-panels/README.md) / [逐项台账](RESULTS.md)。本段补PRE-01/02/04、来源返回及UI-02/04/05明确组合；完整预览其它异常/后台/全屏设备手势与录屏、完整管理、500页4K/8K、目标手机/NAS及原签名升级继续。固定视口不能冒充实际旋转，小型公开视频不能冒充目标机性能。原型1cbf605独立未改，backup_v2生产能力仍关闭；MemoryCredentialStore不新增强杀/安全存储证明，未发布APK或修改正式8760/NAS/SDK。LF8/#33与总任务/#24保持开放。

## 2026-10-26：范围面板尺寸、Paper轮廓与紧凑整理条（PR #67）

[Draft PR #67](https://github.com/ShiJiJS/video_viewer/pull/67)基于#66。

按上一段实际并排的残差继续对齐冻结原型：短队列随内容收缩、长队列上限后滚动，横屏预览范围改为可用全宽；恢复圆角描边选择、当前项边界、来源/说明层级与三个工具/方框播放轮廓。快速整理恢复浅绿紧凑条、文字动作和危险文字色，普通状态标题按原型保留，大字优先完整两动作。标题“范围”和视频数量按完整短语换行；新增真实滚到底部的完整说明和固定关闭检查。

固定取证eee463a（生产与组件测试树相同），完整客户端544项、analyze、lib/test及本轮integration文件format、脚本Ruff通过。普通三轮、大字和短横屏各20点，同源码100个原生前台检查点；325份manifest输入只读复核通过，证据提交5c711d6。普通两项范围实际总高435dp（含实际系统底部），旧固定面板约700.5dp；横屏宽844dp，旧640dp限制已移除。5000项末端定位组件检查仍按48项、有界次数读取，不能替代真实设备/NAS性能。

独立存量视觉首轮与同清单复核：大字标题/来源孤字、快速整理的面积与危险填色权重两项提升已在指定视口/状态关闭，没有剩余必须修正或提升项。按冻结参考保留普通整理状态标题，记录与删减建议的取舍。原始输入、诊断、修后原图与不拉伸的并排材料一并归档；没有用静态图声称完整动效已验收。

真实服务仍核对单项搜索返回、固定1/2候选与完整成员/序号、实际暂停/拖进度/倍速与长按恢复、面板/整理显隐和最近去重；26个源SHA与五轮设备显示配置恢复一致，无标签/删除/图包操作提交。服务生产/测试树同4bf060b，本段未重跑服务测试。完整预览其它异常/全屏/后台/手势录屏、完整管理、500页4K/8K、目标手机/NAS与原签名覆盖升级继续；需用户配合部分按授权暂跳过。原型1cbf605独立可移除且未改，backup_v2生产能力仍关闭，MemoryCredentialStore不新增强杀/安全存储证明；未改正式8760/NAS/SDK或发布APK。#33/#24保持开放。

[实现约束](LF8-PREVIEW-GEOMETRY.md) / [固定源码证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview-geometry/README.md) / [逐项台账](RESULTS.md)。


## 2026-10-26：设置表单、媒体目录与真实键盘（PR #68）

[Draft PR #68](https://github.com/ShiJiJS/video_viewer/pull/68)基于#67，最终源码81b598f（生产界面同57edbc8）。连接/目录保持全高度管理页，文字输入恢复外置标签与近白输入面，类型/方向/适配使用开放设置行；保留图片适配、显式保存和原请求核对。正常完成扫描收为可展开摘要，异常仍显示详情；错误滚入可见区，极短键盘窗口允许动作随正文滚动，当前值与焦点保持可见。共享Paper短面板全宽，修正短媒体库状态区消息/重试可达。

完整客户端550项、analyze、181个Dart文件format与runner Ruff通过。普通三轮/大字/横屏105个设置点，另阅读13/预览20/最近17个短横屏回归，共155个同源码原生前台图。设置核对端口错误、真实目录类型409、草稿取消、默认值保存/重开读回/恢复；活动2成员视频范围、根记录和夹具原进度不变，阅读默认只两次写入/revision2、播放默认未写。八轮源SHA及显示配置恢复核对；阅读/最近回归产生的会话和进度按各自预期另核对。服务生产/测试树同8b68804，本段未重跑服务测试。

独立存量首轮与同清单复核，2问题/2提升均关闭：横屏连接焦点遮挡、表单还原、大字时间行首分隔点、类型冲突重复说明。原始图与不拉伸的并排、先行不稳定截图、真实溢出修正及两次QEMU自身崩溃/恢复分开归档；中断不计最终通过。主题文件IO测试改为等待真实保存/错误，相关两分支连续三轮及最终550通过，不隐藏原失败。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/LF8-SETTINGS-FORMS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/evidence/lf8-settings-forms/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-settings-forms/docs/plans/library-first/RESULTS.md)。本段补SET-01/02/04与UI-03/04/05明确组合，完整其它管理、预览/阅读异常与手势录屏、500页4K/8K、目标手机/NAS及原签名升级继续；需配合部分按授权暂跳过。原型1cbf605独立未改且可移除，backup_v2仍关闭，MemoryCredentialStore不新增强停/安全存储证明；未改正式8760/NAS/SDK或发布APK。#33/#24保持开放。


## 2026-10-26：双类型回收站、逐行恢复与待核对选择（PR #70）

[Draft PR #70](https://github.com/ShiJiJS/video_viewer/pull/70)，证据提交f5493f4。本段基于#69，最终生产及主流程固定88a45ec。视频／图包回收站统一为Paper全高度管理页：20dp正文、名称／完整路径、左侧勾选、逐行恢复和底部选择动作。短列表动作跟随内容；长列表保留可见收尾，真实IME或极短高度时随正文滚动。24项分页、图包搜索、刷新、原请求与任务入口继续保留；成功翻页回到新页开头，读取失败保持成员、偏移和选择。

原生核查修复两处实际状态问题：查询原请求成功后只释放对应26个选择，后来新选成员保留；ListView保持同一视口类型，避免键盘弹出切布局时丢失焦点。核实前显示“保留选择N／恢复结果待核对”，阻止相交内容的重叠恢复与删除；逐行确认写“恢复1个图包”，与批量选择区分。恢复确认和任务终态说明精简，真实停止结果仍保留。

47项相关客户端检查连续三轮、analyze、13个变更Dart文件格式及Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏同源码各15点，共45个原生前台检查点。每轮真实27包81张图片，跨页选26、确认取消零写、受理丢回执只GET原请求一次、再逐行恢复剩余1包；两次POST(503/202)、精确26+1成员、SQL计数、81张源SHA、首包进度／偏好／标签、完整当前视频范围及设备显示恢复单列核对。

独立存量评审沿冻结2问题/1提升复核页签锚线与通栏细线、未知选择语义、单项确认及终态减字，三视口可见项已静态闭合。另同生产补横屏unknown页尾1图，确认保留选择／核对说明／禁用动作完整；补轮原生只提交一次26恢复、零原GET，源SHA与视频响应保持。原始基线首阶段通过但旧runner误启动第二阶段，整体失败；旧选择问题、键盘焦点及惰性列表脚本等待失败另归诊断，不计最终成功点。

[实现与边界](LF8-TRASH-MANAGEMENT.md) / [原图、固定源码及只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-trash-management/README.md)。本段补DEL-04/06与UI-03/04/05明确组合，完整永久删除复核／部分失败、备份／任务管理、其它预览／阅读异常与手势、500页4K/8K、目标手机/NAS及原签名升级继续。MemoryCredentialStore不新增安全存储或真实强停证明；冻结原型1cbf605独立未改且可移除，backup_v2仍关闭，未发布APK或改正式8760/NAS/SDK。#33/#24保持开放。


## 2026-10-27：备份与操作任务（PR #71）

[Draft PR #71](https://github.com/ShiJiJS/video_viewer/pull/71)补BAK-01/02/03、UI-03/04/05的明确组合：Paper备份／短长恢复预览／任务列表及详情，37项相关检查三轮、三视口63点，原请求、源SHA与完整恢复／快照独立核对。生产e10bbbc，archive等待脚本30bc9d7；证据b9ccf92及521份manifest输入已复核。

[逐项结果](RESULTS.md)和[原始证据／边界](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-backup-task-management/README.md)保留失败、中间版本及静态未覆盖组合。整体验收继续开放；下一段推进永久删除复核与部分失败，其它大文件／故障／系统选择器、手势、性能和需配合部分仍按台账推进。原型独立未改且可移除，backup_v2生产仍关闭，未发布APK。


## 2026-10-27：永久删除复核、完整清单与部分失败（PR #72）

[Draft PR #72](https://github.com/ShiJiJS/video_viewer/pull/72) 基于#71，最终源码35a29d4，证据提交adeb1e2及527份manifest输入已逐字节复核。视频采用短底部前置勾选确认，图包保留精确图片清单／摘要／有效期和附件保留；保存选择、图包／图片清单及结果改为完整Paper管理页，20dp正文、52／72dp页头、单一正文滚动、真实分页和原请求／原任务重试。成功翻页归位，失败保页并揭示错误，完成空态移除零项页控。

90项相关客户端检查连续三轮、analyze、11个变更Dart文件格式与Ruff通过；未重跑客户端或服务端全集。普通／双倍字号／短横屏各12点，同源码36个原生前台点。每轮108份真实源文件，取消／保存重开零物理提交；两次准备503/202、一次删除503、一次原任务重试202。相同task/plan逐项结果与SHA核对，最终差集恰为清单3张图片，其余105份SHA不变，27份附件保留、目录retained。视频原生仅取消确认；勾选分发与代次变化由组件边界检查，不外推真实视频源删除。

独立存量首轮冻结1问题／1提升，三视口36张最终PNG均已亲看，原1问题／1提升在可见范围闭合；静态图不认证动效／手势与行为。初次暗色图捕到主题与嵌套文字过渡中间帧，最终等待过渡结束并检查三个实际按钮文字／背景对比≥4.5，未更换主题色板。失败脚本定位、busy无限加载、长清单揭示距离和Demo队列测试诊断单列保留，不计最终成功点。

[实现与边界](LF8-PURGE-MANAGEMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-purge-management/README.md)。本段补DEL-05与UI-03/04/05明确组合，不关闭整体验收。更多批次／断电、备份大文件／故障／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机/NAS与原签名覆盖升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760/NAS/SDK。#24/#33保持开放。

## 2026-10-27：两套标签目录、定义编辑与交集结果（PR #73）

[Draft PR #73](https://github.com/ShiJiJS/video_viewer/pull/73)基于#72，证据提交[d710b33](https://github.com/ShiJiJS/video_viewer/commit/d710b33)，生产客户端固定4e905aa；普通完整脚本2cde25c、大字核心4e905aa、横屏核心c7e9799，结果专项补充79de2d9，完整生产字节一致。标签目录沿用Paper开放行、20dp正文锚线与描边选择，视频／图包继续独立。新建／改名复用外置字段、类型范围和明确动作；同名错误只留在表单。移除在同一面板独立确认，取消保留未保存草稿；写入中防重复及关闭，连接身份变化禁止旧ID写入。

46项相关客户端检查连续三轮、analyze、6个Dart文件格式与Ruff通过；未重跑客户端或服务端全集。生产字节相同的普通完整15点、大字核心13+结果专项2点、短横屏核心13+结果专项2点，共45个有效原生前台点。结果补充各自使用独立夹具，不冒称同一次全流程；旧弱门槛结果图不计。真实图包同名409保草稿、创建201、原ID改名保关联与移除取消／确认、视频61项跨50分页503／重试均核对。结果页另注入503并实际点击重试，核对唯一视频ID、total=1及两个标签条件，未以页面标题代替加载成功。四次UI定义写尝试、61视频定义／3关联、81图片SHA、27视频路径／大小／SHA和完整播放响应分别核对；前置准备写入不称只读。

独立存量评审沿冻结唯一提升将双层确认收敛为单层，浅暗编辑与普通完整15图／大字和横屏各新增2图复核；13核心图沿已亲看且字节未变的结论，不称再次重跑；静态图不认证完整动效／手势。原14点弱结果门槛、夹具遗漏代次头、短视口惰性定位与QEMU退出／同AVD恢复均单列，不计最终成功点。真实视频UI定义CRUD、批量追加／完整范围等其它TAG组合继续，不以共享组件分发代替完整业务验收。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/LF8-TAG-MANAGEMENT.md) / [固定源码、原图与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-tag-management/docs/plans/library-first/evidence/lf8-tag-management/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，不关闭整体验收；更多备份故障／大文件／系统选择器、预览／阅读其它异常与手势、500页4K/8K、目标手机／NAS及原签名升级继续，需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS／SDK。#24/#33保持开放。


## 2026-10-27：视频／图包标签分配与批量追加（PR #74）

[Draft PR #74](https://github.com/ShiJiJS/video_viewer/pull/74)基于#73，生产客户端固定94c7292，最终原生脚本94c7292。标签分配统一Paper面板、21dp标题及20dp正文；视频／图包分别读取、创建与关联标签。单项保存替换整项标签，跨页批量仅追加，即使最后只剩一个目标也保留原标签。搜索与新建字段分离；创建／关联错误保留草稿，分页与名称核对沿原协议；提交中阻止重复、返回和拖动关闭，连接／恢复变化拒绝旧回调。小目录去除重复已选区，新建与添加同行；短横屏字段并排，系统字号保持。短横屏只在所选标签不在当前候选中时显示独立已选区，避免重复挤占首行。覆盖媒体库的弹层自行避让IME，背景保持原视口及读取错误，修复74dp剩余窗口中的29dp溢出。

48项相关客户端检查连续三轮、另31项共享导航／设置／面板检查、analyze及Ruff通过；Linux隔离服务10项标签／名称／全范围选择契约检查通过，未重跑客户端或服务全集。普通／双倍字号／短横屏同生产与最终脚本各14点，共42个原生前台点，包含两类单项替换、新建同名409保草稿、真实IME、保存返回实际来源模型读回，以及跨24项分页全选27再排除1项的批量追加。请求ID、单项其余26项未变、批量精确26成员、最终每类53条关联、两套命名空间、81图片SHA及显示配置恢复分别核对。

独立复核沿冻结1问题／1提升检查最终42图，可见范围内低高度操作截断与面板体量均闭合；静态图不外推动效或完整手势。截图保持状态并由宿主完成采集后确认，初始等待真实候选、保存等待来源模型读回；旧错位、加载中、未刷新图和失败轮单列诊断。普通使用默认Android渲染，大字／短横屏用测试专用Skia以绕过QEMU默认渲染崩溃，未修改应用或SDK默认，不冒称三组默认渲染全部通过。

[实现与边界](LF8-TAG-ASSIGNMENT.md) / [原图、固定源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-tag-assignment/README.md)。本段补TAG-01/02与UI-01/04/05明确组合，#24/#33及整体验收保持开放。真实视频定义CRUD的完整UI组合、更多备份故障／大文件／系统选择器、预览／阅读异常与手势、500页4K/8K、目标手机／NAS与原签名升级继续；需配合部分按授权暂跳过。冻结原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未发布APK或改正式8760／NAS。

## 2026-10-27：原型可移除构建演练与当前整合回归（PR #75）

[Draft PR #75](https://github.com/ShiJiJS/video_viewer/pull/75)基于#74，固定源码7c70e59。将整个Git提交导出到新建副本，仅移除副本内72份`design/reference/`文件，12,145份保留文件与固定提交全部blob独立逐字节核对；App package root实际指向副本，Git discovery上界避免借用父仓库。构建后保留源码与原仓库参考文件SHA均未变，副本参考目录保持不存在。冻结原型树1cbf605在原仓库独立保留。

同一副本Flutter analyze、完整643项客户端测试、debug/release APK构建、服务镜像Ruff check和完整Linux pytest 447项通过；初次pub解析离线且强制锁文件，构建使用标准Flutter模式注册。两包Flutter资产清单不含原型路径，Flutter引擎仅ARM64，JNI依赖另含armeabi-v7a/x86_64；release DEX无integration_test插件路径。APK仅本机构建，沿现有开发签名、未递增版本，不作为原签名升级包。服务格式检查仍有27份存量文件失败，单列保留，未误报全部门禁通过。

首轮debug后错误复用`--no-pub`使release残留测试插件注册而失败，`complete:false`与原始日志保留；同副本标准release通过只作诊断，修正脚本后按7c70e59重新完整跑第二轮。未修改SDK或移除开发测试依赖。输出安全检查拒绝仓库根目录、整个.dev及已有目录；实际只删除一次性导出副本。

[实施与边界](LF8-REFERENCE-ISOLATION.md) / [固定源码、原始日志与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-reference-isolation/README.md)。此段证明实际移除参考目录后的构建/测试隔离，服务用例覆盖大于32MiB HTTP备份和500页4K/8K扫描，但不证明Android长包渲染、真机/NAS性能、系统选择器、完整手势或原签名覆盖升级。#24/#33及整体验收保持开放；需用户配合项按授权暂跳过。原型树独立未改，backup_v2生产仍关闭，未发布APK或修改正式8760/NAS。

## 2026-10-27：图包瞬断重试与500页/大图阅读（PR #76）

[Draft PR #76](https://github.com/ShiJiJS/video_viewer/pull/76)基于#75。真实大图响应头前连接关闭暴露自动恢复缺口，生产固定f8631ae：SocketException/HttpException沿现有400/800ms、最多两次自动重试；持续失败仍可手动重试/跳过，失败不记进度，离页取消定时器。布局、服务业务、SDK和冻结原型均未改。新增3项回归在修复前两项失败、修后通过；12项相关与完整646项客户端测试、analyze/格式/Ruff通过。服务447项全集仍归属#75，本段未重跑。

最终驱动/采集固定df9d80c，生产与组件测试字节同f8631ae。同一API36 ARM64专用AVD、软件GPU/headless、390×844/DPR3/字号1、App无渲染覆盖，连续三轮均从媒体库进入500页，经730次实际拖动覆盖所有页；末页横纵切换、固定4包范围、三次4K/6K/8K实际解码往返、返回媒体库再续读及纵向偏好，均核对实际可见帧、HTTP与只读SQL。共39个前台点、6段原生录屏（全帧解码通过），源SHA相同，显示基线恢复。宿主GPU退出139、长扫描准备、旧图像传输失败及驱动/采样就绪问题分别留档，不拼为成功。

元数据峰值120、provider 6项/估算24.4MiB、Flutter缓存约26.8MiB/待解码4；全部采样与检查点PSS最高480.8/631.4/462.9MiB。不同指标不互作上限，debug驱动节奏及高压缩纯色合成图不代表真实照片、SMB或目标手机/NAS性能。第一轮一次已处理离屏长包预读HttpException保留；没有原生当前大图故障注入，自动恢复/重试上限由组件检查证明。标准ARM64 release编译成功，资产无原型路径且release DEX无integration_test；仅本机构建、开发签名和原版本，不发布或冒称原签名升级。

[实施与边界](LF8-READER-LONG-PACK.md) / [固定源码、原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-reader-long-pack/README.md)。本段补READ-01..06、PKG-03与UI-02的明确组合，未据此关闭整项。目标手机/NAS峰值与30次p50/p95、其它方向/缩放/大字/手势及异常、系统选择器和原签名覆盖升级继续；需配合部分按授权暂跳过。原型树1cbf605独立未改且可移除，backup_v2生产仍关闭，未改正式8760/NAS。#24/#33保持开放。

## 2026-10-27：当前视频预览的全屏/后台原生链路（PR #77）

[Draft PR #77](https://github.com/ShiJiJS/video_viewer/pull/77)基于#76，最终驱动/采集98507ea。生产App、组件测试及服务业务树与605badb相同；新增当前媒体库→二级预览→实际全屏/系统操作的演练，修正采集器录屏回收失败后仍应恢复设备并清理精确自建容器的问题，原型元数据可空。

独立8768的公开三视频变体（第三项复用公开横屏字节，普通原型场景仍2项）、4包/24PNG，API36 ARM64专用AVD、software GPU/headless、关闭宿主HardwareDecoder、App无渲染覆盖。固定98507ea连续三轮行为通过：45个前台截图/焦点/内存点、21次1600逻辑px/s fling、6次实际Home往返、12段旋转分段录屏（全帧解码通过）。同一控制器/暂停位置跨真实旋转保持；1.5倍/临时2倍、左右原生亮度/音量、后台释放与前台暂停、系统返回先退全屏、当前±1共3控制器/仅当前playing且volume>0、真实设置关闭准备后1控制器及离页释放，分别分别核对实际UI暂停意图、可见VideoPlayer与原生值。两轮固定3成员/序号、最近3实际视频、27源SHA和显示/音量恢复经请求、API与只读SQL核对。

15项相关客户端检查、App/最终驱动analyze、变更Dart格式和Python Ruff通过；完整646/447分别保留#76/#75源码归属，本段未重跑全集或构建release。早期随机默认/当前锚点假设、队列异步挂载、显示控件时重复切换的驱动失败、历史成功、QEMU实际139退出/恢复均分开留档，不计最终三轮。关闭宿主视频解码是本地启动条件，未改SDK；成功不证明旧宿主解码路径崩溃根因。

**实际画面仍有未解决问题：**关闭宿主解码后的横屏右侧绿边已与源帧和相同生产树的宿主解码原图对照，登记[渲染/稳定性 #78](https://github.com/ShiJiJS/video_viewer/issues/78)。根因尚未证明，不能以行为通过或录屏可解码判定UI-02画面完整性通过；保留原图继续定位，不裁边或换素材掩盖。

[实施范围](LF8-PREVIEW-LIFECYCLE.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview-lifecycle/README.md)。本段补PRE-04/05、NAV-02及UI-02的明确行为组合；实际三个小视频不证明重叠初始化/迟到回执、全部格式/来源/主题/字体或目标手机/NAS性能。MemoryCredentialStore/内存偏好与Home不新增强停/凭据/落盘证明。原型1cbf605独立未改且可移除，backup_v2生产仍关闭，未改正式8760/NAS或发布APK。#24/#33/#78保持开放，需用户配合项按授权暂跳过。


## 2026-10-27：本地视频画面与开发启动配置（PR #79）

[Draft PR #79](https://github.com/ShiJiJS/video_viewer/pull/79)已创建并附于任务。

对应#78/#33/#24，基于#77，当前完整App采集固定7740f4d。最小同源比较确认：关闭宿主解码时，Flutter textureView在Impeller/Skia均复现129列绿条；platformView与原生MediaPlayer两入口无该条。byte-buffer codec逻辑/裁切960×540、stride1024仅为独立路径数据，不证明Surface根因。选择software GPU、Vulkan关闭、GLDMA关闭、宿主解码开启的本地配置，保留产品播放器实现；实际AVC属性2、日志c2.goldfish.h264.decoder。

同源当前App连续三轮通过，共45前台点、21次fling、6次真实Home往返、12段录屏全帧解码。新增15个横屏原图的已知绿条/非黑帧检查，实际抽查每轮截图正常。阅读相邻13点通过。设置相邻两次IME超时经实际宿主截图/Window/IME确认：键盘和表单正常，旧驱动取了弹层下刻意归零的来源页insets；eb5cc46仅改integration_test从真实FlutterView读取，保留键盘/焦点/遮挡断言，最终21点通过。失败与修后源分别留存，不把两个源码说成同一采集。

启动器修复离线ADB残留阻止启动和短暂前置shell生命周期问题：真实进程判断、现有配置核对、其它AVD保留、独立session；6项CLI契约有旧失败/修后通过记录，真实启动命令结束后持续运行并成功复用。原有VS Code前置任务调用此脚本；本段实际验证脚本入口，未冒称再次点击F5。显示/字号/原生音量恢复后，专用AVD正常退出，未清userdata。

flutter analyze与变更Python Ruff通过。正常release构建、manifest/DEX诊断Activity与integration_test排除、原型页面资产排除及原证书核对通过；仍0.1.4+5，只在本地构建。Flutter应用/引擎为ARM64，依赖另携带其它ABI的libdartjni.so辅助库，不当作完整跨ABI应用。相关15项组件与646/447全集沿用既有固定业务树证明，本段未重跑全集。

[方案](LF8-VIDEO-RENDERING.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-video-rendering/README.md)。本地固定样本的画面通过不关闭完整UI-02/05、目标手机/NAS、其它格式/异常/迟到回执、完整主题字号与来源组合。短队列收高、横屏范围宽度和工具形态已由#67完成；本轮后续以当前源码/原生画面复核，转而推进标签变更与固定范围稳定性等剩余状态组合。原型树1cbf605独立未改可移除，backup_v2生产仍关闭；未改正式8760/NAS、SDK或发布APK。#24/#33/#78保持开放，需配合项按授权暂跳过。


## 2026-10-27：预览标签与固定范围、来源返回库存（PR #80）

[Draft PR #80](https://github.com/ShiJiJS/video_viewer/pull/80)已建立并关联本任务。

基于#79，最终生产/驱动固定76a2f95。当前b94754f完整预览20点确认#67已完成的队列390×435dp与工具形态，修正最新段落将旧留白/640dp差异重新当余项的过时描述，不重复改已对齐布局。

新原生链路实际从标签筛选进入，预览内保存／重开读回标签；当前项、范围身份、成员和序号不变。专用目录真实复制公开样本并扫描，已鉴权API为新增项加同一标签，旧范围不吸收；返回原筛选看到更新后的匹配项。再从新匹配结果进入固定范围，外部删除来源标签定义，旧范围仍保留；返回后保留0项而非扩库，明确清除才显示全部3项。新增项真实相邻初始化、未播放且音量0，最近API／SQL仍仅两个实际打开的旧视频；同名图包标签与原进度未改。

先行三轮的实际原图另发现返回列表已新、顶部库存仍旧。新增视频/阅读器返回、即时/延迟库存四项组件旧版全失败；最终两个来源页返回时独立刷新权威库存，不阻塞列表/锚点恢复、不由筛选数推算库存。4新增与21相关共25项、analyze/Ruff通过。修后同76a2f95三轮42原生点、阅读相邻13点通过；返回图等真实库存3及新封面解码，429项证据只读复核通过。

原先26个源文件SHA不变，唯一新增文件为固定路径公开flower-landscape副本，SHA和scanner真实ID单列；不是伪称前后文件完全相同。三轮各两个固定范围的成员/序号/游标、精确标签写入／定义删除、返回结果与历史由API/SQL分别核对。源控制入口错误键403且只在专用场景标志下启用，生产服务无此测试入口。早期采集上下文／嵌套滚动错误、先行未核对库存的三轮与组件中间失败均保留，不计修后成功。

[实施边界](LF8-PREVIEW-STATE-STABILITY.md) / [原图、请求、SQL、源码与只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview-state-stability/README.md)。本段补PRE-03及LIB-03/NAV-02/REC-01明确组合；阅读器返回同类修正有组件和相邻原生证明，不冒称新增图包的NAS场景。没有新视觉方向或布局变更，旧#67视觉评审保留源码边界，本段未重做独立视觉评审。未重复全集或release构建、未发布APK；其它格式/异常与目标手机/NAS及原签名升级继续。原型树1cbf605独立可移除未改，正式8760/NAS/SDK未改，#24/#33/#78仍开放。下一步继续视频标签定义真实改名／删除及失败读回等明确余项。

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
