# 当前候选验收覆盖核对

跟踪[#133](https://github.com/ShiJiJS/video_viewer/issues/133)，详见[方案与剩余流程](../../LF8-ACCEPTANCE-AUDIT.md)。

- 正常App源码12d6ca67、preview.16/code22：重新执行完整Flutter套件791项，退出0。命令、目录、源码树与日志SHA见[test-context.json](test-context.json)，原始输出见[current22-flutter-test.log](current22-flutter-test.log)。
- 服务源码b79da7b9完整树及73运行文件保持；复用原462项结果及原始日志，本轮未重跑服务端套件。
- [覆盖索引](../../ACCEPTANCE-COVERAGE.json)逐字保留原45项要求，定位11组实现/测试入口。六组2437份文件仅核对完整性，未把文件SHA或旧画面相同算成当前整项通过。
- `python3 scripts/audit-library-first-acceptance.py`只读核对来源和索引；故意改候选编号的副本被以`Audit stale`拒绝。只有明确审阅后才使用`--write`更新索引。脚本需要仓库Git历史和所列固定证据文件。
- 剩余9条工作流程均保留待验，尚未开始R1。本轮没有产品代码修改、新APK、模拟器/服务启动、手机安装或NAS操作。按用户要求收尾后暂停。

本记录证明当前自动化套件及来源核对结果，不替代真实手机、NAS、系统云文件选择、有声播放或完整视觉验收。

首次提交归档复核发现备份上传诊断的25份既有日志被忽略规则漏掉。本轮按原清单SHA原样补入，未改写旧manifest；随后重新导出提交文件、借助原仓库Git历史运行索引复核。该检查并非无Git历史的独立运行。

[提交归档复核结果](archive-replay.json)记录最终来源0804b2d4和退出0；原始日志保留终端空格，不为格式检查改写其字节。
