# LF7：恢复代次与旧写入隔离

[Draft PR #50](https://github.com/ShiJiJS/video_viewer/pull/50)，基于 #49。[协议及完整剩余范围](../../LF7-AUTHORITY-DESIGN.md)。固定源码 `403b5a70e4055b14156a537dbb2d25bd99915305`，本目录保留完整源码SHA、原始结果及诊断。运行 `bash scripts/dev.sh python3 docs/plans/library-first/evidence/lf7-authority/verify.py` 核对。

服务端全集375项通过（626.43秒），包括新增17项代次检查；全量video_viewer/migrations/tests Ruff及Python编译通过。只有一条既有Starlette测试客户端弃用警告。进程/文件/图包恢复、真实50MiB图片流取消及备份文件/历史包均在同次全集回归，不拿以前的通过数量累加。本轮没有改App或重跑客户端/Android。

实际HTTP覆盖显式和旧缺省代次、受理检查后恢复提交再进入写库（两个固定交错均拒绝、目录新增0）、写锁内先提交再轮换、另一Database连接的SQLite事务锁、令牌等待时撤销、旧导入不受理、非法/重复头、自身退出、已执行SQL的回滚、丢失权威不自动重授、0013升级及重启保留原令牌签发代次。检查既有真实v1恢复只创建1个恢复任务，旧POST被拒绝，原GET/前快照/源媒体保持，代次及令牌字段不进入v1/v2文件。

两处真实HTTP/子进程SIGKILL是现有v1恢复：snapshot_written和after_replace_before_commit。后者已在同一事务内实际flush了新代次。提交前旧数据/旧代次仍可见；重启恢复完成后代次更新，旧POST409，原GET可查、媒体SHA保留、历史操作重放0。完整标志见proof.json；这些不是新v2完整恢复事务或断电证明。日志中其它SIGKILL/流媒体指标来自既有回归，不混算为新增代次用例。

诊断保留旧用例未明确采纳恢复后的新代次、能力列表旧期望及新增测试缺Setting导入的失败。修正测试输入/断言而没有放松旧令牌写入保护；升级保留数据仍逐原列比较，新0014只给不导出的令牌表加字段。最终完成证据只用固定源码的375项全集。

公开info已提供management_authority/代次，数据库0014；v2逻辑管理图仍0013，因为新字段完全不在管理文件中。公开backup_v2仍关闭。App不可变网关代次、跨设备变化后旧日志/选择历史化、迟到响应失效及无口令承接仍待接；旧App恢复后继续写需重新验证连接。完整v2预约/前快照/根映射/物理删除真相/替换/正式历史引用及孤立清理、历史路由/任务协议、有界传输与系统选择器继续。LF7/#32、总任务/#24、LF8开放；原型独立未改，树SHA见environment.json，未改SDK/正式8760/真实NAS或发布APK。
