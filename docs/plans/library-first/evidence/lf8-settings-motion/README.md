# 设置开关与主题切换证据

生产与原生观察源码：`c6c1695fdc5c02f8af420fc901ce3e66f3383548`。2026-10-30。原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 不变，完整说明见[设置段](../../LF8-SETTINGS-MOTION.md)。

- `client-tests.log`：完整740客户端通过；`affected-final.log`：26项相关检查，包括一个测试中的16组开关静态像素、另一个测试中的16组标签像素。完整集覆盖相同相关测试。`analyze-final-source.log`包含原生观察入口，检查清洁。
- `theme-before.log`：原实际App/标签5项失败；`switch-before.log`及`switch-before-test.dart.txt`：原SDK开关300ms/运行中减少动画2项失败；`palette-before.log`：实际自定义背景中途跳色失败。均是修改前的专用检查，不混入最终通过。
- `toggle-initial.log`、`toggle-after.log`等保留最初取消提交及激活描边像素差异；之后加入原生pointer cancel监听、保持2px描边并复核。`toggle-fixed.log`保留编辑括号错误。`analyze-with-native.log`保留观察入口初始lint，最终已修正。
- `native-1/source.json`、`command.json`、`profile-artifact.json`明确专用profile入口、源码及APK哈希；APK不入Git。实际VideoViewerApp接内存Demo仓库，真实设置页/真实Android输入，不连接任何媒体服务，不把24次内存偏好通知当作磁盘保存或服务写入。
- `native-1/profile-result.json`：三轮24次进退场的原始帧、可见绘制输入、真实系统偏好；普通有中间值，减少动画在控件值已变更的首个观测帧到目标。开关与Navigator Element身份不变。只读Element采样，没有post-frame tester调用或伪造MediaQuery。
- `native-1/events.json`：三项Android动画比例设置/读回和真实点按；`recordings.json`：12段MP4逐段完整解码，配套前后/目标PNG与窗口前台记录。固定1170×2532、density480，不冒充手机速度、实际屏幕延迟或全部布局状态。
- 动画中途切换系统偏好、拖动中切换/取消/禁用、异步失败、草稿/焦点/滚动保留由组件检查证明，原生本轮没有覆盖这些组合。
- `launcher-attempt-1.json`/`.log`：最初漏用dev.sh，找不到AVD，没有创建设备；改用项目环境后一次测试完整通过，不称运行中App崩溃或重启。成功启动器boot日志保留在本地，不发布设备发现信息。
- `restoration.json`和`cleanup.json`：进入配置完全恢复，自有PID关闭，原四服务ID/健康保留；没有新媒体服务、数据库、源文件或NAS操作。`audit.json`按原始数据独立核对次数、帧、哈希和源码。

普通安装包仍为preview.8/rollback.8、同code14，不包含本段；本段没有生成新普通包或覆盖安装试验。`previous-apks.json`复核旧交付哈希未变。服务树/原型未改。其它UI-06、#78/#89/#100原因、真实手机/NAS/有声/云文件和正式发布继续开放。

`log-provenance.json`保留日志原SHA、发布SHA与临时本机VM服务URL脱敏数量；其余证据原样复制。`manifest.json`列出本目录除自身外的全部文件SHA，可独立复核。源码命令中的本机目录只是当轮记录，不保证跨设备直接执行。
