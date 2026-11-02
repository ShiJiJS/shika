# 第31版 App 已交付

2026-11-02，统一处理[#179](https://github.com/ShiJiJS/video_viewer/issues/179)、[#180](https://github.com/ShiJiJS/video_viewer/issues/180)、[#181](https://github.com/ShiJiJS/video_viewer/issues/181)、[#182](https://github.com/ShiJiJS/video_viewer/issues/182)。[根因、行为与测试范围](plans/library-first/PACK-CLEANUP-FEEDBACK.md)。

NAS：`SATA存储11/docker/video-viewer/packages/`。正常包 `video-viewer-0.2.0-preview.25-arm64.apk`，直接覆盖安装，不要卸载或清数据；同号旧界面回退包 `video-viewer-0.1.4-rollback.25-arm64.apk`。原签名、包名、地址和口令保持。服务仍为preview.8，本次无服务重启、数据库迁移或实际收藏文件操作。

- 切换前后图包不再与后台列表读取互相取消，重复点击只启动一次导航；旧响应不改新位置。
- 回收按钮扩大到80dp，去掉“正在移入回收站”，顶部提供两秒撤销提示，沉浸时同样可操作；最后一项可在末尾页撤销或返回。
- 回收立即更新显示数量与当前位置，撤销/明确失败时恢复，回执不重复扣减，不重建原阅读范围。
- 媒体库搜索旁增加多选入口，长按封面也可选择，支持跨页和全选、批量移入回收站；确认显示数量，只提交选中项，未知结果查询原请求。源文件保持，可在回收站恢复。

固定安装包源码 `718edbb48fcb564efe098d4c00f71b58fbcc8f55`，Android内部版本31，原Windows签名证书SHA256 `f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161`。

| 安装包 | 字节 | SHA256 |
| --- | ---: | --- |
| video-viewer-0.2.0-preview.25-arm64.apk | 23373714 | `c5b823e6be18f89c0a824427e2acdcb7c45ca521e8bfb37924ab5683fc27f7cf` |
| video-viewer-0.1.4-rollback.25-arm64.apk | 21734394 | `c139c8b8a7d0cdd9f2937d976caa1b18b0a731994100b2d116b46c708b5b1160` |

两包均为普通main入口、ARM64 release，无integration_test插件和原型资产；NAS摘要与本地一致。图包相关308项测试和Flutter analyze通过，包含修前两项失败的真实HTTP并发复现、显式取消和过期结果、重复点击、即时计数和撤销、批量回收、全删为空及未知回执。另完成构建副本连接/偏好/日志兼容检查及旧界面回退检查。

本次没有重新运行整个客户端测试套件或进行实体手机试用。45项历史验收仍按原版本保留，其他持续目标仍暂停。临时导出、测试过程文件和旧本地APK交付后清理，工具链、签名、最新包及配套镜像保留。
