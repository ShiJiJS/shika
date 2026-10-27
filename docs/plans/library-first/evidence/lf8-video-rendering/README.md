# LF8：本地视频开发配置与画面回归

关联 [#78](https://github.com/ShiJiJS/video_viewer/issues/78)、#33/#24，基于 #77。实现范围见 [方案](../../LF8-VIDEO-RENDERING.md)。本段保留原型与产品播放器实现，选择可实际运行的模拟器配置并修复启动器；不修改 Flutter SDK，不遮盖绿条、不更换素材尺寸。冻结原型树仍为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`，独立且可移除。

同源公开 flower-landscape.mp4，SHA256 `d097d4403a6bad16f8243f341599d233d3c3c7c4bc4ece7afece0b4657e01001`，H264/AAC 960×540。软件 GPU、Vulkan 关闭、宿主视频解码关闭时，最小 Flutter textureView 在默认 Impeller 与 Skia 均有 129 列平绿条；platformView 与原生 MediaPlayer 的 SurfaceView/TextureView 无该条。原生 byte-buffer MediaCodec 为 c2.android.avc.decoder，逻辑/裁切 960×540、Y stride1024。这条 buffer 路径与 Surface 输出不同，不能独自证明纹理实现的具体根因。最初诊断曾过早捕获黑色原生 Surface；最终诊断等待实际 rendering-start、seek 和横屏布局，黑帧不计成功，早期失败保留本机 .dev。

候选配置为 software GPU、Vulkan 关闭、GLDMA 关闭、宿主 HardwareDecoder 开启；最小两 Flutter 入口均正常。当前 App 三轮采集源码固定 `7740f4d`，启动器显式配置上述功能，实际 AVC boot 属性为 2，日志观察到 c2.goldfish.h264.decoder。两组结果是路径对照，不把更换模拟器配置写成产品软件解码缺陷已根治，也不把录屏可解码代替截图检查。

启动器以真实同端口进程判定启动/复用，离线 ADB 残留不再阻止新启动；其它 AVD 或已运行配置不匹配时保留并报错。另一次真实启动曾返回 ready 后 QEMU 消失，不能确认其退出原因；改用独立 session 并验证命令结束后的真实进程、ADB 和再次复用。6 项隔离假 SDK 契约含两次旧版各 5 通过/1 失败与修后 6 通过；模拟契约不代替真实 AVD。

当前完整链路的每轮 15 个保持前台点覆盖媒体库进入、暂停/进度/1.5倍、实际旋转全屏、窗口亮度/媒体音量、临时2倍、两次实际 Home 往返及重建暂停恢复、系统返回、六次预加载切片与一次单播放器切片、离页释放和最近记录。每轮另检查 5 个横屏原图无已知平绿条且有足够非黑图像内容。像素扫描只针对固定公开素材中的已知异常；实际查看原图，不宣称它完成全部视觉验收。录屏按实际旋转分段，段间可能有缺口。12段以 `-fps_mode passthrough -enc_time_base demux` 保留输入时间基全帧解码。首次用默认输出时间基的 null 检查产生重复DTS错误，原始输出单列 checks/recording-initial-output-timebase.log，不把该错误称为素材损坏或删除记录。

每轮 3 视频/4 图包/24PNG，共27源文件，前后SHA相同；第三视频仅是公开横屏字节副本，不代表三种视频格式。固定候选/序号与游标经 API 和只读 SQL 核对。只用独立127.0.0.1:8768夹具，正式8760/NAS未改。MemoryCredentialStore、内存偏好和Home不增加安全存储、强停或偏好落盘证明。播放器瞬时状态可能处于缓冲；暂停意图下禁止播放，播放请求不强求每个瞬间原生isPlaying为true。

源范围、原始截图/窗口/内存、请求、实际手势、数据库投影与录屏在 native；最小隔离在 diagnostics；启动器旧失败、修后及真实启动在 checks。15项相关组件检查与646/447全集仍沿用#77/#76/#75固定业务树证明，本段不重复全集。新增诊断Activity仅src/debug且固定公开asset/夹具键/模拟器守卫；release构建和APK排除检查另存checks，未发布或装到手机，版本/原签名策略不变。

本地固定样本通过不关闭完整 UI-02 或整个 LF8：目标手机/NAS、其它格式、迟到回执/重叠初始化、完整主题/字号/来源组合及剩余原型差异继续。#24/#33/#78 保持开放。需配合项按授权暂跳过。

只读复核（不访问服务或操作设备）：

```sh
python3 docs/plans/library-first/evidence/lf8-video-rendering/verify.py
```


设置相邻检查两次在“real root IME”超时，不能计通过。第二次宿主实际截图和Window/IME原文确认键盘已显示、字段及保存按钮在键盘上方；产品home.dart刻意把被弹层覆盖的来源页viewInsets归零，旧驱动从app-shell读取了这个来源页。eb5cc46仅修integration_test驱动，从真实FlutterView构造设备MediaQuery，同时保留实际IME大于0、收起归零、输入框焦点与位于键盘上方的断言及采集。当前预览三轮和阅读相邻仍为7740f4d；设置最终轮单列eb5cc46，复核要求两源码唯一差异就是该驱动文件，其余运行文件一致。两次失败与宿主观察单列diagnostics，生产App未为测试改变。

最终三轮当前预览均通过，45前台点/21次fling/6次真实Home往返/15个横屏原图门禁；12段录屏全帧解码无错误。相邻阅读13点、修正取值后的设置21点均通过。当前flutter analyze无问题；正常release构建成功，manifest/DEX无诊断Activity与integration_test插件，无原型页面资产。主Flutter应用与引擎为ARM64；APK同时包含依赖携带的armeabi-v7a/x86_64 libdartjni.so辅助库，不将这些当作完整跨ABI客户端。证书与原版一致，仍0.1.4+5，仅本地构建未发布。
