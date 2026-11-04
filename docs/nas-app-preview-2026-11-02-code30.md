# 第30版 App 已交付

2026-11-02，按用户截图精简图包快速整理，修复 [#177](https://github.com/ShiJiJS/shika/issues/177)。[调整与测试范围](plans/library-first/QUICK-READER-IMMERSIVE.md)。

NAS目录：`SATA存储11/docker/video-viewer/packages/`。正常包 `video-viewer-0.2.0-preview.24-arm64.apk`，直接覆盖原App，不要卸载或清除数据。同号旧视频界面回退包为 `video-viewer-0.1.4-rollback.24-arm64.apk`。原Windows签名、包名、服务地址和口令保持；NAS服务仍为preview.8，本次没有重启服务或操作实际媒体及数据库。

快速整理不再显示图片滑杆、阅读方式行、标签/回收站大按钮。右下角保留小回收站悬浮按钮；单击图片隐藏/显示上下栏，单指上滑后进入沉浸，双指缩放和横向翻页不触发上滑隐藏。后台移除后进入下一个图包仍保持沉浸；底部范围导航只在栏显示时出现，阅读方式在更多菜单调整。普通阅读操作区保持。

构建固定源码 `5d6e35ecc3ed6067d24b24f37c0bf14d6fa6286d`，Android内部版本30，原签名证书SHA256 `f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161`。

| 安装包 | 字节 | SHA256 |
| --- | ---: | --- |
| video-viewer-0.2.0-preview.24-arm64.apk | 23373714 | `d048317423a7759052a5ec3866358e836fdf8305c9f4acce3d6a711072d404de` |
| video-viewer-0.1.4-rollback.24-arm64.apk | 21734394 | `0f31aa9baa8a63c0ed870a1b7b876dec0d4347801c4a303fab5a836d09d7dc97` |

两包为普通main入口、ARM64 release，已核验不含integration_test插件和参考原型。NAS摘要与本地一致。Flutter analyze及集中44项阅读、快速整理、缩放与异步回收相关检查通过；另完成构建副本的连接/偏好/日志兼容检查及旧界面回退检查。

此次未重跑第29版的851项整版测试，未连接实体手机试用，不将累计测试数或模拟触摸视为实体手机体验结论。临时导出、测试过程文件及旧本地APK在交付后清理；工具链、签名、最新安装包及配套镜像保留。总体持续目标和其他验收仍暂停。
