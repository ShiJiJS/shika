# LF5 原生阅读主路径：同实现连续三轮

实现为 `278a774` + `91f1112`，三轮均在 **91f1112** 源码上执行，无中途App/服务实现修改。API36专用Android模拟器 + 8761隔离FastAPI/SQLite服务，真实鉴权HTTP和实际图片首帧。每轮重置专用夹具，正式8760和真实NAS未改。

| 顺序 | 逻辑尺寸/字号 | 结果 | 原始记录 |
| --- | --- | --- | --- |
| 1 | 360×740 / 2倍 | 完整路径通过，31秒 | [日志](01-large/android-test.log)、[宿主事件](01-large/host-events.json)、[源码/APK/产物哈希](01-large/proof.json) |
| 2 | 390×844 / 普通 | 完整路径通过，30秒 | [日志](02-normal/android-test.log)、[宿主事件](02-normal/host-events.json)、[源码/APK/产物哈希](02-normal/proof.json) |
| 3 | 390×844 / 普通 | 完整路径通过，32秒 | [日志](03-normal/android-test.log)、[宿主事件](03-normal/host-events.json)、[源码/APK/产物哈希](03-normal/proof.json) |

以上为测试执行时间，不含Docker准备、编译和安装。源码哈希覆盖客户端lib/test/integration_test与服务端业务/迁移/测试/runner；各轮tracked_changes仅为当时正在整理的Markdown记录，没有运行源码变化。三轮归档后重新逐文件核对当前源码和全部产物哈希一致。日志仅移除行尾空白，原始日志哈希另存；PNG为ADB原始尺寸，未裁剪或修图。

## 真实执行路径

27包，每包3张公开花卉图片，文件自然顺序1/2/10；列表首批24项。卡片封面实际解码后点击，创建完整27包固定范围；当前图片实际显示才opened，最近从0变1。翻到第二张，切纵拼并实际拖动，保存非零页内比例，退出后独立GET读回pageId/比例。重开确认同页/比例/纵拼；总览3张缩略图真实解码，点第三页后等待当前首帧，再flush并独立读回落盘pageId。手动下一包保持原session ID和27包范围，新包以自己的默认模式实际打开；最终返回图包列表。

独立核对最近仅含这两个实际打开的包，预加载未产生其他历史；总创建会话2次、opened3次（第一包首次及续读各一次、第二包一次）。请求记录不包含鉴权头或请求体；业务值通过集成测试断言和独立读回核对。

每轮六张截图及同阶段请求记录：

- [横翻](02-normal/reader-horizontal.png) / [纵拼](02-normal/reader-vertical.png) / [重开续读](02-normal/reader-reopen.png)
- [总览当前页](02-normal/reader-overview.png) / [同范围下一包](02-normal/reader-next.png) / [返回媒体库](02-normal/reader-return.png)
- [双倍字号横翻](01-large/reader-horizontal.png) / [双倍字号总览](01-large/reader-overview.png)

## 视觉复核与边界

按已批准Paper/P2和oil-ui-pro存量界面评审规范，首轮390独立看图复核未发现阻断视觉缺陷，提出模式图形差异、总览当前页标识、实际范围名和冗余副信息四项局部调整。本次已落实；主任务又查看本目录最终普通/放大字号截图，核对52dp普通顶栏、大字号自然增高、图标上对齐及两字换行、当前页和真实范围文案。Android字体曾出现0.4px溢出，已用自然行高修正并通过以上三轮；未压缩字体来避错。参见[界面约束](../../LF5-UI-DESIGN.md)。

截图不独立证明网络时序或性能。当前路径覆盖横翻按钮、纵拼、保存/续读、总览跳页、手动下一包和返回；左右滑动/缩放/宽适配/沉浸/整包标签改变固定成员、故障与未知保存、后台/连接/恢复、来源组合等仍需专项原生检查。844×390横屏目前只有客户端实际资源widget路径，没有原生截图或动作录屏。公开图片240×360，不能证明500页4K/8K真实解码、峰值PSS、翻页延迟或NAS/真机表现。以上是91f1112检查点；最近图包列表其后已接线，见[最近来源三轮](../lf5-native-recent/README.md)。LF5不因三轮主路径通过而关闭；LF6快删、LF7完整设置/备份v2和LF8整体验收继续保留。

复跑：`bash scripts/dev.sh python3 scripts/run-client-connection-test.py --pack-reader`；放大轮增加 `--workspace-viewport 360 --workspace-text-scale 2`。只能作用专用8761容器和既定AVD。

## 最近接线后的原阅读器回归

`d8e3082`上额外完整复跑一次普通字号主路径，通过，执行33秒。该轮在最近来源三轮之后运行，验证原媒体库入口、首帧、翻页、纵拼比例保存、关闭/续读、总览跳页落盘、同固定范围换包和返回仍正常。见[日志](04-recents-regression/android-test.log)、[宿主事件](04-recents-regression/host-events.json)、[源码/APK/产物哈希](04-recents-regression/proof.json)。六阶段截图与请求按同一命名归档。该当前版本回归只有一轮，不冒称上述旧版本三轮也在d8e3082重跑。
