# Video Viewer

部署在 NAS 上的私人短视频库，配套 Android 优先的跨平台 App，用于随机浏览、标签筛选、快速清理和主动归档。

当前已初始化 Flutter Android 环境验证脚手架，并提供 [B 风格 HTML 交互原型](prototypes/p2/README.md)。真实客户端与 NAS 服务业务尚未实现。交付顺序为原型试用确认 → Flutter 客户端演示版 → 服务端 → 联调验收。

## 第一版范围

- NAS Docker 服务，个人局域网使用。
- 多媒体目录接入，保留原有目录结构，接受外部文件变化。
- 随机 / 顺序播放和缩略图列表，支持挂载目录层级选择、横竖屏、倍速与拖进度。
- 平铺多标签、批量打标和标签交集筛选。
- 快速移入回收站、撤销、恢复和确认后永久删除。
- 标签与物理归档分类分开，主动归档才移动文件。
- 管理数据持久化、备份与恢复。

图包、AI 打标、外网、多用户及离线缓存暂不进入第一版。

## 项目文档

- [P2 HTML 原型：启动、试用路径与验证记录](prototypes/p2/README.md)
- [当前 UI 设计基线](prototypes/p2/DESIGN.md)
- [Android 开发环境、模拟器和 VS Code 使用](docs/android-development.md)
- [第一版规格 Issue #1](https://github.com/ShiJiJS/video_viewer/issues/1)（ready-for-agent）
- [第一版完整规格](docs/v1-spec.md)
- [已确认需求与验收场景](docs/requirements.md)
- [领域术语](GLOSSARY.md)
- [归档分类与标签分离的决策](docs/adr/0001-separate-archive-category-from-tags.md)

## 验证方向

在 VS Code 打开仓库根目录，选择 **Video Viewer (Android)** 并按 **F5**。启动前任务会准备模拟器，随后启动 Flutter 调试。具体配置和命令见 Android 开发文档。

在模拟器中验收完整 App 流程；服务端公开 API 集成测试补充验证文件操作及异常恢复。NAS 和真实 Android 设备在后续验证实际媒体兼容性与性能。

仓库保存源码、文档及注明来源的公开演示素材，不保存个人视频、运行数据、备份或访问凭据。
