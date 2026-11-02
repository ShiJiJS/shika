# LF8：通知时长、系统偏好与图包撤销提示退出

继续PR #106后的既有UI-06通知缺项，不改变产品范围。原通知默认250ms，减少动画和打开后切换设置也未直接响应。统一正常进入/退出160ms；减少动画在首个绘制前完成进入、退出时长0。所有8个生产调用文件统一使用PaperSnackBar，原文字、边距、动作、duration及ScaffoldMessenger队列/关闭原因保留。

共用组件借用公开withAnimation传入的控制器，不替换或销毁它。为避免0时长返回同时触发下一条入场时与框架旧timeout清理顺序冲突，共享前向时长保留160ms，减少动画的入口直接到目标；排队入口在同步清理后的microtask完成，早于下一次绘制。MediaQuery依赖只更新未来反向时长，监听随组件释放；不改accessibleNavigation，不自动延长撤销期限或重发命令。

另外，当前框架的SnackBar带操作按钮默认persist=true，实际showPackUndo会超过设定时长仍留着。此处明确persist=false，使图包撤销提示按原duration退出；不改服务端期限、实际撤销动作或其它恢复提示的常驻默认。

验证：修正后的原框架8种时长组合全部失败，改后8种通过；补两条队列/设置切换和真实showPackUndo到期无命令，共11项通过，完整706与analyze通过。早期测试夹具缺少Paper浮动主题，以及中间全0控制器导致框架队列timeout断言的失败分开保留，不称原产品已有该队列断言。该中间问题已由队列回归关闭。

## 本段结果

[草稿PR #107](https://github.com/ShiJiJS/video_viewer/pull/107)；冻结源码 `7299c6d2c396af111a683e3fe3778f9678856c3e`；[原始证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-notice-motion/README.md)区分生产组件 profile 与普通 release。

- 原生三轮共24次进退场、12段完整解码录屏通过。实际Android系统比例、PlatformDispatcher与MediaQuery一致；正常160ms有真实透明度中间值，减少动画首个观测帧到目标。通知完全打开后切换相反设置，再分别关闭或触发测试撤销；六次测试回调不冒充真实文件命令。
- 普通preview.6/rollback.6均原Windows签名、正常main入口、ARM64 release、同内部号12。新11→新12→旧12→新12三次覆盖检查通过；21张业务表、登录摘要、设置摘要、完整外观偏好和安装身份逐次相同，无卸载/清数据。
- 普通新版实际操作私有可丢弃的 `Upgrade Pack`：确认整包移除、看到提示、约3.30秒后点击撤销，服务在8秒期限内完成，卡片恢复。只有两条实际POST，均受理成功；两个完成任务、图包generation从3增至5是预期变化。其余19张业务表、图包其它字段、标签/页/阅读进度/偏好与认证摘要相同。设置中的active-opened清除和last-delete记录通过精确重建原摘要核清。源目录只读绑定，保存操作后SHA；不声称有本段操作前独立SHA快照。
- 最初普通操作核对脚本错误要求generation及设置不变，还误把逻辑操作任务当作file_operations新增；两次核对失败保留。后续只读取既有记录核清，不重放删除/撤销，不把核对脚本错误称App故障。
- 两套自有模拟器、专用容器均已关闭；进入时系统设置、原四服务及donor文件SHA恢复/保留。正常code11旧包未覆写；原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 与服务生产树未改。

目标手机/NAS、有声、通知在动画中途切换的全部组合、按压/选择与完整UI-06仍不据此关闭，#78/#89/#100根因未定位。NAS已只读确认旧服务健康、ARM64架构及真实图包目录，升级方案待明确授权，尚未部署或写收藏。实现完成与整体验收分开，总票#24/#33保持开放。
