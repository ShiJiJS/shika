# 按压、选择与快速点击反馈

结果与边界见[本段说明](../../LF8-CONTROL-FEEDBACK.md)，安装包见[安装说明](../../../../library-first-preview.md)。source-map.json和same-production-tree-final.json区分普通包、原生观察及预检源码。

- before-tests.log：原框架8项失败；LEGACY_CONTROLS仅让同一夹具使用原标准控件。quick-before.log：新色层在快速点击/键盘确认的普通模式2项失败、减少动画2项通过；修复后quick-after.log的19项通过，其中一个测试逐像素比较16组静态状态。client-tests-final.log完整725项通过，analyze-delivery.log无问题。原型/服务生产树未改。
- native-4：920581e3的三轮36次按住/单选/多选进退场与18录屏完整解码，preflight-audit.json对应这组。native-1/2/3分别保留输入前取样、定时按住结束、post-frame tester调用冲突的失败；最终host-runner使用明确DOWN/UP，采样只遍历挂载Element。36项是预检源码，不冒称全部在code14重做。
- native-6：最终生产lib与普通code14相同，三轮6次真实快速点击、6录屏完整解码。每次一次业务回调；普通确认后有可见100ms色层，减少动画确认后首个观测帧已移除。按下/确认以回调计数分开，所有观察帧保留。native-5首轮失败后未保留未通过分组的帧，无法从原数据确定原因；当前修正取样语义并保留observations，后续通过不把原失败计入成功，也不声称原原因已经定位。
- build-2/normal是code13预检，保留其完整覆盖安装与阅读/草稿取消结果，未作为交付候选。build-3/normal-final是最终preview.8/rollback.8、同code14：新13→新14→旧14→新14，21表/登录/设置/偏好/安装身份逐次相同；正常/减少动画下三次标签草稿切换后取消，回媒体库，21表和登录/设置摘要仍同，期间没有写请求。普通窗口图不替代profile计时。
- 预检正常流程错误要求退出阅读的request_records不变，原断言保留；audit-controls.py只读核清同页opened及版本/最近时间更新，无命令重放。像素夹具初次错误等待引擎IO、测试查找不识别新子类、控制器100ms边界回调在下一调度帧发生等记录均保留，不冒称原产品故障。初次构建缺ANDROID_HOME后改用dev.sh，新目录重建，未覆盖旧包。
- cleanup-native/normal-cleanup是预检归还；cleanup-native-final/normal-final-cleanup是最终归还。具体PID/容器、进入时设置、原四服务健康与donor SHA均核对。fixture源目录只读，真实收藏/NAS未动。原始日志仅去除临时本地VM URL，原文/公开文SHA及数量在log-provenance.json；不公开含ADB身份的emulator.log，也不含数据库、APK、凭据或NAS私有路径。夹具脚本只保留来源，不是对真实收藏执行操作的说明。

本段实现和列出的检查完成；完整UI-06其它控件/手势、真实手机/NAS、有声与云文件、#78/#89/#100仍开放。帧/录屏不证明物理呈现延迟或持续稳定性。
