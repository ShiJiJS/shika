# LF5 图片、回执、后台与整包标签恢复专项

App实现为 `9ca6518`（基于9024f88），最终集成测试为 **aafccee**。三轮均使用同一实现与测试。API36专用Android模拟器 + 8761隔离FastAPI/SQLite和公开花卉图片；正式8760、真实NAS和原型未改。

| 顺序 | 逻辑尺寸/字号 | 测试执行结果 | 记录 |
| --- | --- | --- | --- |
| 1 | 360×740 / 2倍 | 通过，55秒 | [日志](01-large/android-test.log)、[宿主事件](01-large/host-events.json)、[哈希](01-large/proof.json) |
| 2 | 390×844 / 普通 | 通过，54秒 | [日志](02-normal/android-test.log)、[宿主事件](02-normal/host-events.json)、[哈希](02-normal/proof.json) |
| 3 | 390×844 / 普通 | 通过，60秒 | [日志](03-normal/android-test.log)、[宿主事件](03-normal/host-events.json)、[哈希](03-normal/proof.json) |

时间不含准备、编译与安装。每轮重置27包夹具，每包3张。触控由设备内Flutter集成测试注入；HOME与重新前台由宿主实际ADB执行，宿主事件各恰有一次。每轮归档8个状态的PNG、请求和独立故障记录，加日志、事件、APK与174份源码哈希。日志只去行尾空白并保留原始哈希，PNG没有裁剪或修图。

## 确认的行为

1. 两个标签的交集和名称搜索进入阅读；列表首批24项，完整固定范围为25包，另2包是反例。首张原图连续3次503后自动重试停止，最近为0、进度不存在。手动重试后实际图片首帧才opened。
2. 进度请求在真正执行前返回503，服务端revision不变。界面查询回执404，等待期间不自动PATCH；点击再次提交后沿用同一请求键哈希和expected_revision，仅落盘一次，第二页续读位置正确。
3. 下次进度由真实Reading模块写入完成，夹具消费实际200响应后替换为503。独立GET已读到第三页和新revision，客户端仍保持待确认；不能换包。点击查询，回执200解决状态，不额外PATCH。前后两种故障各有记录，不能用同一假失败代替。
4. 切回第二页纵拼、实际滚动产生未保存比例后，真正HOME退出前台；核对paused且保存完成，通过HTTP读回pageId/比例与新增revision。重新前台核对resumed、原范围及同一页/比例。另有[不推进假时钟的3尺寸组件回归](../lf5-reader-recovery-client/README.md)，证明生命周期回调本身发起保存，自动保存定时器不能代替它。
5. 阅读器中移除整包的第二个标签后，实际新查询只有24包；当前仍是原包原页/比例，原session与25个完整成员保持。查看范围队列得到全部25个原ID（含原首批之外的成员），不加入2个反例；手动下一包沿用原范围与自己的设置。返回仍是原标签来源和原查询，显示准确24条。

最后最近ID恰为实际阅读的两包，全流程只创建1次阅读session。标签修改后的元数据重读会重新确认当前实际显示首帧，不把这次确认说成另一包；没有把25个范围成员都计为实际阅读。

每轮return-faults.json的首3个进度记录必须为before/normal/after、状态503/200/503；前2条键哈希和revision相同，before未提交、after确实提交。图片前4次必须为503/503/503/200；所有阶段必须来自本轮ready之后，拒绝用旧截图补齐。请求快照没有鉴权头或请求体，故障记录只保存合成ID、键哈希与结果。

## 关键可见状态

- [图片错误](02-normal/recovery-image-error.png) / [手动恢复首帧](02-normal/recovery-image-ready.png)
- [回执不存在，显式重试](02-normal/recovery-unknown.png) / [已提交回执确认](02-normal/recovery-receipt.png)
- [后台后回到原页](02-normal/recovery-background.png) / [整包标签后仍在当前包](02-normal/recovery-tags.png)
- [原25包队列](02-normal/recovery-queue.png) / [返回24条结果](02-normal/recovery-return.png)
- [双倍字号图片错误](01-large/recovery-image-error.png) / [双倍字号未知结果](01-large/recovery-unknown.png)

主任务检查普通/双倍字号错误和回执截图，白色重试/跳过在深色画布可读；大字号说明与按钮自然换行，页码和实际范围仍可达。图片错误动作按已有白色阅读提示修正，界面比例和方向未重设计。返回列表截图可能仍含待加载封面，不把它们作为所有可见封面均解码完成的证明；完整视觉/动效仍由LF8验收。

本路径只覆盖503图片重试、两类未知进度、HOME生命周期、从标签交集移出当前包。其它错误码/跳过、断线、连接替换、同连接管理恢复、旧服务、强杀重启及所有组合仍待检查。没有测500页4K/8K真实解码、峰值PSS、延迟或真机/NAS。LF5/总任务继续开放；LF6快速整理、LF7设置/备份v2、LF8整体一致性仍需推进。

复跑：`bash scripts/dev.sh python3 scripts/run-client-connection-test.py --pack-recovery`；放大轮增加 `--workspace-viewport 360 --workspace-text-scale 2`。仅作用于既定AVD与8761可丢弃服务。
