# 恢复图片读取：普通26、本机 preview.6

[本轮说明](../../LF8-RESTORED-IMAGE-READ.md)。全部图片和目录都是本机合成夹具；无真实 NAS 媒体、口令、令牌、配置或完整数据库。产品源码82eacdbd，测试检查点修正e4bcf533，普通客户端8416a3f7/原签名code26保持。尚未部署 NAS。

## 结果与证据

| 核对项 | 记录 |
| --- | --- |
| 同一原故障样本三个409 | [升级前复现](original-fixture-reproduced.json) |
| 停机备份后原挂载/37表/46文件保持 | [升级记录](original-upgrade-public.json) |
| 原ID/版本3，三个接口各三次200、Range206 | [直接读取](original-read-200.json) |
| 普通App打开原页 | [原生结果](original-native-open.json)、[封面](03-original-restored-cover-success.png)、[图片](05-original-restored-last-page.png) |
| 新长图三张，保留两项附件，未勾选不能提交 | [核对页](07-tall-review-three-images.png) |
| 原删除任务2/3，仅第三张失败归位 | [结果](08-tall-partial-two-of-three.png)、[原状态](tall-native-state.json) |
| 明确恢复一次，原计划1/1 | [确认](09-tall-restore-confirm.png)、[原计划结果](10-tall-original-restore-result.png) |
| 恢复后原删除重试被拒绝 | [原结果保持2/3](11-tall-old-purge-protected.png)、[stale_pack_state API证据](tall-native-state.json) |
| 剩余同一页，纵向45% | [最近1/1](12-tall-recent-one-of-one.png)、[ROW13中部](13-tall-restored-row13-offset.png) |
| 实际App强停，PID3283→3952 | [冷启媒体库](14-tall-cold-library.png)、[最近](15-tall-cold-recent.png)、[同位置](16-tall-cold-row13-offset.png)、[返回最近](17-tall-return-after-cold-read.png) |
| 长图三个读取200，37表/49文件保持 | [只读核对](tall-readonly-200.json) |
| 原有46文件保持，只删确认的Tall01/02 | [文件清单](file-manifests.json)、[独立交叉检查](verified-phase.json) |
| 37表逐阶段行数/摘要，设置只留摘要 | [表摘要](catalog-table-digests.json) |
| 原生与准备请求分开 | [普通App](requests.jsonl)、[准备API](preparation-requests.jsonl)、[界面动作](ui-events.jsonl) |
| 镜像78份运行文件与源码逐份匹配 | [运行文件](runtime-source.json)、[归档/rootfs/健康检查](build-result.json) |

主Agent逐张查看本目录13张原始截图，约389dp、浅色竖屏，无独立视觉评审。11图显示原2/3结果；拒绝原因由同一任务API证据确认，不冒称截图展示错误提示。原短图明确点击“返回最后一张”后保存偏移0，不作为45%续读证明。长图45%由600×3000、30行网格的ROW13.5画面、原生请求、服务进度和真实强停新PID共同确认。

## 检查记录与失败保留

[针对44通过](read-after-fix-targeted.log)；[最终完整509通过](full-server-atomic.log)，[Ruff](ruff-atomic.log)/[147份格式](format-atomic.log)通过。完整检查使用不可变测试提交e4bcf533、只读/无网络/64MiB shm/tmpfs，与产品运行文件82e相同。

[首次完整508通过/1失败](full-server.log)是SIGKILL夹具标记创建后尚为空，父进程读得空字符串；测试辅助进程改为旁路文件+原子发布后再跑全量。原产品回归[首版](read-before-fix.log)含真实读取失败和软链接错误断言；按既有422契约纠正后[旧产品仍1失败/8通过/2未选中](read-before-fix-corrected.log)。未用最终绿色替换原失败。Starlette已有弃用警告保留。[客户端834与分析的复用范围](reused-client-check.json)是同一未改源码的已有结果，没有重跑客户端全集。

两次QEMU退出分别在并行检查期间与无其他测试时发生，见[第一次](emulator-exit-public.json)、[第二次](emulator-exit-serial-public.json)。同一AVD数据随后采用[图片专用配置](emulator-image-profile.json)，关闭宿主视频/音频；新长图实际读图、冷启证明限于该配置，#78未解决。服务不因此重启，原恢复任务先已完成，后续只查询原回执。[接续日志](resume-restore-and-read-tall.log)、[真正App冷启日志](cold-resume-tall.log)。

Tall准备API种子先完成后驱动误读回收对象层级；后续仅查回原结果。首次同模式chmod没改变ctime的[断言失败](tall-native-partial-resume.log)后，保留同一2/3任务，才切换并恢复权限位构造[确定ctime变化](recover-tall-partial-state.log)。[原生恢复后模拟器退出日志](restore-and-read-tall.log)保留。没有重提永久删除/恢复以重跑流程。观察脚本供审阅原过程，需要私有夹具布局和辅助模块，不是对真实媒体直接运行的操作工具。

## 仍未解决：扫描关联 #163

[新缺陷记录](post-restore-scan-identity-conflict.json)、[已建issue](scan-identity-issue-receipt.json)：Tall准备的两次明确扫描让先前可读的Restore-partial变为旧missing+新available。同目录/设备/inode及剩余SHA不变，旧标签/最近仍在旧ID，新ID没有关联。真实最近返回2包；不能把本轮扫描前读取成功延伸成扫描后也成功。匹配分支根因尚未定位。

下次 NAS 更新前先修#163。Tall完成恢复和冷读之后不扫描，保持原身份，停止保留专属容器/媒体/数据/配置/控制文件。[清理记录](cleanup-public.json)确认自有AVD/注册、代理、导出/归档和4个测试镜像标签清理；原四服务ID/healthy、常用AVD、SDK/签名、候选/回退APK、服务归档与完整备份保留。移除文件表观约2.09GB，不当作实际释放空间。#159、#160、#78开放；手机/NAS、其余验收和正式交付继续。

本目录所有可提交文件列入 `CHECKSUMS.sha256`，该清单自身除外；日志去敏主机路径、去除行尾空白，私有原始记录保留。日志显式强制加入Git，不能只在忽略目录本机留下验证结果。
