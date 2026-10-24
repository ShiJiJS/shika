# LF5 阅读操作专项：同实现连续三轮

实现为 `3f693be` / `9024f88`，三轮均在 **9024f88** 上运行，期间没有修改App、服务或集成测试。API36专用Android模拟器 + 8761隔离FastAPI/SQLite，公开花卉图片240×360。正式8760和真实NAS未改。触控事件通过运行在设备上的Flutter集成测试注入；返回键由宿主实际ADB `KEYCODE_BACK` 发送，不直接调用leave。

| 顺序 | 逻辑尺寸/字号 | 测试执行结果 | 原始记录 |
| --- | --- | --- | --- |
| 1 | 360×740 / 2倍 | 通过，46秒 | [日志](01-large/android-test.log)、[宿主事件](01-large/host-events.json)、[哈希](01-large/proof.json) |
| 2 | 390×844 / 普通 | 通过，49秒 | [日志](02-normal/android-test.log)、[宿主事件](02-normal/host-events.json)、[哈希](02-normal/proof.json) |
| 3 | 390×844 / 普通 | 通过，55秒 | [日志](03-normal/android-test.log)、[宿主事件](03-normal/host-events.json)、[哈希](03-normal/proof.json) |

时间不含Docker准备、编译与安装。每轮重置专用27包夹具，每包3张，所有真实操作走鉴权接口与实际图片首帧。每轮proof包含APK、172份源码和全部产物SHA-256；宿主事件必须无错误并恰有4次android-back。PNG为ADB原始截图，日志只去行尾空白，保留原始哈希。

## 完整路径

进入首包后按住拖动约四分之一页，断言当前位置在0与1之间，松手吸附回原页。LTR实际完整滑动3次，切换本包方向为RTL后反向滑动2次；每次等当前首帧并保存，再独立GET核对pageId。

在RTL第二页实际双指捏合放大，断言仍是第二页；双击复原，再双击放大并拖动画面，断言图片变换大于1.5且不翻页。第1次Android返回只复原缩放，随后实际RTL往返再滑2次，证明恢复可翻页。进入沉浸，工具隐藏；第2次返回只显示工具并保持同一张。

设置铺满宽度，实际纵向拖动当前图片，保存非零页内比例；第3次原生返回退出，独立GET核对落盘pageId/比例，重新点卡片续读。RTL/宽度适配/第二页及比例保留。切为纵拼并开启间距（冻结默认为不留间距），同一图片与页内比例保留；手动下一包仍在原27包固定范围和原session，新包保持自己的横翻/LTR/完整适配/无间距默认。第4次原生返回退出，最终最近为2包，创建会话2次、实际opened3次；翻页、缩放和预加载没有额外opened。

设备实际打印touchSlop=8.0；组件回归显式使用相同阈值。此次发现并修正单指被缩放识别器截获，以及较低阈值下父层抢走双指、拖动时子树忽略第二指的问题。当前[完整197项客户端/专项组件记录](../lf5-reader-controls-client/README.md)与本目录分开保存。

## 可见状态与边界

- [RTL第二页](02-normal/controls-rtl.png) / [放大后拖动](02-normal/controls-zoom.png) / [沉浸](02-normal/controls-immersive.png)
- [宽度适配滚动](02-normal/controls-width.png) / [重开保留位置](02-normal/controls-reopen.png) / [纵拼同页](02-normal/controls-vertical.png)
- [下一包独立默认](02-normal/controls-next.png) / [返回库](02-normal/controls-return.png)
- [双倍字号RTL](01-large/controls-rtl.png) / [双倍字号宽度适配](01-large/controls-width.png) / [双倍字号纵拼](01-large/controls-vertical.png)

主任务查看最终普通字号缩放/沉浸/重开和双倍字号RTL/宽适配/纵拼截图，工具比例、来源/页码和安全区沿用Paper/P2，没有改变冻结原型或另选视觉方向。此次为交互修正，沿用既有阅读器视觉评审；截图不代替手势时序断言，也不代替LF8动作录屏和完整原型一致性检查。

该路径不覆盖整包标签编辑后固定范围、单页错误/未知保存、后台/连接/恢复和旧服务的完整组合；没有测500页4K/8K、峰值PSS、翻页延迟或真机/NAS表现。LF5和总任务继续开放，快速整理LF6、完整设置/备份v2 LF7与整体验收LF8仍待完成。

复跑：`bash scripts/dev.sh python3 scripts/run-client-connection-test.py --pack-controls`；放大轮增加 `--workspace-viewport 360 --workspace-text-scale 2`。仅允许作用于既定AVD和8761隔离夹具。
