# LF7 原历史删除清单与逐项结果证据

固定源码 `cabbc682387713a9c7e14e45fd14d615a325016c`，基于 PR #54 的 `c6fda22`。实现与边界见 [设计契约](../../LF7-PURGE-HISTORY-DESIGN.md)。本目录仅含专用隔离夹具的合成媒体名称、元数据及原始日志，没有私人图包。冻结原型树仍为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`。

## 已验证内容

历史预览/永久删除任务使用原 graph、原父任务、原计划和原包条目读取清单；永久删除另可读取原图片/目录结果。三个认证接口只支持 GET，缺失/无效关联不会回退到当前数据或重建清单。App 专用网关没有执行、重试删除或结算接口，连接变化使旧读取失效。

完整客户端 **451 项通过**，analyze 无问题。完整服务端 **402 项通过**，保留一条现有 FastAPI/httpx 弃用警告；容器按仓库要求使用 `--shm-size=64m`、只读源码挂载。服务端全集启动于 `9199f31`，该提交与固定源码的完整 `services/server` Git 树一致；客户端全集启动于 `619033c`，其 App lib/test Git 树与固定源码相同；最后一次提交仅修正原生脚本的转场定位。Ruff lint 及132份 Python 源码语法检查通过。Ruff format 仍有基线继承的23份文件，列表相同、无新增；Dart format 另有2份未改的基线文件，Git blob 对照见 [dart-format-comparison.json](dart-format-comparison.json)。没有把全量格式检查写成通过。

服务端新增四项覆盖同 ID 跨图、错误父子/类型、明确 graph/epoch、有界分页、真实导出/连续完整恢复及无效清单拒绝。额外测量使用 **43,806,720 字节 SQLite、18,000 项 manifest**，读取100条/末页的 Python tracemalloc 峰值 **2,550,992 字节**，见 [bounded.log](bounded.log)。这是实际管理文件和 Python 分配量，不能视作18,000张物理图片、进程 RSS、恒定磁盘 I/O 或 NAS 性能。

## 真实 Android 路径

独立服务 `video-viewer-history-purge-app-lf7` 仅监听本机8763，使用现有 `emulator-5554`。测试保留安装与设备数据，使用三个专用安全日志键；不卸载、不清应用数据、不重启 AVD。每轮结束恢复原屏幕尺寸、density 和字号。正式8760、NAS、SDK、其它隔离服务及发布 APK 均未改。

夹具真实扫描27包、153图片。大包127图在 `0101.png` 注入权限失败；其余26包完成图片删除，留下附件并记录目录保留。真实结果为126图已删、27图未完成；全部图片/目录结果共207项，其中目录54项。随后真实完整恢复预删除管理文件，将原任务保存为历史；恢复管理数据不会复活已删除源图片。

从完整 App 的设置→操作任务→历史→原永久删除任务进入原结果，读取原权限错误；切换全部结果，下一页注入一次503，旧页保留，再点击同一分页只 GET 同一查询。读取目录结果、27包的最后3包、127图片的最后27图，再返回原预览任务核对原清单。每轮7张截图同时保存实际前台窗口；结果、请求轨迹、54份剩余源文件和历史 SQLite 的前后哈希、三份真实安全日志不变断言分别保留。

| 固定源码轮次 | 逻辑视口 / 字号 | 证据 |
| --- | --- | --- |
| 1（64.96秒） | 360×740 / 2 | [result.json](round-1/result.json)、[flutter.log](round-1/flutter.log) |
| 2（55.14秒） | 390×844 / 1 | [result.json](round-2/result.json)、[flutter.log](round-2/flutter.log) |
| 3（58.00秒） | 390×844 / 1 | [result.json](round-3/result.json)、[flutter.log](round-3/flutter.log) |

原始轨迹允许唯一登录 POST 及原有启动扫描，历史清单/结果查询全部 GET 且绑定同一个原 graph；没有删除、恢复或 acknowledge 写入。每轮中唯一503的后续200须为相同路径与参数。原 graph、plan、task 的具体身份在 [setup.json](setup.json) 中，复制的正式历史 bundle 及独立 SQL 摘要见 [original-history-bundle](original-history-bundle/) 与 [backend-proof.json](backend-proof.json)。

独立静态 [视觉报告](visual-review.md) 以原 Paper 设置页为参照。初审建议把根目录 `.` 改为“图包根目录”，并指出小屏目录截图尚在加载；本次固定源码补齐文案及等待条件后重跑。自然换行和滚动裁切不作为溢出；静态评审不替代运行轨迹或返回行为检查。

## 可复核输入与限制

[source.json](source.json) 记录136份运行源码哈希、Git提交和 App/服务端树；[manifest.json](manifest.json) 覆盖本目录的固定输入。`python3 docs/plans/library-first/evidence/lf7-purge-history/verify.py` 独立核对 Git 源码、测试汇总、原 SQLite、21个真实窗口截图、三轮无写入/无源文件变化与恢复视口；输出见 [proof.json](proof.json)。原始日志保持原样。

[diagnostics](diagnostics/) 分开保留开发失败、旧源码成功、截图等待修复前的三轮及首次遗漏 Docker shm 参数的401通过/1失败全集，不混入最终三轮或最终402项结果。

本阶段只补 BAK-03、SET-05、DEL-04/06 的历史读取部分。其它命令/来源强停组合、历史图片解码/资源不可用、全原型暗色/横屏/手势、目标手机/NAS及原签名发布仍开放。生产 `backup_v2` 仍关闭，LF7 与总任务不在本段关闭。
