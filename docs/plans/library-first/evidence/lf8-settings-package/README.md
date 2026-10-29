# preview.9 / rollback.9 普通包证据

2026-10-30，构建源码 `21de58d3a31e0f9135a191490c701e91825e2d37`。两包同code15、正常main/ARM64、原Windows签名，无集成插件或原型资源，文件在项目tmp/releases。完整说明见[设置段](../../LF8-SETTINGS-MOTION.md)与[安装说明](../../../../library-first-preview.md)。

- `build-1/result.json`：签名、包名/版本、SHA、字节数、全部步骤退出码及隔离导出记录；`*-source-files.json`为固定源码文件哈希，rollback覆盖适配器另有明确来源。旧界面85项、新界面相关14项及双方analyze通过；普通APK不入Git。
- `same-production-tree.json`、`package-audit.json`：普通包与c6c1695f生产lib同树；复用[前段740客户端与24次原生/12录屏](../lf8-settings-motion/README.md)，不称整合版全量重跑，也不将普通截图当计时数据。
- `normal/*-install.json`与各次包信息：同一AVD新14→新15→旧15→新15，3次install-r成功，首次安装时间、身份/dataDir/appId保持。前后21张表、登录/设置摘要及完整本机偏好逐次相同；读取SQL仅在拥有该副本的容器内mode=ro事务完成，未在Mac打开活跃绑定数据库。
- `normal/settings-result.json`与原始文件/UI读回：实际深浅色、相邻准备各普通/减少动画一次，共4次保存；两次真实force-stop后启动，持久化文件与界面都正确，最终完整偏好恢复原值。原初值为暗色开/相邻关，不假定默认值。
- `normal/screens/tag-draft-*.xml/png`：真实标签草稿在切换Android减少动画后保留未保存选择，取消返回媒体库。全部21表及认证/设置仍同；`normal/trace/requests.jsonl`在本段偏好/草稿范围内仅GET/HEAD，无服务写入。
- `normal-upgrade-initial.log`、`normal/initial-permission-failure/`：初次读取安装前偏好时ADB为shell而权限不足，发生在任何安装之前；包信息、启动记录、SQL基线与失败日志保留。首次同名着陆截图在再次采集时被替换，不据后截图说明首次失败时画面。`debug-access.json`记录自有调试AVD临时root读取，模拟器PID11650未变，无清数据、模拟器重启或产品改动；此后完整覆盖检查一次完成。
- `scan-baseline.json`只读核对inactive donor为18项任务，新副本安装前19项且新增项为扫描；比较基线取旧14启动之后。`normal/runtime.json`记录独立命名/标签、只读媒体挂载及donor SHA。donor未挂载，复制前后均核对无活跃绑定，未在主机打开SQLite。
- `package-cleanup.json`：偏好已恢复，系统配置与临时ADB读取权限回到进入状态，专用AVD关闭、专用容器移除；原四服务完整ID/健康、donor文件SHA保留，所有本地证据/数据/旧code14两包留存。真实NAS/收藏未访问或升级。

`package-audit.py`独立按原始JSON、UI XML、实际APK哈希与Git树核对，未只依赖结果布尔值。`previous-apks.json`复核code14两包未覆写。完整产品/其它控件与手势、#78/#89/#100原因、真实手机/NAS/有声/云文件及正式发布仍开放。

本目录不含APK、数据库、密码文件、密钥或设备boot/发现日志。构建和脚本中的本机路径是历史执行上下文；日志临时本机VM地址如有则脱敏，原/发布SHA见`log-provenance.json`。`manifest.json`覆盖除自身外全部文件，可独立复核。
