# Preview.4/code10：正常签名包与配套回退

本轮边界、已知风险判断和实现/正式验收区分见[交付结果](../../LF8-PREVIEW4.md)，安装文件/服务版本/SHA见[安装说明](../../../../library-first-preview.md)。不重复长进度正文。

- 固定正常源码f0ee0504，两包原Windows证书、正常main、ARM64 release，无integration插件/原型资产；`build/result.json`与双方签名、badging、analyze及检查日志。回退85、现代相关14、受影响行为17通过；复用已有687/三轮48，不重新跑全集/500页。
- `native/upgrade-result.json`和三次install/package/startup/catalog/preferences：同AVD未卸载清数据，新9→新10→旧10→新10；21表/设置/登录/偏好完整比较。
- `native/path-result.json`、`native/screens/`、`native/trace/`：真实普通APK横纵第2张、3→2、续读返回、两套标签、设置、实际视频与横屏返回。无声host GPU/宿主解码配置，不等于手机有声/性能/长期稳定。
- `delivery-audit.json`：扫描时间变化在旧9启动前就已存在；路径/身份相同，重建安装前完整设置摘要严格相等。主动阅读播放后的13表保留，8表与三项活动设置变更分别列出。`scan-difference.json`仅含非秘密扫描/根记录及设置摘要，没有口令/token。
- `stop-cleanup.json`：恢复进入时设备参数，关闭专用资源，原服务/donor文件保留。恢复阶段未重建APK或重开模拟器。
- `logs/`及对应原始助手脚本保留中间失败：ADB未root/短暂无UI根、旧诊断地址8773需在旧9建立8772基线、标题与按钮同名、全屏已播放隐藏控件却错误期待播放按钮、审计错误跨启动基线，以及host SQLite/docker tmpfs前置读取问题。名称含paused/playing的中间截图不单独计为状态证明；最终verify-fullscreen-actual-playing两图与语义独立核对。首进全屏系统教育有单独截图和实际Got it点击。

`finish-audit.py`为本轮私有目录记录的只读复核脚本来源，要求对应私有停机数据库，先确认没有运行容器绑定及非空WAL。首次恢复只读打开产生零字节WAL/SHM，使最初“任何侧文件都禁止”的前置失败；最终immutable只读且拒绝非空WAL，payload SHA未变。脚本不是生产命令，不应对真实收藏直接运行。公开目录不携带SQLite、签名密钥或安装包。截图为公开视频/合成图包原始画面，未裁边、挪动或重绘。
