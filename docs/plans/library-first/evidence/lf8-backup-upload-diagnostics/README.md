# LF8 上传失败诊断与原请求找回

主实现／完整客户端回归ed09749186b2f9f375fdd0c22b38d4a9fefb768b；最终Android驱动／测试工厂848a1b8a0f80dccc3fd49ea1fa7676e5405114ba。两者App生产源码、Android与单元／组件测试相同，后续提交只扩充集成驱动、host runner、隔离服务工厂和方案，并修正host显示配置归还。基线为PR #90的6ae5ad6，原型树1cbf605af8f03fa067a4ce8e914bb809e3a487ca独立未改。

生产变化仅在ServerApi保留IOException和异常发生时的Dart等待阶段，放在ApiFailure的内存字段；UI仍显示原有简短提示，不自动记录／上传底层原因，不含新增网络重试。阶段不证明已发送多少数据或服务是否受理。显式测试模式只输出异常类型／message、阶段及本次合成文件大小／SHA，不输出认证头、口令或备份内容。

客户端完整672项、相关28项、最终analyze／Dart格式及Ruff通过。真实拒绝连接测试补充了服务尚未受理的组合：上传出现opening阶段SocketException，重建客户端对象、删去本地临时输入后，两次均GET同一原请求并收到404，日志／请求键保留，没有POST。该组件使用MemoryBackupWorkStore，不能当作进程强停或真实安全存储证据。已有“已受理但丢回复”的模型检查继续回归。服务生产源码与#90相同，本轮没有重跑服务端447项全集；上轮27个原有格式问题也没有在本轮解决。

controlled-reply-restart/是受控回复中断，一次完整的双进程验证：

- 独立8769工厂通过显式环境开关，仅让第一次已受理的导入回复少发1字节，真实HTTP连接按协议错误关闭。实际字节数和SHA见本例saved-document.json，Android真实保存／选入一致。
- 真实错误页面及安全日志捕获成功，错误为readingResponse阶段HttpException，message为“Connection closed while receiving data”。这是人为制造的、已知服务受理的错误，不是#89原始偶发失败的复现。后者的服务trace未见导入POST，原因仍未知。
- 在错误页面实际停止活跃App旧PID，确认消失（failure-force-stop.json）；仅删除该次日志指向的一个32位ID暂存文件（观察路径及大小后操作）。保留真实安全凭据／操作日志，新App以不同PID初始化成功（resumed-app-pid.json），无需口令或重选本地文件。明确点击“继续核对已选备份”，原请求返回同一个已完成任务，27目录预览与完整替换确认仍关闭。
- 重开窗口请求全部为GET（实际数量见resumed-requests.json），其中一次精确原请求GET，没有登录／上传／恢复POST。第一次导入POST恰1次，Idempotency-Key、安全日志、原任务和SQLite回执相同；根27、视频标签2、图包标签2、包1／页1及旧管理代次保持，源图片／附件SHA不变。SQL只读投影不称整库字节相同。
- 第一次Flutter命令因明确强停按预期非零，保留工具断连／临时监听目录清理异常；服务日志中的Content-Length协议异常同样是注入的一部分。第二次Flutter命令通过，host受控流程整体退出0。不能把第一次非零计为普通成功轮。

该例4个失败前正常App点＋错误页1点＋重开3点=8个App点，另4个系统动作，共12点、13张PNG（含改名辅助帧）。普通normal-after-control/在同源码、关闭注入下，系统保存／选择取消、实际同文件（大小／SHA见saved-document.json）、27目录确认、完整恢复及快照只预览一次通过，10个App点＋4个系统动作，共14点、15张PNG。两类各一次合计26点／28张PNG，按顺序运行；不是三轮稳定性。普通例没有复现#89，不能据一次通过宣称该错误已修复。

development-assertions/保留新增组件测试的两次错误断言和初次analyze提示；404原请求查询在业务层转换为保留原记录的LibraryFailure，初版错断言成ApiFailure，pendingReceipts字段也由request_id改为实际key。最终断言核对业务错误、完整原日志／键和精确两次GET，未放宽“不重发”要求。初期材料不计最终28／672项。

intermediate-before-display-fix/另保留d22d6fc的两次中间流程：受控回复中断与重开功能检查通过，但host误将原屏幕配置变量original覆盖为原命令，finally报KeyError(size)，未归还屏幕设置；后一次普通流程继承该临时设置。它们不计最终26点。修正为独立命令变量，并让归还失败使host非零退出；按首轮original-viewport恢复原1080×2400／420dpi／字号1.0（display-recovery.json），再用新源码重新验证两例。正式验收同时要求host-exit为0、恢复前后显示一致、无restore-error，不能仅凭流程result判断成功。

所有新文件都是独立合成数据，Git仅将实际备份字节gzip保存以缩小体积。最终两次8769容器已移除，显示还原，自有AVD关闭（见cleanup.json），原四个服务ID和运行状态保持。默认凭据、SDK、原签名、正式8760／NAS及冻结原型未改，未发布APK。目标手机／云文档提供器／真实NAS、原签名覆盖升级及原始#89原因保持待验证。

只读复核：`python3 docs/plans/library-first/evidence/lf8-backup-upload-diagnostics/verify.py`。它核对manifest输入、固定Git源码、普通／受控样本、错误／安全日志／PID／HTTP／SQL投影及资源归还，不启动App、服务或再次运行测试。
