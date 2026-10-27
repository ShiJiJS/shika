# LF8 完整备份公开入口：范围与原始记录

主实现／完整回归源码2f62dd02b2c7e6b37d1f3da0f82a9e479f30566e；最终原生驱动6287cc4747da4160ca20e6e51559183f8e1ed61c。两者App／Android／服务源码及测试相同，后两次提交只修host runner的初扫等待和系统控件可用条件。冻结原型树1cbf605af8f03fa067a4ce8e914bb809e3a487ca独立未改。

生产代码只在公开info的capabilities增加backup_v2；移除测试服务额外追加能力的分支。App使用既有完整备份页，旧服务回退及旧v1任务协议保留；默认32 MiB不变。实际原生使用独立8769、显式64 MiB上限、公开合成图和附件，非正式8760／NAS。

客户端完整670项通过，analyze无问题；服务端完整447项通过、1个既有Starlette测试客户端弃用提示。脚本整体退出1：仓库格式检查有27个既有文件不通过，与基线3a72b1eb的文件列表完全相同，见format-comparison.json；其中test_media_types末尾旧格式也记录在format-changed.log。Ruff代码检查通过，不将功能通过写成全部检查全绿。

native/为唯一正式原生样本：无临时诊断改动，真实DocumentsUI保存取消→同一导出任务保存→选取取消→重新选入，HTTP导入、27目录分页／键盘映射、明确完整替换、免口令新管理代次、恢复前快照只预览。10个App检查点＋4个系统动作，共14点、15张PNG（含保存框改名辅助帧）。文件19,204字节，SHA256为9c9151c2e9da04e1382fd0e79f62acada592a65688b5262dddef3df8f4caa333；系统保存／读回相同，Git的gzip文件解压后为Android实际处理的原字节。公开info前后均声明backup_v2，历史状态由false变true；恢复完成，两类后来标签移除，源图片／附件SHA不变。每例恰一次导出、导入、恢复、登录与指定快照预览；取消保存保留完整原日志，取消选取没有导入／恢复POST。

以下材料不能计入最终14点，也不能被一次成功覆盖：

- diagnostic-launcher-anr/：桌面nexuslauncher无响应挡住首帧，0个App点。保留系统XML／PNG，实际点关闭桌面提示后恢复；首个即时窗口读取仍为旧窗口，随后按真实焦点消失等待成功，见launcher-recovery.json。
- diagnostic-upload-network/：系统文件19,204字节保存／读回校验通过，随后App显示“暂时无法连接服务”，未出现预览。服务trace没有导入POST，原因未确定；已登记[待解决问题#89](https://github.com/ShiJiJS/video_viewer/issues/89)。没有服务记录不能证明完全没有发出网络数据，也不认定为空闲连接问题。
- diagnostic-transport-logging/：仅临时增加IOException输出的一轮完整恢复成功，未复现前一次错误。transport-diagnostic.patch保留改动；正式样本已经撤销。它是不同源码的诊断，不能并入同版稳定性或宣称修好上传。
- diagnostic-initial-scan-conflict/：host初始化目录时初扫未完，服务正确返回409；尚未运行App。本段runner改为只读等初扫结束，不放宽服务保护或自动重发写命令。
- diagnostic-document-frame/：系统已经打开保存框，第一次XML尚未包括底部输入框，随后PNG才显示它，host严格找控件失败并退出。最终runner等到实际输入框／SAVE及选取目标唯一条目可见后才继续，没有假装点击成功。

两个大文件、取消与完整恢复的既有同次验证见[PR #88证据](../lf8-native-backup-roundtrip/README.md)，不把旧24点加到本轮14点，也未在本轮重复约41 MB流程。本轮不是连续三轮、目标手机／云文档提供器、Android内存峰值、正式覆盖升级或发布验收。#89保持开放，完整发布仍待定位该失败及其恢复行为；本轮没有修改通用传输或添加自动重发。

各临时8769容器已移除，显示还原，自己启动的AVD PID17829已关闭；原四个服务ID及运行状态不变，见cleanup和preserved-services文件。实际新导出文档仍保留在专用AVD供复核；没有改默认凭据、SDK、原签名或部署正式服务，没有交付integration-test APK。

只读复核：在仓库根目录执行 `python3 docs/plans/library-first/evidence/lf8-public-backups/verify.py`。manifest封存文件字节，Git固定对象验证生产与驱动来源；不启动服务、模拟器或再次运行测试。此复核检查明确范围，不代表整版性能或稳定性验收。
