# LF8：真实 Android 菜单与运行中减少动画

源码固定 `30b350eeaabc958466c3b6540b66c063bce8f54a`，生产 lib 树与已通过完整750客户端的 `1b924ceaadb2db94e5600fb0634fcf106880d9e1` 相同。对应 [问题 #110](https://github.com/ShiJiJS/video_viewer/issues/110)、[草稿 PR #111](https://github.com/ShiJiJS/video_viewer/pull/111)。本目录与原[源码/组件证据](../lf8-menu-motion/README.md)分开冻结；不重写原证据。

生产 PaperMenuButton 的独立 profile 入口，在自有 Android 36 ARM64 模拟器、host GPU、无声配置执行三轮。原生触摸/返回与 Settings.Global 设置由主机执行，App 同时记录真实 PlatformDispatcher 和 MediaQuery，无 FakeAccessibilityFeatures 注入。图标/文字按钮、普通/减少动画、取消/选择及进入/退出中切换均覆盖：72次方向过渡、36次打开、12次选择、24次取消；24段录屏全部完整解码。进入240ms/退出160ms的控制器和实际菜单 Opacity/Align/最后条目输入逐帧记录，不能把录像采样当作物理触屏延迟。

其中12次在过渡尚未完成时开启系统减少动画：前一个原生标记为false的帧仍严格在0与1之间，第一个true帧已经处于目标进度和不透明度。固定Flutter3.47.7的Android桥监听transition_animation_scale，因此先写该值，再写animator和window，全部读回核对；40ms仅是输入至开始写设置的主机观察间隔，不当作实际生效时间。完整原始帧及12条首次标记对照见 `native-1/profile-result.json`、`native-live-proof.json`，设置动作/读回见 `native-1/events.json`，本机SDK定位见 `android-flag-source.json`。

首轮运行即完整通过。初次分析只有缺少控制块花括号的提示，修正后分析无问题；两份日志均保留。flutter-drive中保留启动跳帧和Android返回分发警告，不据此关闭视频/音频/持续稳定等其它问题。`audit-native.py`独立核对72个明确用例名、实际帧、回调计数、24段解码回执、配置恢复、profile SHA、生产lib相同、原型树和既有code15两包SHA。

`cleanup-native.json`确认进入时的窗口/密度/字体/三项动画设置原样恢复，只关闭自有QEMU38130；原四个服务同ID健康，既有两包和原型未改。没有启动媒体服务或执行媒体/文件命令。profile APK只在本地留存，本目录发布其SHA与构建/执行命令，不包含APK、数据库、密钥或完整启动日志；临时VM连接URL按 `log-provenance.json` 脱敏，其余输入逐文件SHA列于 `manifest.json`。

复现时应先读主机运行器的所有权/端口/源码断言，按项目 `scripts/dev.sh` 构建 `integration_test/menu_motion_test.dart`，创建全新证据目录，不能覆盖这次记录。独立审计/清理脚本有本次固定PID/路径，属于执行记录，不应直接对新环境运行。`native-1/contact-round1.png`为首段录像每秒6帧的接触表，全部原始MP4/静态PNG另存。

这证明生产菜单组件在本机原生系统偏好下的行为，**不是普通main安装包或真实业务菜单操作的验收**。现有preview.9/rollback.9同code15不含菜单修复；后续需新配套普通包和受影响业务路径核对。完整UI-06、其它控件/手势、目标手机/NAS/有声/云文件以及#78/#89/#100原因继续开放。
