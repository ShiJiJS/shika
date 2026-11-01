# 恢复后扫描：原身份与续读

[完整说明](../../LF8-RESTORED-PACK-SCAN.md)。全部为本机合成夹具，无真实NAS媒体、配置、口令、令牌或完整数据库。产品7ddf20d4/runtime preview.7，普通原签名26/客户端8416a3f7未改；未部署NAS。

| 核对项 | 证据 |
| --- | --- |
| 同一旧missing+新available故障，最近2包 | [原样本](original-scan-conflict-reproduced.json) |
| 停止状态完整私有备份，旧服务重启后37表/49文件保持 | [基线](original-baseline-public.json) |
| 仅升级本机服务，挂载/环境/命令/用户/健康检查保持 | [升级](upgrade-public.json) |
| 原ID恢复、新无管理记录移除、Tall原ID/页/45%保持 | [两次明确准备扫描与读取](original-scan-state.json) |
| App指定目录扫描一次，scope.all=false | [普通App请求](requests.jsonl)、[原任务](native-scan-state.json) |
| 页面真实扫描记录更新，已知8空包/4保护包不冒称全绿 | [扫描前16:57](02-directory-before-native-scan.png)、[扫描后17:07](03-directory-native-scan-result.png) |
| 原恢复图包重回最近，实际图片正常 | [最近3包](04-recovered-recent-three-packs.png)、[原图片](05-original-reader-after-scan.png) |
| 原标签关联与实际筛选/阅读 | [标签计数](06-existing-pack-tag.png)、[选中1标签的3包结果](07-original-tag-filtered-packs.png)、[从该标签打开Tall](08-tall-from-tag-row13-offset.png) |
| 强停旧PID3575消失→新PID6731，同一Android启动 | [状态](native-read-state.json)、[冷启媒体库](09-cold-library-after-scan.png) |
| 冷启续读仍同页45%，返回最近保持 | [最近3包](10-cold-recent-three-packs.png)、[ROW13中部](11-cold-tall-row13-offset.png)、[返回最近](12-cold-return-recent.png) |
| 扫描后明确重试同一旧删除，拒绝且保持2/3 | [原结果](13-old-purge-protected-after-scan.png)、[stale_pack_state及只读数据核对](old-purge-after-scan.json) |
| 49份源文件从头到尾大小/SHA相同 | [文件清单](file-manifests.json) |
| 14阶段37表行数/摘要，设置和凭据只留摘要 | [表摘要](catalog-table-digests.json) |
| 主Agent另行交叉核对请求/页/位置/源码/归档 | [核对结果](verified-phase.json)、[脚本](verify-phase.py) |
| 候选及实际已停容器79份文件匹配产品提交 | [镜像](runtime-source.json)、[已停容器直接读取源码](stopped-container-runtime-source.json)、[归档与rootfs](build-result.json) |
| 自有环境清理，原四服务及必要文件保留 | [清理](cleanup-public.json) |

12张原始截图均由主Agent逐张查看，约389dp、浅色竖屏，无独立视觉评审。两次长图画面顶端为ROW13中部、下一完整行为ROW14，配合同一页ID、45%服务进度、真实App强停新PID和不变的Android boot_id判断位置；不是用服务字段代替实际看图。13图显示2/3，具体拒绝原因由同任务API确认。

## 完整检查与边界

[固定源码完整524通过](full-server.log)，[新增15通过](scan-final-15.log)，[Ruff](ruff-final.log)/[149文件格式](format-final.log)通过。中间版本[针对53通过](scan-after-fix-targeted.log)保留原范围；[旧产品13例7失败/6通过](scan-before-fix.log)真实复现原ID丢失、已有重复记录未修复、冲突没有报告。规定容器只读/无网络/64MiB shm/tmpfs；健康探测预算未改。

最初Ruff调用遗漏/tmp tmpfs而无法建缓存，随后规定环境调用又指出新增import排序问题；[两份原失败](ruff-work.log)、[排序提示](ruff-work-tmpfs.log)保留，固定提交最终均通过。[客户端834与分析](reused-client-check.json)复用同一未改源码已有结果，没有声称本轮重跑全集。

第一次明确扫描任务终态deferred，已修复旧重复身份，Tall因已知签名变化进入默认两秒稳定等待。驱动误要求整个根目录completed的[初次断言](check-original-scan.log)保留；随后明确再扫一次，Tall完成，夹具原有8空目录仍报告pack_empty。接着驱动又错误比较全部设置的[断言](check-original-scan-resume.log)保留：本来应更新的两项扫描设置已单独列出，凭据及其余设置保持。之后[只查询原两个任务核对](check-original-scan-query-resume.log)，没有第三次准备扫描。

App再扫后的[首次驱动断言](native-scan.log)误把seen_scan当成内容变化；仅此扫描标记变化、页ID/其它内容相同。后续[只读原任务并返回最近](native-scan-query-resume.log)，没有重提扫描。网格卡片语义以数量/状态开头，驱动误用最近列表名称前缀后只滚动，未打开替代图包或新发业务动作；[修正记录](tag-grid-driver-diagnostic.json)。旧删除任务也在滚动到屏外记录后才打开并核对UUID，确认之前没有重试请求。

普通App只有一次root_id=purge扫描、三次阅读会话和一次明确旧任务重试，没有新永久删除或恢复POST。[原生动作](ui-events.jsonl)、[准备API](preparation-requests.jsonl)、[实际强停续读](cold-read.log)、[旧任务保护](old-purge-guard.log)分开。页面8空包提示是夹具保留的事实，不是全库成功；本机过程也不冒称自动化始终无断言错误。

源文件49份保持；索引48→43页、25→24包是移除无管理重复页1条和两个图包已永久删除的4条旧页，原删除逐项日志仍保留。扫描期间28张非扫描业务表/非扫描设置/凭据保持；GET读图窗口37表/设置相同；旧任务重试仅任务/请求记录变化，其余33表/设置/凭据保持。实际阅读正常更新进度revision、最近时间和会话，不能把整个过程称作所有管理表零写。

## 范围与保留

已有重复的新ID若有标签/进度/偏好/最近/会话或任何操作外键，则保留两侧并报告身份冲突。五类管理数据、扫描期间新加标签、外部内容/文件身份/mtime/目录/创建时间变化，以及缺少/历史化日志由新增用例核对；不全局按路径认同一包，也不静默自动合并两边数据。

[图片专用配置](emulator-profile.json)关闭宿主视频/音频，完整服务检查终态后才启动自有模拟器。本轮未观察到QEMU异常退出，不能以此关闭#78或证明视频/音频/原配置稳定。自有AVD/注册、代理、源码导出/中间归档及3测试标签已清理，保留小型已停夹具和私有完整备份供后续核对；原四服务ID/healthy、常用AVD、SDK/JDK、签名、普通/回退APK、候选服务镜像/归档、此前NAS成对快照保持。清理数为表观文件字节，不等于实际回收空间。

#159恢复后偶发503、#160空选择待处理堆积、目标手机/NAS部署、其余45项验收与正式交付继续。原型冻结树单独可移除，未改。观察脚本需要私有夹具与辅助模块，仅供审阅本次步骤，不是对真实媒体直接运行的操作工具。

所有可提交文件的SHA列在 `CHECKSUMS.sha256`，该文件本身除外；公开日志去敏主机路径、去除行尾空白，私有原始记录保留。日志显式强制加入Git。
