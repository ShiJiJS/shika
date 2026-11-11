[项目首页](../README.md) · **简体中文** · [English](README.en.md)

# 拾刻文档

先了解[拾刻能做什么](../README.md#主要功能)，再按下面的任务选择文档。README、文档导航和部署手册均提供简体中文与英文；开发和接口细节目前以中文为主。

## 安装、使用与维护

| 你想做什么 | 文档 |
| --- | --- |
| 第一次在 NAS 安装拾刻 | [部署手册：准备与部署](deployment.md#首次部署) |
| 在飞牛中创建服务 | [飞牛部署](deployment.md#飞牛-fnos-部署) |
| 安装 App 并连接服务 | [安装与连接-app](deployment.md#安装与连接-app) |
| 理解媒体库、阅读和整理操作 | [开始使用](deployment.md#日常使用) |
| 备份、升级、换 NAS 或回退 | [备份、升级与迁移](deployment.md#备份升级与迁移) |
| 排查连接、扫描、播放或删除问题 | [常见问题](deployment.md#常见问题) |
| 反馈问题或查看待办 | [GitHub Issues](https://github.com/ShiJiJS/shika/issues) |
| 批量生成视频标签或导入已有标签 | [视频打标 Skill 与 CLI（选装）](video-tagging.md) |

## 开发与接口

| 文档 | 内容 |
| --- | --- |
| [开发指南](development.md) | 环境准备、调试、APK 构建与测试 |
| [服务端](../services/server/README.md) | Docker 开发、API、扫描、回收与完整备份 |
| [命令行客户端](../apps/cli/README.md) | 安装 CLI、视频查询和标签自动化 |

部署模板：[Compose](../deploy/fnos/compose.yaml) · [环境变量](../deploy/fnos/.env.example) · [媒体允许范围](../deploy/fnos/mounts.json.example)。运行实例的完整 API 参数以 `/openapi.json` 为准。
