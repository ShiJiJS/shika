# LF6 新菜单接线后的原生标签名称回归

App实现 **8efae13**，最终原生测试 **e6b34c6**。API36专用emulator-5554、8761隔离真实FastAPI/SQLite和公开花卉图包。正式8760、真实NAS、冻结原型未修改。此处测试名里的delete是**图包标签删除**，没有执行图包永久删除，不作为LF6整包删除的原生完成证据。

| 轮次 | 逻辑尺寸/字号 | 实际测试 | 证据 |
| --- | --- | --- | --- |
| 01 | 360×740 / 2倍 | 通过，55秒 | [日志](01-large/lf4-pack-names-android-test.log)、[事件](01-large/lf4-pack-names-host-events.json)、[校验](01-large/proof.json) |
| 02 | 390×844 / 普通 | 通过，55秒 | [日志](02-normal/lf4-pack-names-android-test.log)、[事件](02-normal/lf4-pack-names-host-events.json)、[校验](02-normal/proof.json) |
| 03 | 390×844 / 普通 | 通过，55秒 | [日志](03-normal/lf4-pack-names-android-test.log)、[事件](03-normal/lf4-pack-names-host-events.json)、[校验](03-normal/proof.json) |

三轮之间App和集成测试源码逐文件不变；每轮记录独立APK SHA，未把分别生成的debug APK说成同一个二进制。每轮重置专用可丢弃服务，四个阶段截图/请求均来自本轮开始之后，各阶段宿主事件恰有一次、无宿主错误。运行与校验脚本见`run-checkpoint.py`，仓库定位改为git根目录，重跑仍使用现有`run-client-connection-test.py --pack-names`。

实际从卡片更多菜单进入整包标签，验证首50项之外的既有标签、受控503失败后保留选择/明确重试、保存后从同一卡片重新进入并读回两个选择、重命名后卡片更新、删除图包标签后卡片更新、同名视频标签始终独立。真实请求轨迹必须按序出现名称解析503和200。

代表画面：[双倍字号失败/重试](01-large/lf4-pack-names-pack-names-retry.png)、[普通字号保存后读回](02-normal/lf4-pack-names-pack-names-saved.png)。主Agent检查这两处实际画面，字号/选项换行与既有画廊比例保留；错误英文来自故障夹具消息，不是新增产品文案。完整视觉与普通整包回收/撤销、阅读器快速整理原生验收仍待继续。

## 失败记录与修正

首次8ef轮在新面板进入动画尚未完成时点击关闭，计算位置y=780超过740视口，导致后续卡片被面板遮挡。[原日志](failed-8ef-large/lf4-pack-names-android-test.log)和[超时画面](failed-8ef-large/lf4-pack-names-error.png)保留；未关闭命中警告或放宽断言。

ce26轮补了转场等待，但全局idle可能在新编辑器尚未构建时短暂满足，名称解析的503状态尚未显示就开始断言。[原日志](failed-ce26-large/lf4-pack-names-android-test.log)和[实际请求轨迹（含名称解析503）](failed-ce26-large/failure-trace.json)保留。e6b34c6改为等目标route进入完成且可命中、名称失败的重试按钮可操作、每次明确重试完成，以及已保存的选择实际读回。原名称/独立类型/缺失与请求状态断言全部保留，之后同一实现连续三轮通过。

本专项没有验证Android操作记录跨进程重建、整包快速整理/永久删除、管理恢复或真实NAS；不据此关闭LF6或宣称整个原型验收完成。
