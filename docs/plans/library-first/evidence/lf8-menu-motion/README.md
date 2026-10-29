# 弹出菜单源码与组件检查

基线 `10f7c13b1c076388be57c90b9d9d5bb251dcd848`，修复源码 `1b924ceaadb2db94e5600fb0634fcf106880d9e1`，2026-10-30。范围与待验条件见[菜单段](../../LF8-MENU-MOTION.md)。

- `before-probe.log`：3项实际VideoViewerApp+内存Workspace夹具失败，分别为普通/减少动画300/300和运行中开启后仍0.2；第4项是独立公开SDK夹具，配置240/160仍得到240/240。完整实际执行夹具为`before-probe.dart.txt`，当时放在apps/mobile/test运行；该诊断文件不留在正常测试集，不把SDK夹具算业务原生验收。
- `source-context.json`：固定Flutter3.47.7、framework revision、Dart版本与菜单源码SHA。当前SDK路由未读取reverseDuration；项目SDK未修改或更新。
- `after-initial.log`和`analyze-initial.log`：初始直接混入WidgetsBindingObserver与预测返回签名冲突，编译失败；之后以独立观察器转发事件。`after-2.log`为3项初步通过，不冒充完整检查。
- `menu-tests.log`：9通过/1失败，失败为测试把160ms可见终点与Route.completed清理同帧等同。`menu-tests-2.log`：10项通过，严格核对160ms时animation绘制输入为0，再取下一ticker样本核对清理；选择回调在退出前已执行一次。失败日志保留，不将下一帧称为物理屏幕延迟。
- 10项包括实际Workspace、进入/退出中切换、普通/减少动画选择立即回调、Tab/Enter跳过禁用项、Escape取消、移除锚点并调整窗口、空/禁用菜单，以及一个测试中的16组静态完整RGBA与原SDK菜单比较。像素由真实测试引擎toImage读取，逐字节比较，包含深浅/RTL/LTR/上下锚点/文字或图标按钮；没有使用全图容差。
- `client-tests.log`：完整750客户端通过；`analyze-final.log`清洁。所有检查为同一生产树，随后仅增加文档/证据。`before-invocation-root.log`是第一次误从根目录执行Flutter的启动失败，没有执行用例，不计App失败或测试通过。
- `audit.json`核对源码、750/10日志终态、固定SDK源SHA与原型树、已有code15两包实际SHA未变。原型仍为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`，源码无原型依赖。

本段尚无真实Android输入/帧、普通新APK或手机验收。FakeAccessibilityFeatures是组件夹具，不冒称真实Android系统偏好；窗口调整也不冒称真实手机旋转。没有启动模拟器或新服务，没有访问NAS/真实媒体，preview.9两包不含新菜单。其它控件/手势及完整产品验收继续开放。

`log-provenance.json`保留日志原/发布SHA和临时本机VM地址脱敏数量，其他输入原样复制；`manifest.json`覆盖除自身外全部文件。本目录无APK、数据库或凭据。
