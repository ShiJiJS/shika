# NAS 健康检查与繁忙扫描记录

2026-11-01，跟踪 #154/#135/#33。固定实现 `6a119b1c0c2022a2f9cc615679bc8aab790f122e`；客户端保持 `8416a3f7` / code26，无新增 App 构建。原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 与原45项要求未变。[修改与部署说明](../../LF8-NAS-HEALTHCHECK.md)。本轮是服务监测修复，没有 UI 改动或新截图。

## 文件与口径

- preflight、architecture、resource-before/after、host-pressure：原服务仍运行时的只读状态。aarch64 原生 CPython；保留原 3 秒超时和直接 HTTP 的耗时。D 状态/脏页是观察，未确定底层阻塞原因。
- comparison、numeric-comparison、comparison-summary：旧 urllib、未采用 socket.py 实验及最终少量导入探测的样本。旧命令最终成功不等于在 Docker 3 秒外层内成功；总执行时间包含 SSH/Docker，导入与探测分开。各组先后执行，没有同时控制宿主负载。
- targeted-tests、full-server、ruff-server、format-server、test-results：13 项新增 TCP 检查；固定 Git 导出构建的 ARM64 test 镜像中完整 491 项、代码/格式检查通过。唯一警告是既有 Starlette/httpx 弃用，不记作产品故障。
- wire-results：实际 runtime Docker 检查 200→503→200；延迟 3 秒仍以失败退出，含本机 exec 约 2.056 秒。不是只调用被测函数。自有容器已清理。
- build-result、runtime-source：77 份运行文件与 Git 提交逐一匹配，原76份业务文件未变，pytest 不在 runtime。归档 SHA 与 NAS 配置/文件层另行核对；Mac 清单 ID 不冒充 NAS 配置 ID。
- database-summaries：停机隔离副本与启动后所属容器 mode=ro 的37表行数/摘要。业务对照排除正常扫描活动列，具体为 business-comparison 的29张保护表、非扫描设置、目录配置及媒体非扫描列；两侧相同，观察结束又比对一次。没有发布原始数据库/设置值/媒体名称或路径；非扫描设置键也作摘要。
- deployment-summary、verification、startup-samples：完整 NAS/Mac 快照校验，原挂载/环境/限制/身份保持，schema0014/quick_check=ok，阅读默认只GET不覆盖。视频/封面/图片各只读1024字节并收到206。687包记录包括683个可浏览包和4个原空包；没有将历史视频总行数混作当前598条列表。
- health-watch：首次健康后同一容器378.34秒，24次真实定时检查全成功，0.235～0.352秒，重启0/OOM=false。6次业务采样同一新扫描任务：视频598/598保持完成，图包30→375、图片2211→18249；最后仍在扫描，没有额外扫描POST。根目录以序号记录，包问题只留计数，不发布私人资源标识。
- auth-cleanup、final：原16条登录记录保持，只撤销自有临时登录。完整快照与新旧镜像归档保留；清理精确NAS中转/解包路径后，同一容器仍healthy、直接健康200约0.026秒。
- cleanup：自有测试镜像和源码导出/归档清理，原四个本机服务的实际ID/healthy保持。apparent bytes是文件逻辑大小，不作磁盘实际释放量。未做全局Docker清理，签名/SDK/常用AVD/安装包与私有成对快照保留。

## 保留的失败与范围

新容器启动阶段一次探测退出1，随后健康；完整原日志保留，未因为观察等待而重复启动。备份更新会正常停止旧服务，原扫描按已有机制记为中断，启动后自动新全扫；观察期间的同一任务是新任务，不声称延续旧任务ID。

第一版 socket.py 实验7/12成功，未部署。准备脚本曾误向容器对象读取镜像RootFS字段，尚未停止/切换服务即失败；改为镜像inspect并沿用原临时登录后继续。宿主Python3.9不支持归档filter参数的导出尝试未进入构建，改从自有Git归档导出；证据导出键名失配仅重导既有结果，没有重演部署。test镜像在pytest作为PID1时没有API，其健康标记不当作服务失败。中间诊断均保留在本机私有目录。

6分钟有限样本不代表长期稳定性、手机或整个NAS性能。底层宿主压力原因未确认；没有真实媒体删除/恢复试验。客户端834项沿用其固定源码结果，本轮只重跑服务全集；45项完整验收、真实手机及#78/#89/#100等继续。未合并或正式发布。

CHECKSUMS.sha256 覆盖本目录其余全部文件。私有连接、凭据、数据库/完整快照与运行脚本不入库。
