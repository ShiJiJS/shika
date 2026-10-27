## 2026-10-27：视频画面与启动环境（PR #79）

[Draft PR #79](https://github.com/ShiJiJS/video_viewer/pull/79)基于#77。同源最小对照在Impeller/Skia纹理软解路径均复现129列绿条，原生MediaPlayer两入口及platform view无该条；buffer crop/stride另存，不据此断言Surface根因。保留产品播放器实现，选择software GPU、Vulkan关闭、GLDMA关闭、宿主解码开启；实际AVC属性2、c2.goldfish.h264.decoder。

7740f4d当前App连续三轮通过：45前台点、21次fling、6次Home往返、15个横屏原图已知绿条/非黑帧检查、12段录屏全帧解码。阅读13点通过；设置旧驱动两次取了弹层下被刻意归零的来源页insets，宿主实际键盘原图/Window/IME保留，eb5cc46仅改驱动读真实FlutterView，保留IME/焦点/遮挡断言后21点通过。启动器的离线残留与短暂shell生命周期问题有6项CLI旧失败/修后检查及真实启动、复用证据。

flutter analyze/Ruff、正常release构建、manifest/DEX诊断与integration_test排除、原型页面资产排除及原证书核对通过；仍0.1.4+5，只本地构建。原型1cbf605独立未改可移除，未改正式8760/NAS、SDK或发布APK；全集沿用既有固定业务树证明。本地固定样本通过不关闭完整UI-02/05、其它格式/异常/迟到回执及目标手机/NAS；#24/#33/#78继续开放，接续短队列留白与横屏面板比例等已登记原型差异。

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
