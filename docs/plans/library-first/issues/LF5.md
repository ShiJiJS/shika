总任务：#24

## 目标

图包需要按漫画阅读方式浏览，管理单位始终是整包。原型的横翻/纵向/总览/沉浸、包间范围和逐包进度必须落实到真实图片和原生生命周期。

本任务属于 LF-2026-10-23 媒体库/图包改造，沿用独立冻结原型。`cb02a67`已接入固定完整范围、逐包进度/偏好、实际opened后的最近、只读回执与schema0009；完整162项服务端测试/Ruff通过。`04f57a8` / `f43a320`接入连接与恢复代次绑定的类型化客户端接口及发布归属检查。

`278a774` / `91f1112`现已接入真实原生PackReadingSession和阅读路由：卡片进入横翻/纵向拼接、方向/缩放/适配/间距、分页总览和跳页、沉浸、整包标签、固定范围内手动换包、保存/关闭后续读、返回原媒体库。实际当前图片首帧才记打开；预加载不记历史，元数据/图片provider有界，未知写结果先查回执。Paper最小52dp顶栏自然适应大字号，工具图标上对齐且避免中文孤字。

当前完整 **197项客户端测试、Flutter analyze和163项服务端测试/Ruff通过**。最近图包已按冻结原型接入纵向历史行；查询来源和排序贯穿列表、分页、全选、定位及阅读入口，与媒体库筛选互不污染。进度页码按当前清单的稳定pageId位置计算；分页边界返回先补足尾页，再恢复原视口锚点。见[最近实现及检查](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-recent-catalog/README.md)。

`d8e3082`上最近来源Android/8761完整路径连续三轮通过（390普通字号两次、360双倍字号一次）：实际新包首帧、跨24项分页、完整28包全选、末包续读、历史重排后的固定范围和原位返回、媒体库筛选保留。27条预置历史不算本轮实际阅读，见[最近原生证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-recent/README.md)。此前`91f1112`阅读器主路径三轮证据独立保留于[阅读原生记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-reader/README.md)，不混称为当前版本三轮。当前`d8e3082`在最近三轮后另跑一轮原阅读器完整回归通过（33秒），同目录保留独立日志与截图。

`3f693be` / `9024f88`进一步修正单指翻页被缩放组件截获、较低触控阈值下双指与翻页竞争的问题。同实现Android操作专项连续三轮通过（含360双倍字号，46/49/55秒），每轮核对4次实际ADB返回；覆盖跟手回弹、LTR/RTL、双指/双击缩放、放大拖动、沉浸、宽适配续读、纵拼与下一包独立默认。原生操作专项与当前197项客户端回归见[操作记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-controls/README.md)及[组件回归](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-reader-controls-client/README.md)。

`9ca6518`补齐深色错误动作的对比度；`aafccee`恢复专项验证图片503有限重试/手动恢复、未受理进度的同键显式重试、已提交丢响应的只读回执、真实Android后台保存、整包标签移出交集后仍保留完整25包范围，以及返回原查询24条结果。同实现原生路径连续三轮通过（含360双倍字号，55/54/60秒）；当前197项客户端回归包含不推进假时钟的3尺寸生命周期保存断言；见[恢复原生记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-recovery/README.md)和[生命周期回归](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-reader-recovery-client/README.md)。服务端业务/迁移35份源码仍匹配既有163项记录，本轮新增的是隔离e2e故障夹具，未重新全量执行163项。

REC-01的回收隐藏/恢复保留状态仍需LF6联动；其它图片错误码/跳过、连接替换/同连接管理恢复/旧服务、强杀与完整状态组合、500页4K/8K的真实内存与延迟仍待补。全局默认设置界面和备份v2由LF7收口，快速整理由LF6实施。本issue继续开放，PR保持草稿。详见[设计契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5-DESIGN.md)、[界面约束](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5-UI-DESIGN.md)和[实施记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5.md) / [草稿PR #39](https://github.com/ShiJiJS/video_viewer/pull/39)。

## 依赖

LF2 (#27)、LF4 (#29)

## 实施范围

- PackReadingSession 独立于视频解码器；固定包范围在服务端创建并分页，手动上一/下一包不越界，纵向到底不自动切包。
- 实现横向翻页、左右方向、缩放/适配、纵向惰性拼接、间距、总览/页码跳转、沉浸与整包标签入口。
- 保存 pageId+页内offsetRatio+revision、每包模式/方向/间距/适配；模式切换保留图片，重开续读；默认仅用于未设置包。
- 实际阅读更新最近；删页后回退最近有效页并说明，后台/离页节流flush，旧请求不覆盖新包。
- 按显示尺寸解码、已知宽高占位、有限图片窗口与字节缓存，取消旧连接/旧包读取；缓存阈值以大图夹具和真机测定。

## 主要代码

- `apps/mobile/lib/features/packs/（新增）`
- `services/server/video_viewer/reading.py（新增）`
- `apps/mobile/lib/ui/preferences.dart`

## 完成标准

- [ ] 所有阅读方式、总览、沉浸、续读、包间范围和返回来源与原型一致。
- [ ] 图包标签始终作用整包，没有单张管理入口。
- [ ] 500页、4K/8K及快速切包测内存/延迟，无无限预解码；单页错误不锁阅读。

验收 ID：READ-01–06、NAV-02、LIB-02、REC-01、UI-02/04

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。

## 2026-10-26：失败末张与横屏错误操作（PR #56）

[Draft PR #56](https://github.com/ShiJiJS/video_viewer/pull/56) 基于 #55，固定源码 `e68f487`，证据提交 `fc97f17`。原型 advance(1) 越过末张会进入 finished；App 原来把“跳过这一张”截回失败末张，且禁用了末张“下一张”。现已接到原生现有本包末尾页，可返回末张/来源，只有明确点击下一包才切换原固定范围；失败图片没有首帧，不写opened、最近、进度或完成状态。

沉浸中到达末尾显示工具，返回动作在黑色画布用白色保持可读。真实844横屏发现17像素溢出，失败/末尾区改为短视口可滚动，保留字体和操作。五项真实HTTP 404/HTTP200非图片解码及完整阅读路由检查回放旧生产代码全部失败，修正后通过。

完整客户端456项、analyze和新夹具/脚本Ruff lint通过。客户端全集在bc3c9fb执行，lib/test树与最终源码相同，最后仅改取证滚动；服务端生产树未改，402项全集沿用#55且本段未重跑。固定源码三轮（360双倍字号37.84秒、390普通36.09秒、844横屏38.74秒）通过，18张实际前台截图、六张源PNG前后SHA、原始轨迹及独立SQL投影保存，253份manifest输入已复核。SQL证实异常包没有progress行、recent只有手动进入且真实显示首帧的正常包。旧源码成功、17像素溢出、测试等待/取证偏移等开发记录单独保留。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/LF5-IMAGE-ERROR-DESIGN.md) / [固定源码及证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/evidence/lf5-image-errors/README.md)。本段补PKG-03、READ-01/02/04/05、UI-04/05的失败末张路径，不关闭整项。其余图片错误码/连接恢复/迟到图片、500页4K/8K性能、全原型与目标手机/NAS、原签名发布仍开放；本段使用MemoryCredentialStore，不作为强杀/安全存储证明。生产backup_v2仍关闭，冻结原型树1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24继续开放。

## 2026-10-26：按实际点中的可见末张跳过（PR #57）

[Draft PR #57](https://github.com/ShiJiJS/video_viewer/pull/57) 基于 #56，固定源码 `07d1cad`，证据提交 `92f08b8`。纵向视口顶部仍在倒数第二张时，可以点击下方可见的失败末张。旧逻辑按顶部index拒绝该点击；现按所点图片进入原末尾页，不自动换包，不把失败图片记成首帧或完成进度。

新真实HTTP组件检查在旧逻辑失败，修正后与原五项图片检查共6项通过；完整客户端457项、analyze及夹具/脚本Ruff lint通过。服务端生产代码未改，402项全集沿用#55且本段未重跑。原生390×844普通字号三轮59.20/39.59/38.89秒，顶部index=1、点击图片index=2、比例约70.94%，关键点击没有先滚动对齐；进度前后完整对象相等，包含revision与更新时间，返回原失败末张、退出重开恢复原页/比例，明确下一包才推进。独立SQL仍是上一张真实图片、未完成。

另按同源码跑既有末张/损坏图片844横屏回归一次35.93秒。三轮加兼容回归共21张实际窗口截图、6张源图前后SHA、原始HTTP与SQL投影已保存；119份manifest输入独立复核通过。普通字号三轮不冒充其它视口组合或安全存储强杀验收。

[核查与修复说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/LF5-VISIBLE-PAGE-SKIP-AUDIT.md) / [固定源码与证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/evidence/lf5-visible-page-skip/README.md)。本段补READ-02/04/05与PKG-03的明确组合，不关闭整项。接下来推进整体原型对照；其它异常/连接恢复/迟到图片、500页4K/8K性能、目标手机/NAS及原签名发布仍开放。生产backup_v2仍关闭，冻结原型1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24保持开放。
