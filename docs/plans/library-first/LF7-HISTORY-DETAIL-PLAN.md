# LF7 后续：永久删除原清单与逐页结果的历史读取

这是 PR #54 后的源码审计与待实施契约，不是完成证据。完整管理恢复已保存历史图，通用任务/成员可按原 graph 读取；以下专用页面仍需接线，不能据通用查询通过就开放正式 backup_v2。

## 当前实际差距

- `pack_operations_api.py` 的 `GET /pack-purge-requests/{request_id}`、`/pack-purge-plans/{identity}`、`/pack-purge-plans/{identity}/files` 与 `/pack-operations/{identity}/pages` 仍直接读取当前库实现。
- `PackPurgePlans.view/files` 读取当前计划和条目；files 会完整物化 manifest 中的 files 数组。`PackPurge.pages` 使用当前 PackPurgeStep / PackFileStep / ImagePack 关联。
- `MaintenanceTaskDetail` 对历史永久删除任务隐藏逐项图片结果入口；`PackPurgeResult` 自动创建当前网关，刷新可能 acknowledgeTask，仍带当前重试能力，不能直接复用为历史读取器。

## 下一段实现边界

历史读取始终明确原 graph（或精确解析原 epoch），先核对父任务的 ID/种类和原图归属，再在该图的只读数据库查询原计划、包条目、精确文件和图片/目录结果。原图缺失、类型错误、同 ID 跨图、错误父子关系均明确拒绝，不退回当前库或另一图。元数据包含 historical 与 graph_id，不代表媒体源字节仍存在。

文件 manifest 的分页在 SQLite JSON 查询中完成，有界投影返回请求页，避免为100条分页加载整个大清单。计划/包条目与页结果也按稳定顺序和总量分页。保留原摘要/路径/结果/错误，不把新代次的目录名或当前状态套入旧记录。

App 使用仅能读取历史任务、计划和结果的专用接口，不能 prepare、submit、retry、undo 或 acknowledge 当前命令。历史详情接入只读精确清单和逐页结果入口，沿用当前 Paper 尺寸及分页/筛选组件；原图缺失留在原详情显示错误，不跳入当前删除确认。连接/代次变化使旧读取失效，迟到结果不能覆盖另一历史任务。

## 必须补的检查

1. 同任务 ID 的两份图拥有不同原路径/页/错误，按指定 graph 准确返回；未知 graph/错误类型/跨父项不得回退。
2. 导出、完整恢复、连续恢复后原计划及永久删除逐页结果仍一致；所有读取不写当前管理库、源媒体、安全日志或执行队列。
3. 大 manifest 实际文件及 SQLite 有界分页，记录峰值与输入大小，明确 Python 分配量不冒充总 RSS。
4. App 历史入口、24/100项分页、未完成筛选、离页与迟到隔离、错误保留，当前删除流程回归。真实 Android 普通及小屏双倍字号核对截图/窗口/轨迹，确认历史页面完全不 POST 执行或结算。
5. 固定实现和原始证据入库、更新 #32/#24；其余命令强停、历史图片错误、全原型/目标设备等未完成范围仍单独记录。

正式改动前保持 App/服务端生产源码为 PR #53 的已验证树，PR #54 只增加真实强停补证。冻结原型和 production backup_v2 开关不随本计划变动。
