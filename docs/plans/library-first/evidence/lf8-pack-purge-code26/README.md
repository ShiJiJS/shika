# 普通26：图包永久删除与原任务重试

完整范围见[本轮说明](../../LF8-PACK-PURGE-RETRY.md)。本目录仅含本机生成的合成输入与普通发布 App 的实际操作记录，无 NAS 媒体、登录凭据、真实收藏或个人业务库。

## 从哪里核对

- [verified-flows.json](verified-flows.json)：三轮原任务、唯一原请求、真实PID变化、503→200、查询零写、逐表与字节检查、最终文件总数。Purge-06/07/08是三轮；前五个诊断样本单独列出。
- [requests.jsonl](requests.jsonl)、[preparation-requests.jsonl](preparation-requests.jsonl)：前者为普通 App 经代理的真实请求，后者为扫描、标签/阅读状态准备及两次明确原任务恢复。没有把准备写入冒称 App 操作。请求头、登录密码和令牌不落入公开记录。
- [catalog-summaries.json](catalog-summaries.json)：每阶段35张普通表逐表行数/SHA，加settings/access_tokens两张表摘要及各设置值SHA。原始逐行数据仅在自有容器中 mode=ro 读取；未从宿主机打开运行中的 SQLite/WAL。
- [file-manifests.json](file-manifests.json)：初始72文件、追加来源及各阶段相对路径/字节数/SHA。最终删除28张原核对图片，原保留44份完全相同，显式新增2份保留，总46份。
- [fixed-runtime-source.json](fixed-runtime-source.json)、[build-result.json](build-result.json)、[archive-identity.json](archive-identity.json)：cf9a的77份运行文件匹配、其他76份不变、ARM64归档、配置字节摘要/源码标签/rootfs核对。镜像摘要和归档配置摘要分别记录，不混称。preview.5本轮未部署NAS。
- [cancel-checks.json](cancel-checks.json)、[saved-choice-checks.json](saved-choice-checks.json)、[stale-case-checks.json](stale-case-checks.json)、[Empty-remove-result.json](Empty-remove-result.json)、[Restore-partial-result.json](Restore-partial-result.json)：未勾选保护、取消保留、旧清单拒绝变化、空目录和恢复后阻止旧删除。
- [cleanup-public.json](cleanup-public.json)：自有代理/AVD/源码导出和测试镜像清理；专属故障容器停机，原数据/媒体/配置/控制文件保留供#161复核原身份。运行容器准确为原四服务，实际ID及healthy、常用AVD和重要开发文件保持。逻辑文件大小不等同实际释放磁盘量。

## 实际截图

19张PNG均由主Agent查看，配套同名XML为当时原生树；约389dp、浅色、竖屏。不是独立视觉评审或真机证明。截图只作为界面证据，物理删除、后台受理和数据保持另以请求/文件/数据库交叉核对。

| 场景 | 原生画面 |
| --- | --- |
| 未勾选不可确认 | [未勾选](02-first-review-unchecked.png) |
| 三张精确清单 | [清单](03-exact-image-manifest.png) |
| 取消后保留选择 | [取消](05-cancel-retains-selection.png) |
| 旧故障原任务修复后完成 | [原任务3/3](Purge-01-retry-completed.png) |
| 回执503仍保留原请求 | [离线回执](Purge-06-receipt-offline.png) |
| 后台部分完成 | [同一任务2/3](Purge-06-partial-task.png) |
| 剩余图片与目录结果 | [逐项结果](Purge-06-partial-image-results.png) |
| 明确重试确认 | [确认](Purge-06-retry-confirm.png) |
| 三轮原任务3/3 | [第1轮](Purge-06-retry-completed.png)、[第2轮](Purge-07-retry-completed.png)、[第3轮](Purge-08-retry-completed.png) |
| 无附件包删除2/2 | [空目录结果](Empty-remove-completed.png) |
| 恢复剩余图片 | [回收站](Restore-partial-restored-trash.png) |
| 恢复回执未核对时先阻止旧重试 | [本机保护](Restore-partial-client-plan-block.png) |
| 恢复后旧任务不删除 | [保护结果](Restore-partial-old-retry-protected.png) |
| 最近原页变为1/1 | [最近](Restore-partial-recent-one-of-one.png) |
| 核对后3种变化均0/3 | [新增图片](Changed-add-image-protected-result.png)、[替换身份](Changed-replace-image-protected-result.png)、[新增附件](Changed-add-attachment-protected-result.png) |

## 原失败与未完成范围

[retry-signature-diagnostic.json](retry-signature-diagnostic.json)记录已归位图片ctime差异。[fixture-upgrade-public.json](fixture-upgrade-public.json)记录保持原库/原任务升级。Purge-01到05的state文件保留故障与额外恢复标记；Purge-05的[控制JSON异常](control-json-diagnostic.json)来自私有故障注入包装器，容器内原子写入后再做标准三轮。Purge-02/03同因未直接证明；Purge-04的[QEMU退出](emulator-exit-public.json)继续关联#78。未用替代任务掩盖旧结果。

[第一次完整检查](full-server.log)495通过/2失败；其中shm配置错误已按项目脚本纠正，恢复后503单独记#159。[规定环境完整检查](full-server-verified-env.log)497通过；[针对检查](rollback-final-targeted.log)50通过；[修复前针对检查](rollback-before-fix.log)1失败/4通过。一次现有Starlette弃用警告保留。Ruff/格式结果同目录。客户端834项与分析复用同一未改源码的结果，见[摘要](reused-client-check.json)，没有冒称本轮重新跑客户端全集。

Purge-06的驱动最初未滚到屏外原回执，尚未发送动作就停止，补滚动后继续。Purge-08完成删除和数据断言后，主Agent过早启动下一驱动，两次UI树读取重叠，返回设置报137；下一项未发送业务命令。从当前任务列表仅返回设置后继续，未重放删除。对应state保留标记，三轮业务主流程通过不代表驱动全程无错误。

`.py.txt`是本轮私有驱动/核对实现摘录，供审阅操作与断言；不是独立可执行安装入口，AVD和构建导出已清理，原故障数据停机保留。恢复样本的原驱动先遇到未核对恢复计划的本机保护，再经任务页查询恢复原回执；随后resume驱动验证旧任务stale_pack_state，finalize驱动只核对最近及既有数据。期间修正带计数的类型按钮、最近独立类型及页码空格匹配，未重放恢复。没有改生产批量上限、文件稳定等待2秒或删除校验来凑结果。小PNG不代表真实照片/NAS性能。其余45项组合、真机、暗色/大字/横屏、后续批次停止、播放生命周期与管理恢复继续，草稿未合并或正式发布。

[restored-image-read-conflict.json](restored-image-read-conflict.json)记录新发现的#161：恢复后03.png仍在、数据保持，但封面/原图/缩略图均409/image_changed，库签名与实文件仅ctime不同。最近1/1截图中的封面为错误重载状态，不作为读图通过。保留停机原夹具继续修复，不部署NAS。

[CHECKSUMS.sha256](CHECKSUMS.sha256)覆盖本目录其余全部文件，不含自身。
