# LF7 v2 App 真实强停与旧安全分册证据

固定源码 `2839c5d788f96d8b2797699a8609df0a55863ad7`，基于 PR #53 最后文档提交 `cbf2df9`。[契约](../../LF7-ARCHIVE-RESTART-DESIGN.md)。只增加原生集成测试、隔离夹具和宿主 runner；`apps/mobile/lib` 和 `services/server/video_viewer` 两棵生产源码树与基线完全一致。`source.json` 保存三个实际执行文件的 SHA，结果再次记录其摘要，`verify.py` 同时对照固定 Git 提交和工作区检查，manifest 输入逐个校验且必须已入库。

| 轮次 | 服务端停留位置 | 视口/字号 | 宿主整轮耗时 | 旧 PID → 新 PID | 新进程 |
| --- | --- | --- | --- | --- | --- |
| round-1 | snapshot_written | 360×740 / 2 | 115.47 秒 | 18988 → 19215 | 退出 0 |
| round-2 | after_replace_before_commit | 390×844 / 1 | 79.17 秒 | 19532 → 19689 | 退出 0 |
| round-3 | restore_committed | 390×844 / 1 | 81.29 秒 | 19991 → 20136 | 退出 0 |

每轮先真实导出/校验 v2 文件，受理一个图包回收和一个恢复命令并保留原回执，另存一个未提交选择；再在实际完整替换表单跨 27 根分页并明确确认。夹具扣留唯一恢复 POST 的 202 响应，原请求已写入生产 SecureStorage，但 App 尚不知道任务 ID。宿主确认活跃 PID 后强停并确认消失，服务端在 App 缺席期间完成原任务、替换管理数据与权威代次。新进程直接使用旧凭据自动重连，不再登录、不重发原写入。

每轮六条旧本机意图均保留原分册；原恢复请求只 GET 核对，两个图包任务/成员按原 graph 读取到原受理 ID 和成功结果，导出之后新增的标签已被完整替换。历史未提交选择不能继续执行。操作任务→原恢复→下载恢复前快照实际打开系统 DocumentsUI，取消后没有保存成功提示、安全日志未结算；原私有备份长度/SHA再次通过验证。真实文件分别为 2,784,541 / 3,138,106 / 3,504,617 字节，不是 40MiB。

宿主将重开请求单独截断：只允许 GET 和既有启动扫描 POST；整轮登录和管理恢复 POST 各一次。五个 App 检查点均同时保存前台窗口/PID和截图；系统保存另有实际 DocumentsUI 窗口与截图。媒体前后各两份合成文件（JPEG+附件）的大小/SHA一致。最后恢复原生 1080×2400 / density420 / font1.0，未重启 AVD、清 App 或改 SDK，始终使用 `--no-uninstall`。

首段 runner 是有意强停，因此非零退出（含 Flutter 附带终结输出）原样保留，**不计为测试通过**。只有第二段实际通过、宿主退出 0 和独立核对吻合才算一整轮。开发 1–4 的失败/开发成功源码均在 [diagnostics](diagnostics/README.md)，不混入最终三个边界。

本轮 analyze 无问题、Ruff 和两份 Python 语法检查通过；服务端管理文件/历史针对测试 24 项通过（67.76 秒，1 条既有 Starlette 警告）。433 项客户端和398项服务端全集是 PR #53 的既有固定源码证据，本轮未重跑全集，不累加成新通过数。这里是 App 进程强停，不能代替服务进程 SIGKILL、整机断电或真实 NAS/手机性能；大文件全路恢复、其它命令/来源组合、历史专用清单/页明细与历史图片失败、完整原型验收仍继续。生产 `backup_v2` 保持关闭，原型树保持 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`，没有发布 APK。

复核：仓库根运行 `python3 docs/plans/library-first/evidence/lf7-archive-restart/verify.py`。重跑任一边界：`python3 scripts/run-archive-restart-test.py --phase snapshot_written --viewport 360 --scale 2 --output /tmp/new-owned-run`，前提是本项目既有的 owned 8762 夹具与 emulator-5554 已运行；脚本不会启动/重置生产服务、NAS 或模拟器。
