# Preview.3：构建完成，实际安装验证进行中

冻结构建源码 `4dd88cac0cd137e2ecc7486408d9b912081ff7e8`，基于复杂图片三轮证据提交58431bfa，整合PR #98的视频减少动画修复（本分支d667950c），App版本提升到0.2.0-preview.3+9。原型树仍为1cbf605，独立目录不进入APK；服务生产代码和镜像未改，未重跑无关服务全集。

整合版客户端676项通过。隔离导出的旧界面85项、正常新版构建前14项检查及两包完整analyze通过；14项包含在客户端全集范围中，不累加成独立功能数量。离线pub get严格锁定，锁文件只允许依赖角色不同，版本/来源/校验和保持；每份原锁SHA另存。正常release入口、原包名/Windows证书、内部版本号9、单ARM64引擎、无integration_test原生插件和原型资源均由构建器核对。result.json记录13步全部退出0，相关日志和源文件SHA清单原样保留。

| 本机产物（位于tmp/releases） | 内部版本号 | 字节数 | SHA256 |
| --- | --- | --- | --- |
| video-viewer-0.2.0-preview.3-arm64.apk | 9 | 23308398 | 7b4d911e88b999c8e3e5b913e0cad90f01cdd1a1812b3bd87866e8060de7b690 |
| video-viewer-0.1.4-rollback.3-arm64.apk | 9 | 21734390 | 4b52bda8b8399978d31ab2268d60e41af79852771d78f53b05580916fd55d051 |

两包证书SHA256均为 `f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161`。构建后重新读取两份新产物SHA，与result相同；原code8新/旧两包也重新核对，与PR #95的最终build-4记录相同。APK二进制仅在本机，不提交Git或发布Release。

接下来在自有AVD实际验证code8→新版9→旧界面9→新版9，检查免口令启动、设置/两套标签/阅读位置与任务保留；正常release的大图阅读另行验证。当前只有构建和组件证据，provenance.json明确normal_apk_install_validation_complete=false，不把“构建完成”称为覆盖安装/目标手机通过。真实手机/NAS仍待验，当前指定SMB挂载不可用，按用户授权暂跳过。#24/#33/#78/#89及原型整体验收继续开放。
