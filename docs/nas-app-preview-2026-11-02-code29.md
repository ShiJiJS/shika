# 第29版 App 已交付

2026-11-02，修复用户反馈的图包阅读与快速整理问题，见 [PR #176](https://github.com/ShiJiJS/shika/pull/176) 和 [五张工单及验证说明](plans/library-first/PACK-READER-EXPERIENCE-FIXES.md)。

NAS：`SATA存储11/docker/video-viewer/packages/`。安装正常包 `video-viewer-0.2.0-preview.23-arm64.apk`，直接覆盖现有 App，不要卸载或清除数据。需要旧视频界面时可覆盖安装同号 `video-viewer-0.1.4-rollback.23-arm64.apk`。原服务地址、口令保持；NAS 服务仍为 preview.8，本次没有重启或改动服务、媒体及数据库。

快速整理的阅读方式在本次整理期间保持一致，可从底部“阅读方式”或更多菜单调整。移除在后台处理，仅记逻辑回收；顶部提示两秒后或切换内容时清除。未确认结果从“移除记录”查询，已完成操作在服务允许的期限内可撤销。

安装包固定源码：`6e827ecd875655253299a45170d94c23c6b19dc1`。两包 Android 内部版本29，原Windows签名证书 SHA256 `f5abd3bd11d94b3aaee66ab65e6a666a228a4d64edf4b86de9327ae9b8a59161`。

| 安装包 | 字节 | SHA256 |
| --- | ---: | --- |
| video-viewer-0.2.0-preview.23-arm64.apk | 23308182 | `c76e261d19dc6edd3fd73543d899c611cfb2f8e72b9d1028ad12b6327d8ab3c4` |
| video-viewer-0.1.4-rollback.23-arm64.apk | 21734394 | `ea632b820fd2654ae66844608392f8bbefa8f6741a9863fe769e07e628b42596` |

两包均为普通 main 入口、ARM64 release，已校验包名、版本、签名、无 integration_test 插件和原型资产；NAS 回读摘要一致。完整客户端851项、针对性客户端71项、Flutter analyze、Linux隔离容器服务相关35项均通过。另完成构建副本的阅读偏好/连接/操作日志兼容检查及旧界面回退检查。

本次未连接实体手机，未对真实收藏进行删除试验。第28版及更早的45项验收记录仍按各自版本保留，不自动算作本次全部验收。总体持续开发目标仍暂停，此次只完成 #171–#175。
