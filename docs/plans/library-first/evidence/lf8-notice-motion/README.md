# 通知、减少动画与真实整包撤销：7299c6d2

结果和范围见[本段说明](../../LF8-NOTICE-MOTION.md)，普通安装包见[安装说明](../../../../library-first-preview.md)。

- before-valid-tests.log与对应执行源码：原框架8组合全失败。最初缺少浮动主题的无效夹具、一次替换未生效、中间全0时长触发框架队列断言均分别保留。notice-tests-final.log的11项及client-tests.log的706项通过；analyze-clean.log与analyze-native-final.log无问题。undo-deadline-before.log保留原真实showPackUndo因persist默认值而不退出的失败。
- native-1/profile-result.json：三轮24次通知进退场，实际系统偏好、借用控制器与真实FadeTransition透明度记录。12录屏由run.py完整解码；audit.json与cleanup-native.json记录检查及原配置归还。独立生产组件入口，测试撤销回调6次，不连接媒体服务、不称实际文件操作或普通release帧时间。
- build-1/result.json冻结正常preview.6与rollback.6源码、SHA、原签名及code12。normal/upgrade-result.json记录新11→新12→旧12→新12；每个窗口21表、设置/登录摘要、外观与安装身份保留。
- normal/actual-undo-result.json及actual-undo-settings-result.json：普通main App实际确认→撤销、两次POST和完成任务、目录只读、卡片恢复及进度/标签保留。normal-undo.log与normal-undo-audit-initial.log保留错误核对断言；audit-undo.py只审计既有记录，audit-settings.py仅在确认无活跃绑定/WAL后以ro+immutable读私有副本，精确核清预期设置变化，不重复执行命令。源SHA仅操作后观测，未冒充本段前后对比。
- normal-cleanup.json核对独占PID/容器、原四服务与donor SHA。原始日志只移除临时本地VM URL，原文/公开文SHA及数量见log-provenance.json；emulator.log不公开以免携带ADB公钥。目录没有数据库、APK、个人NAS路径或凭据。夹具脚本保留其来源，不作为真实收藏操作说明。

普通模拟器无声运行，不能替代目标手机/NAS、有声、完整手势及物理呈现延迟验收；UI-06剩余按压/选择与开放问题仍保留。
