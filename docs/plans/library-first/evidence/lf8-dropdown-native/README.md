# LF8：真实 Android 下拉选择与运行中减少动画

源码固定 `6f4f5e004756697fbbd6328d956ca87ef03c76e2`，生产 lib 树与已通过完整765客户端的 `2f9792a4d25e08524856d9c1c8b0a077571109af` 相同。对应[问题 #112](https://github.com/ShiJiJS/video_viewer/issues/112)、[草稿 PR #113](https://github.com/ShiJiJS/video_viewer/pull/113)。本目录与[源码/组件记录](../lf8-dropdown-motion/README.md)分开冻结，不重写原20输入记录。

生产PaperDropdownButton和PaperDropdownButtonFormField的独立profile入口，在自有Android36 ARM64模拟器、host GPU、无声配置执行三轮。主机发送真实触摸/返回并写入Android全局设置；App读取PlatformDispatcher和MediaQuery，未注入系统标记。两种形式、普通/减少动画、选择/取消、进入/退出中启用偏好，共72次方向过渡，36次打开、12次选择更新、36次路由返回与24次取消结果。下拉没有业务取消回调：24是实际返回后未出现选择更新的结果，不能称24次业务回调。普通退出还核对选择或返回观察回执已发生，而实际透明度仍处于中间值，防止菜单提前移除。

12次确实在过渡尚未完成时开启减少动画，含6次进入/6次退出。前一个原生标记false的帧严格0<route_value<1，第一个true帧的实际菜单透明度和route_value均已到目标。普通情况记录中间帧，初始减少动画的首个菜单构建/确认返回帧直接到目标；菜单末项FadeTransition也在进入终点到1。进度/透明度是公开Route和实际FadeTransition的绘制输入，未读取私有CustomPainter的展开参数，也不把帧时间称为物理触屏或屏幕呈现延迟。

固定Flutter3.47.7的Android桥监听transition_animation_scale；运行器先写它，再写animator/window，全部读回。输入后的40ms只是主机观察间隔，不称为实际生效时间。`native-1/profile-result.json`保留72项全部帧及操作前帧；`native-live-proof.json`另列12条首次原生标记对照。动作及设置读回见 `native-1/events.json`，桥源码定位及SHA见 `android-flag-source.json`。

首个原生执行即全部通过；初次分析有一个花括号提示，修正后分析无问题，日志均保留。驱动中的启动/Android返回分发警告原样保留，不据此关闭视频/音频/持续稳定等其它问题。24段MP4通过ffprobe帧数与ffmpeg全片解码；首轮表单普通录屏的每秒4帧接触表为 `native-1/contact-round1.png`。独立 `audit-native.py` 核对72个明确名称、普通60/实时12、原始帧、每次入口至退出的选择更新/路由返回差量、24解码回执、恢复设置、APK SHA/生产lib相同、原型和现有code15两包SHA。

`cleanup-native.json`确认窗口/密度/字体/三项动画设置原样恢复，仅关闭自有QEMU53426；原四服务同ID健康，现有两包和原型保持。没有启动媒体服务、访问数据库或执行媒体/文件业务命令。profile APK在本地保留，本目录只有其SHA及构建/执行记录；不发布APK、数据库、密钥或完整启动日志。临时VM连接URL按 `log-provenance.json` 脱敏，其余文件SHA列于 `manifest.json`。

复现应先读运行器的所有权/端口/源码断言，用项目 `scripts/dev.sh` 构建 `integration_test/dropdown_motion_test.dart`，创建新证据目录。主机运行器、独立审计和清理脚本均含本次路径/PID约定，属于执行记录；不能覆盖本目录或直接对另一环境运行。

本段是本机原生系统下的生产下拉模块证明，**不是普通main或真实服务业务验收**。实际菜单/表单的数据来源和业务请求仍需随新配套普通包核对；现有preview.9/rollback.9同code15不含菜单及下拉修复。其余UI-06/手势、目标手机/NAS/有声/云文件和#78/#89/#100原因继续开放。
