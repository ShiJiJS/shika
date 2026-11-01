## 2026-10-27：视频画面与启动环境（PR #79）

[Draft PR #79](https://github.com/ShiJiJS/video_viewer/pull/79)基于#77。同源最小对照在Impeller/Skia纹理软解路径均复现129列绿条，原生MediaPlayer两入口及platform view无该条；buffer crop/stride另存，不据此断言Surface根因。保留产品播放器实现，选择software GPU、Vulkan关闭、GLDMA关闭、宿主解码开启；实际AVC属性2、c2.goldfish.h264.decoder。

7740f4d当前App连续三轮通过：45前台点、21次fling、6次Home往返、15个横屏原图已知绿条/非黑帧检查、12段录屏全帧解码。阅读13点通过；设置旧驱动两次取了弹层下被刻意归零的来源页insets，宿主实际键盘原图/Window/IME保留，eb5cc46仅改驱动读真实FlutterView，保留IME/焦点/遮挡断言后21点通过。启动器的离线残留与短暂shell生命周期问题有6项CLI旧失败/修后检查及真实启动、复用证据。

flutter analyze/Ruff、正常release构建、manifest/DEX诊断与integration_test排除、原型页面资产排除及原证书核对通过；仍0.1.4+5，只本地构建。原型1cbf605独立未改可移除，未改正式8760/NAS、SDK或发布APK；全集沿用既有固定业务树证明。本地固定样本通过不关闭完整UI-02/05、其它格式/异常/迟到回执及目标手机/NAS；#24/#33/#78继续开放，此处误列的短队列/横屏范围与工具形态已由#67完成；[PR #80](https://github.com/ShiJiJS/video_viewer/pull/80)更正台账并补预览状态/返回库存，不改变本条渲染复现与未定根因。

[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-rendering/docs/plans/library-first/LF8-VIDEO-RENDERING.md) / [444项原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-video-rendering/docs/plans/library-first/evidence/lf8-video-rendering/README.md)。

## #77 原始复现与排查清单

关联 #24 / #33 / #77。当前预览手势与生命周期的本地演练发现显示异常，需要继续定位；UI-02保持未通过。

复现环境：Android Emulator 37.2.12、API36 ARM64、video_viewer_api_36，software GPU/headless、Vulkan关闭，并通过SDK支持的`-feature -HardwareDecoder`关闭宿主视频解码。App无Skia等渲染覆盖，未修改SDK。`CCodec`记录实际`c2.android.avc.decoder`。生产App/服务业务树与605badb相同。

从媒体库进入预览→范围面板选顺序并点第一项→横向全屏：公开H264/AAC 960×540视频右侧出现明显绿条。相同生产树、同源视频字节，在先前开启宿主视频解码的截图没有绿条；原素材也无该条。关闭宿主解码前，连续轮次另出现QEMU线程挂起并实际退出139；不能仅以切换环境后行为测试通过认定图形/解码问题已解决。

[关闭宿主解码后的原图](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-lifecycle/docs/plans/library-first/evidence/lf8-preview-lifecycle/native/normal-1/lifecycle-fullscreen-playing.png) / [原宿主解码路径对照](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-lifecycle/docs/plans/library-first/evidence/lf8-preview-lifecycle/diagnostics/before-identity-metrics-success/lifecycle-fullscreen-playing.png) / [运行条件、原始证据与限制](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-lifecycle/docs/plans/library-first/evidence/lf8-preview-lifecycle/README.md)。截图时刻不同，不作为逐像素同帧比较；绿条是实际观察，具体根因尚未证明。

继续处理：

- [ ] 用同源文件在最小原生播放器/现有video_player路径比较，读取实际codec、crop/stride及渲染方式，区分模拟器、插件与App责任；不先推定根因。
- [x] 找到能正确显示完整画面且稳定完成当前流程的本地环境，明确全部启动条件；不用裁掉绿边、改测试素材尺寸或修改SDK掩盖。
- [ ] 若证据表明需要App调整，使用受支持的接口，并复核全屏/返回、控制层/手势、只有当前发声、暂停意图和资源释放；冻结源码重新跑关键路径三轮。
- [ ] 补原图/录屏及逐项台账，真实手机/NAS与其它格式仍分别验证；不要用ffmpeg能解码录屏替代画面完整性。

需用户配合项按授权暂跳过。保持原型树1cbf605独立且可移除，不改正式8760/NAS、不发布APK，不据此关闭#24/#33。

## 2026-10-27：API36专用模拟器再次挂起退出（PR #87）

[PR #87](https://github.com/ShiJiJS/video_viewer/pull/87)中，全屏完整双进程验证后，后续普通视频准备期间QEMU报告bad color buffer handle、QEMU2 main loop及CPU线程无响应并退出；ADB消失，原显示恢复失败。软件GPU、GLDMA off、host AVC2，未改SDK或renderer。旧launcher及QEMU日志PID均确认消失；按原配置重启、先恢复原显示，普通视频与图包后续完成，不把中断轮计成功或将重新运行称无中断稳定性通过。

[原始模拟器／App／恢复失败与进程证据](https://github.com/ShiJiJS/video_viewer/tree/codex/lf8-fullscreen-restart/docs/plans/library-first/evidence/lf8-fullscreen-restart/diagnostics/emulator-exit)。根因尚未证明，不将其直接定性为App错误。本段公开视频画面检查无绿边，不关闭已有其它解码路径绿边问题。另已证明旧全屏“换片”来自测试ensureVisible误滚动，并非短片自然结束，详见本PR证据。


## 2026-10-28：复杂图片场景的模拟器退出补证（PR #96）

新增独立profile入口，计划每类30次Flutter缓存冷首图、正常相邻翻页、连续拖过500页、内核PSS/RSS/VmHWM和帧时序；静态检查通过，原型独立。前三次采集错误（异步tester保护、控制消息分块协议、Tooltip类型）分别修正/留档，不算产品故障。随后SWANGLE/GLES在8次4K重复后bad color buffer/GL context异常、QEMU81429挂起并离开进程表；内核PSS采样最大196416KiB、RSS高水位297432KiB，不能据此诊断App OOM。只在确认进程消失后换官方CLI支持的SwiftShader复测；另一次进度确认等待超时，正在加完整状态诊断，尚未归因。所有失败均不算成功轮次，不用8次样本冒充30次分位数。

[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/LF8-READER-PERFORMANCE.md)／[当前诊断记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/evidence/lf8-reader-performance/README.md)。完整30次、三轮500页、普通release入口与目标手机/NAS仍待完成；#78/#89与#24/#33保持开放。指定SMB目录在Mac可读，目前只确认路径可达；未把它当成真实图包已验收，未扫描/修改真实收藏或NAS服务。

## 2026-10-28：完整摄影长包后，正式轮再次退出

311d2c86已实际完整走过500页并保留第500页横纵切换，但不据此关闭环境稳定性。81a11a98正式轮在4K30次与8K第0次后QEMU90728消失；同PID宿主报告的触发栈位于CrashReporter.GenerateDumpAndDie/HangDetector，SIGSEGV记录不是App OOM的证明。ADB与清理均失败，缺少终态原始报告，不拼凑正式分位数。退出前可采PSS220.118MiB、VmHWM317.117MiB，仅是已有观察值。

选择性退出字段/符号栈、原系统报告SHA、原采样和同配置重启记录见[正式轮失败证据](https://github.com/ShiJiJS/video_viewer/tree/codex/lf8-reader-performance/docs/plans/library-first/evidence/lf8-reader-performance/diagnostics/final-1-qemu-exit)。确认旧进程消失后才复用原AVD数据启动87970，未升级SDK或wipe data；启动日志实际GLES仍为SWANGLE/ANGLE→SwiftShader。当前SDK37.2.12列于[官方稳定版说明](https://developer.android.com/studio/releases/emulator)，不是一次SDK修复验证。相同完整矩阵继续，#78的原视频画面与其它环境问题均未关闭。
