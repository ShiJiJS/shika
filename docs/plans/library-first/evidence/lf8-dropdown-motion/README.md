# LF8：下拉选择源码、诊断与组件检查

对应[问题 #112](https://github.com/ShiJiJS/video_viewer/issues/112)，承接菜单草稿PR #111。生产源码及最终检查固定 `2f9792a4d25e08524856d9c1c8b0a077571109af`，生产lib树 `3fa6e5011c2cfeaef29fc1b03a68411d5565e50c`。完整765客户端、15针对及analyze通过；其中一个检查包含16组新旧完整RGBA比较。实现说明见[LF8-DROPDOWN-MOTION.md](../../LF8-DROPDOWN-MOTION.md)。当前没有新增Android运行或普通包，不能当作真实系统/服务/手机验收。

`before-probe.dart.txt`为实际DefaultSettingsSheet/PaperControlTheme的完整旧版诊断，使用既有DefaultDraftLibrary读取替身。`before-probe.log`保留三项预期失败：普通和减少动画300/300，运行中系统组件标记true后仍0.2。`before-invocation.json`另记最初工作目录/保留变量错误；没有启动测试，不计产品失败。

`initial-targeted.log`保留适配过程的一次编译失败：Dart的私有初始化形参采用公开调用名，修正后对应15项阅读/默认设置相关检查在 `initial-targeted-2.log` 通过。最终源码完整针对检查见 `dropdown-tests-5.log`。前四份日志分别保留：已释放路由的测试查询错误、两次未观察到键盘滚动进行中的尝试，以及请求未挂载惰性条目的错误。最终焦点滚动用公开Focus请求已挂载项，先确认滚动进行中，再确认系统组件标记启用后完成目标且不继续移动；不把它称为实际键盘中途切换。真实箭头/Enter跳过禁用项另有两项检查。

最终15项还覆盖选择立即且只回调一次、退出80ms实际不透明度0.5/160ms进度0、运行中进退场开启减少动画直接到位、方向开始读偏好、null选项与取消、表单验证/保存/重置/初始值、禁用/空/失效与锚点移除/旋转。16组像素覆盖普通/表单、深浅、RTL-LTR、上下位置，包含底层按钮和菜单的完整画面；这不是全部手势/全部设备证明。既有阅读/设置检查只更新类型查找，业务断言保留。

`client-tests.log`为完整765通过，`analyze-final.log`无问题。此前分析提示/警告保留；各诊断不混称最终源码通过。`audit.json`固定源码、lib树、实际9处入口、SDK下拉源码SHA、原型树，以及原四服务同ID健康和code15配套包完整SHA。生产服务未改，本段未重跑服务端全集，不读取/写入任何业务数据库；未操作NAS或真实收藏。

`manifest.json`列出本目录除自身外全部文件SHA；`log-provenance.json`保留原始/发布SHA及临时VM连接URL脱敏计数。没有数据库、APK、密钥或私有连接配置。既有菜单15输入和原生149输入证据保持独立冻结，原型树1cbf605独立可移除。

后续：真实Android触摸/返回、实际系统设置与绘制帧；再纳入新配套普通安装包核对相关业务。现有preview.9/rollback.9同code15不含菜单及下拉修复。其它UI-06/手势、目标手机/NAS/有声/云文件和#78/#89/#100原因继续开放。
