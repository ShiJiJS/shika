# GitHub 实施任务

总任务：[媒体库与图包升级 #24](https://github.com/ShiJiJS/video_viewer/issues/24)。LF0–LF2 已实现对应阶段并验证，等待 PR 按依赖合并；LF3 实施中（固定范围、二级原生预览和来源位置恢复已接线，I2 两阶段首次通过，来源接线与关键路径复跑待补），LF4 四入口、双类型媒体库与独立标签已接线，标签分页、跨页批选、图包名称和深列表稳定返回已补齐，剩余来源/错误组合仍在验证，LF5 真实阅读器和最近图包已接入，197项客户端/163项服务端检查通过，完整原生异常/大图验收待补，LF6 后端、卡片/阅读器整理与双类型回收站/跨页批量恢复已接入，271项客户端与既有原生检查点保留，当前214项服务端/Ruff通过；永久删除后台精确清单准备已接，实际删除执行与App双确认仍待实现，既有回收站三轮及每轮8次阅读整理三轮原生证据独立保留，历史两次偶发图片失败仍待定位；永久删除、完整后台批次与安全存储重开待实施；LF7–LF8 尚未实施；以下依赖是实施顺序，不是完成状态。

| 编号 | 任务 | 依赖 |
| --- | --- | --- |
| LF0 | [[LF0] 锁定原型基线与可运行的模块骨架](https://github.com/ShiJiJS/video_viewer/issues/25) | 无 |
| LF1 | [[LF1] 兼容迁移数据模型：媒体类型、图包标签与服务能力](https://github.com/ShiJiJS/video_viewer/issues/26) | [LF0](https://github.com/ShiJiJS/video_viewer/issues/25) |
| LF2 | [[LF2] 图包扫描、分页目录与授权图片读取](https://github.com/ShiJiJS/video_viewer/issues/27) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26) |
| LF3 | [[LF3] 视频从入口范围进入固定预览会话，保留原生播放能力](https://github.com/ShiJiJS/video_viewer/issues/28) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26) |
| LF4 | [[LF4] 原生四入口外壳、双类型媒体库与独立标签页](https://github.com/ShiJiJS/video_viewer/issues/29) | [LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF3](https://github.com/ShiJiJS/video_viewer/issues/28) |
| LF5 | [[LF5] 图包阅读器：横翻、纵向拼接、范围与续读](https://github.com/ShiJiJS/video_viewer/issues/30) | [LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF4](https://github.com/ShiJiJS/video_viewer/issues/29) |
| LF6 | [[LF6] 图包快速整理、准确撤销及安全的回收站操作](https://github.com/ShiJiJS/video_viewer/issues/31) | [LF3](https://github.com/ShiJiJS/video_viewer/issues/28)、[LF5](https://github.com/ShiJiJS/video_viewer/issues/30) |
| LF7 | [[LF7] 设置完整接线、统一任务与兼容的管理备份 v2](https://github.com/ShiJiJS/video_viewer/issues/32) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26)、[LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF6](https://github.com/ShiJiJS/video_viewer/issues/31) |
| LF8 | [[LF8] 原型一致性验收、真实服务联调与兼容升级包](https://github.com/ShiJiJS/video_viewer/issues/33) | [LF0](https://github.com/ShiJiJS/video_viewer/issues/25)、[LF1](https://github.com/ShiJiJS/video_viewer/issues/26)、[LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF3](https://github.com/ShiJiJS/video_viewer/issues/28)、[LF4](https://github.com/ShiJiJS/video_viewer/issues/29)、[LF5](https://github.com/ShiJiJS/video_viewer/issues/30)、[LF6](https://github.com/ShiJiJS/video_viewer/issues/31)、[LF7](https://github.com/ShiJiJS/video_viewer/issues/32) |

当前依赖 PR：[LF0 #34](https://github.com/ShiJiJS/video_viewer/pull/34) → [LF1 #35](https://github.com/ShiJiJS/video_viewer/pull/35) → [LF2 #36](https://github.com/ShiJiJS/video_viewer/pull/36) → [LF3 草稿 #37](https://github.com/ShiJiJS/video_viewer/pull/37) → [LF4 草稿 #38](https://github.com/ShiJiJS/video_viewer/pull/38) → [LF5 阅读会话草稿 #39](https://github.com/ShiJiJS/video_viewer/pull/39) → [LF6 逻辑整理草稿 #40](https://github.com/ShiJiJS/video_viewer/pull/40)。

代码按任务分批提交，PR 引用对应 issue 和 [验收 ID](ACCEPTANCE.md)。方案、独立原型及合成夹具已随 LF0 纳入版本控制；提交、验证和当前边界见 [LF0 记录](LF0.md)、[LF1 记录](LF1.md) 与 [LF2 记录](LF2.md)。

旧 [#1](https://github.com/ShiJiJS/video_viewer/issues/1) / [#23](https://github.com/ShiJiJS/video_viewer/issues/23) 保持原状态，不把原型规划当作既有目标环境验收完成。
