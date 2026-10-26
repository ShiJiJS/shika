# GitHub 实施任务

阅读器继续补证：[可见末张跳过 PR #57](https://github.com/ShiJiJS/video_viewer/pull/57)，原生三轮及兼容回归见 [LF5 记录](LF5.md)。整体原型对照继续。

阅读器最新补证：[失败末张与横屏操作 PR #56](https://github.com/ShiJiJS/video_viewer/pull/56)，固定源码/原始证据见 [LF5 记录](LF5.md)。LF5、LF8及总任务仍开放。

总任务：[媒体库与图包升级 #24](https://github.com/ShiJiJS/video_viewer/issues/24)。最新阶段状态统一见 [PLAN.md](PLAN.md) 和对应LF记录。当前LF8整体验收推进中，最新验证范围与未完成项见[RESULTS.md](RESULTS.md)；以下保留LF7实施历史：任务中心、整份恢复/停止、永久删除剩余选择及服务端默认值/本机迁移已接入；目录类型/启停和图包缺失管理已接入，实际验证见LF7证据；备份v2文件/校验和v1转换模块已落地，只读历史包与查询已落地，服务端恢复代次已接，App代次与历史分册由PR #51接入；完整替换协调、正式历史路由、有界传输及原历史删除专用清单/逐项结果已接入，三处v2 App强停及历史只读原生验证已补；其它命令/来源强停、历史图片资源错误及最终原型/目标设备继续推进，生产backup_v2仍关闭。近期草稿：[任务中心 #41](https://github.com/ShiJiJS/video_viewer/pull/41) → [恢复服务端 #42](https://github.com/ShiJiJS/video_viewer/pull/42) → [恢复App #43](https://github.com/ShiJiJS/video_viewer/pull/43) → [删除选择 #44](https://github.com/ShiJiJS/video_viewer/pull/44) → [真实1003包强停 #45](https://github.com/ShiJiJS/video_viewer/pull/45) → [设置默认值 #46](https://github.com/ShiJiJS/video_viewer/pull/46) → [目录与缺失管理 #47](https://github.com/ShiJiJS/video_viewer/pull/47) → [备份文件模块 #48](https://github.com/ShiJiJS/video_viewer/pull/48) → [只读历史 #49](https://github.com/ShiJiJS/video_viewer/pull/49) → [服务端代次 #50](https://github.com/ShiJiJS/video_viewer/pull/50) → [App代次与历史分册 #51](https://github.com/ShiJiJS/video_viewer/pull/51) → [完整恢复协调 #52](https://github.com/ShiJiJS/video_viewer/pull/52) → [App文件接线 #53](https://github.com/ShiJiJS/video_viewer/pull/53) → [v2 App真实强停 #54](https://github.com/ShiJiJS/video_viewer/pull/54) → [原历史删除明细 #55](https://github.com/ShiJiJS/video_viewer/pull/55)。以下依赖是实施顺序，不是完成状态。

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


## 2026-10-26：LF8共享比例与收口入口

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)补齐两类库共享几何、设置与标签确认密度及独立复核证据；[RESULTS.md](RESULTS.md)现逐项登记45个验收ID。#33/#24保持开放，下一段优先真实续读区、权威类型总数、保守标题/作者与全范围排序一致性，详见[差异审计](LF8-SHARED-GEOMETRY.md)。本轮只有共享区域局部证据，不能替代完整管理/阅读/动作或目标设备验收。
