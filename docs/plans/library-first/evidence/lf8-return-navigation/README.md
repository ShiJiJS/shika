# 返回旧页的组件复现与源码修复

跟踪[#140](https://github.com/ShiJiJS/video_viewer/issues/140)，[实现与边界](../../LF8-RETURN-NAVIGATION.md)。

- before.log：旧生产代码12d6ca67，五类管理页按系统返回均暴露nav-browse，旧服务对照通过。
- related.log：修后同一防旧入口检查及现有四入口/预览退出共20项通过。
- analyze.log：客户端分析通过。
- client-full.log：修后完整客户端检查，结果以原始终端记录为准。

测试中的设置列表会保留滚动位置，最终验证设置标题与旧入口不存在，不要求已经滚出构建窗口的行仍被构建。使用Demo仓库与播放器替身，只证明列明的交互；Android正常包、手势/预测返回、实际服务/连接和目标手机仍待验证。NAS及已交付包未改，issue保持开放。
