关联总任务 #24、LF8 #33。真实 schema0004 数据升级到预览服务 cf992025 时，已完成的视频回收任务在新版任务列表显示“结果待核对”；详情未完成0项、全部1项已完成，原任务 status=completed、成功1/失败0。原数据和操作记录仍在。

根因：FileOperations.finish 在旧版及当前源码中丢弃 total/processed，而统一任务汇总要求这两项，因此新旧真实视频操作都会被误归类。

修正分支 codex/lf8-upgrade-rollback，源码 b79da7b9：新任务保留总数和已处理数；旧回执仅在结束状态、ID/格式与持久成员计数一致时补足只读汇总。未知、pending、布尔或不完整计数、ID不符、needs_attention 继续待核对；部分成功和失败保持原分类，不重写旧结果、不重放命令。

- [x] 原生界面及原数据库定位，保留诊断
- [x] 同一15项新增检查在旧服务代码上5失败/10通过，修正后任务相关21项通过
- [x] 新生产 runtime 实际界面确认旧任务显示完成
- [x] 三轮独立数据升级/回退及原凭据验证
- [x] 完整服务回归、固定版本原始证据和配套镜像说明

[演练方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/LF8-UPGRADE-ROLLBACK.md)。尚未合并或部署NAS，原 #89 上传网络故障与本问题分别跟进。


## PR #94：视频任务状态与真实旧数据升级回退

[草稿PR #94](https://github.com/ShiJiJS/video_viewer/pull/94)基于#92。服务源码b79da7b9、证据1b31995，正常runtime为preview.2，App仍是cf992025的正常release APK6，客户端生产源码未改、未重跑客户端全集。真实旧任务成功1/失败0却显示待核对，已登记#93并修正；旧JSON/回执不改，异常与部分成功保持原分类。最终15项新增检查在旧代码5失败/10通过，修正后相关21项、完整服务462项及Ruff/格式通过。

`accepted-1/2/3`三轮同一公开样本全部完成：2视频（可用1/回收1）、1标签2关联、原轮次2成员及3请求记录，正常启动迁移0004→0014，自动快照旧表相同；原凭据免口令，新媒体库无自动内容，旧任务已完成、原回执不变。UI新建标记标签后停机恢复完整基线，核对容器内版本/完整性/SHA，再启动原旧镜像，旧UI及原记录保留、标记消失。六个App PID、51成功图（另3基线/5诊断）、336输入只读复核通过；控制登录窗口单列，不冒充整份trace零登录。

首次cf任务问题、一次QEMU退出与一次旧容器首启报告0014而宿主恢复为0004的失败均保留，未计入最终三轮；后者原因未确定。最终驱动关闭SQLite连接，在原绑定目录和数据库文件内恢复内容，并先做容器侧核验。当前三轮通过不等于#78已修复。最终自有AVD关闭、11容器移除，原四服务ID/状态、上一阶段数据与媒体SHA未变。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/LF8-UPGRADE-ROLLBACK.md)／[固定源码、原始记录与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/evidence/lf8-upgrade-rollback/README.md)／[配套安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/library-first-preview.md)。本段补UP-01/02和SET-05明确组合；App回退包、真实手机/NAS、当前新服务配旧客户端完整终验、禁用根其它组合及其余原型验收继续。#89原始上传故障未复现，#78仍开放；原型1cbf605保持独立可移除，未正式发布或部署NAS，#24/#33/#32保持开放。

本问题已在修正分支通过验证，仍待PR审阅/合并；实际NAS尚未更新，本issue保持开放。
