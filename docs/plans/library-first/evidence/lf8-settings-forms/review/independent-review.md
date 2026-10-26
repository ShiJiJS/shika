# LF8 设置与表单独立视觉评审

[问题 1 / 优先] 横屏服务器连接 / `settings-connection-keyboard.png`：数字键盘打开后，端口输入框及光标完全离开可见区 → 键盘稳定出现后，当前输入值和光标自动进入剩余窗口。
[问题 2 / 规范偏离] 连接、目录编辑、阅读偏好：浮动标签＋浅绿填充描边框替代冻结参考的外置标签和开放设置行 → 恢复参考中的表单层级、颜色语义和主要比例，同时保留真实能力及明确保存。
[提升 1 / 精致度、减法] 目录类型冲突：常驻说明与红色错误重复讲同一限制 → 错误出现时只保留一份完整、可操作的限制解释。
[提升 2 / 精致度] 大字目录状态行：时间前的分隔点孤立在第二行 → 允许真实状态、时间清楚换行，不让分隔符成为独立行首装饰。
[动效] 没看到完整手势录屏；本轮不判定出入场、键盘过渡或保存反馈的运动质量。

## 依据与范围

采用 reviewer-manual.md 的「存量已有界面润色评审」，只对齐现有规范，不评分。版本由主 Agent 交接为 **711c9f4**。读过 LF7-DEFAULTS-DESIGN.md 与 LF7-ROOTS-MISSING-DESIGN.md；只查看原生 PNG、冻结参考 PNG，以及 metrics.json / 参考尺寸 JSON 的几何信息，没有读取生产代码、测试日志、SQL、历史评审结论或请求记录。

当前图视口：普通 390×844 / DPR 3 / 字号 1；横屏 844×390 / DPR 3 / 字号 1；大字 360×740 / DPR 3 / 字号 2。参考为同逻辑尺寸的普通、横屏浏览器截图。原生系统状态栏与手势区造成的位移已与应用内容区分；未把地址、目录名、排序、时间或原型虚构数据的差异列为视觉缺陷，也未通过拉伸原图制造接近效果。

本轮覆盖连接管理、媒体目录管理及编辑、默认播放顺序、阅读偏好、共享短面板与键盘窗口。不外推媒体库入口范围、持久化、取消零写入、原请求核对或旧服务兼容已经通过。默认值明确保存属于成文规范，参考里的自动保存文案不能覆盖此要求。

## 问题（按影响排序）

### 1. 横屏连接输入时，看不见正在修改的端口

证据：`/tmp/lf8-settings-v5-final-landscape/settings-connection-keyboard.png`。数字键盘占据下方后，上方只显示共用服务说明、服务地址标签和地址框上沿，端口及光标完全不可见。普通与大字同状态中端口均能看见，因此这是横屏极短窗口中的适配缺口。几何数据也显示窗口高 390、键盘 inset 210；截图可见区内没有端口框。

影响：用户按数字键时无法目视核对输入，很容易继续在不可见对象上编辑。这里只断言当前捕获状态的焦点不可见，不据静态截图断言无法手动滚回。

目标与验收：相同横屏窗口打开端口键盘，等待系统键盘稳定后，无需用户先找滚动位置就能看见端口标签、当前值和光标；从地址、端口、口令依次切换焦点也不被遮住。标题可以在极短窗口里随正文让位，不要求所有字段与保存按钮同时装进首屏。不要通过缩小全局字号、遮掉错误或去掉明确保存来解决。

### 2. 共享表单与冻结 Paper 组件语言仍有明显偏离

证据：普通 `settings-connection.png`、`settings-root-add.png`、`settings-reader.png`，以及对应横屏图；对照参考 `normal-connection.png`、`normal-root-form.png`、`normal-defaults.png`。

冻结参考的文字输入使用外置小标签、接近白色的输入面；内容类型、翻页方向是开放画布上的设置行，右侧给当前值。现状把文字输入、类型、方向、图片适配均呈现成浅绿填充的浮动标签描边框；空输入的名称/挂载目录标签落在框中，已有值时标签又移到边框缺口。结果是阅读偏好的后半部与录入表单同形，浅绿面积也从「已选模式」扩展到了普通字段。

这是参考还原的组件差异，不是建议改品牌。几何上，普通当前文字输入为 50dp 高，参考可见输入约 42dp；当前阅读方向也成为 50dp 输入框，而参考为紧凑开放行。正常字号的双模式卡约 97dp 高，与参考基本一致，不能把模式卡也一并压缩。

目标与验收：同视口并排看，文本标签持续可见，输入面与选中态分工明确；类型、方向和图片适配回到同一 Paper 设置行语言；保留图片适配、目录类型/启停、错误、真实状态、显式保存和关闭草稿出口。对照时扣除系统安全区和额外真实说明，再比较组件本身，不要求为了首屏全显示删掉业务信息。

## 提升

### 1. 类型冲突说明可以合并，保留错误本身

普通与横屏 `settings-root-conflict.png` 中，内容类型下方有「已有内容的目录不能直接更改类型，请新建正确类型的接入目录」，保存按钮上方又有近同义的红色错误。大字下两份解释占据明显篇幅，用户在同一表单中读到两次相同原因。

目标：正常编辑仍保留类型限制提示；冲突发生后由一份完整错误承担原因与下一步，不重复占位。可以精简常驻说明或在错误出现时合并展示，但不能删掉服务端拒绝的真实反馈，也不能把错误写成成功。验收看三种视口的冲突状态：仍能读到不能改类型、应新建目录，草稿身份/内容与保存出口仍清楚。

### 2. 大字状态串可改善换行秩序

大字 `settings-roots.png`、`settings-dark-roots.png` 中，「图包 · 已启用 · 可访问」下一行以「· 10/26 18:12」开头。类型、启停、可访问和时间都是有用信息；问题是串联分隔符跟着时间被折到行首。

目标：在保持真实状态与时间的前提下组织自然换行；时间可以独占一行，但不以孤立的分隔点开头。验收用 360×740 / 字号 2，看两类目录、明暗色均能逐项读清，不用省略号吞掉管理身份。

设计感：既有开放列表、细分隔、衬线标题和阅读模式双卡已形成一致 Paper 方向，没有依据要求另换布局或添加装饰。精致度的主要提升就是上面两项与表单统一，不追加面板或数据。

动效：静态截图能区分模式选中、开关、草稿值和错误，但不足以判定动作衔接。没看到完整手势录屏，不提出凭空的动效缺陷，也不写「动效通过」。

## 可删减文字与不应删的内容

- 类型冲突状态中，上下两份同义限制解释可合并，保留一份完整错误与下一步。
- 目录编辑中「填写媒体服务内的挂载路径。扫描包含子目录，不修改源文件位置。」可收紧措辞，但「服务内挂载路径」「含子目录」「不改源文件」三层含义都应保留。
- 未发现需要直接删除的「示例」「仅供示意」或空泛装饰文案。
- 不删当前服务默认值的作用范围、已阅读包独立偏好、目录启停后保留记录、口令不进备份的说明；不把真实可访问状态或时间替换为笼统套话。

## 已成立并应保留

连接与目录保持全高度管理页；编辑、播放顺序及阅读偏好使用全宽底部面板。横屏短面板不再缩成居中的窄弹窗，左右 20dp 主锚线也连续。普通阅读双模式卡的尺寸与冻结参考接近，浅选中和细描边能清楚区分状态。大字与暗色中标题、主要按钮和模式名称仍可辨认。

普通和大字目录表单里，显式保存按钮与关闭按钮可见；横屏极短键盘时目录当前名称与光标可见，关闭仍在标题右侧。横屏键盘下保存暂不在同一屏不能单凭截图判为不可达，仍需实际滚动/收起键盘操作验证。错误图保留草稿与真实拒绝原因，不会以视觉简化抹掉管理语义。

## 实际查看的图片清单

以下均用 view_image 实际查看，不以文件名推断内容。

冻结参考 `/tmp/lf8-settings-reference/`（11 张）：
`normal-settings.png`、`normal-connection.png`、`normal-roots.png`、`normal-root-form.png`、`normal-defaults.png`、`normal-playback.png`；`landscape-connection.png`、`landscape-roots.png`、`landscape-root-form.png`、`landscape-defaults.png`、`landscape-playback.png`。

当前普通 `/tmp/lf8-settings-v5-final-normal-1/`（19 张）：
`settings-home.png`、`settings-connection.png`、`settings-connection-keyboard.png`、`settings-connection-invalid.png`、`settings-roots.png`、`settings-root-add.png`、`settings-root-edit.png`、`settings-root-keyboard.png`、`settings-root-invalid.png`、`settings-root-conflict.png`、`settings-playback.png`、`settings-reader.png`、`settings-reader-draft.png`、`settings-scan-details.png`、`settings-dark.png`、`settings-dark-roots.png`、`settings-dark-reader.png`、`settings-reader-saved.png`、`settings-reader-restored.png`。

当前大字 `/tmp/lf8-settings-v5-final-large/`（16 张）：
`settings-home.png`、`settings-connection.png`、`settings-connection-invalid.png`、`settings-connection-keyboard.png`、`settings-roots.png`、`settings-root-add.png`、`settings-root-keyboard.png`、`settings-root-edit.png`、`settings-root-invalid.png`、`settings-root-conflict.png`、`settings-playback.png`、`settings-reader.png`、`settings-reader-draft.png`、`settings-dark-reader.png`、`settings-dark-roots.png`、`settings-dark.png`。

当前横屏 `/tmp/lf8-settings-v5-final-landscape/`（12 张）：
`settings-connection.png`、`settings-connection-invalid.png`、`settings-connection-keyboard.png`、`settings-roots.png`、`settings-root-add.png`、`settings-root-keyboard.png`、`settings-root-invalid.png`、`settings-root-conflict.png`、`settings-playback.png`、`settings-reader.png`、`settings-dark-reader.png`、`settings-dark-roots.png`。

未使用旧原生 baseline 图作为现状依据。本报告不包含功能通过结论、HTML lint 结论或动效通过结论。

保留：Paper 留白、既有衬线标题、开放目录列表、全宽短面板、清楚的模式选中态，以及显式保存/真实错误/管理对象身份。
不评分；当前优先修正横屏连接的焦点可见性，再统一与冻结参考偏离的表单语言。

---

# 第二轮复核（进行中，c60b12d）

本轮只复核首轮冻结的 2 个问题、2 个提升，不扩展首轮清单、不评分。当前先完成横屏 844×390 / DPR 3 / 字号 1 的图片检查；普通、大字将由主 Agent 通知到齐后补齐，以下不作为整轮最终结论。

已实际查看 `/tmp/lf8-settings-v8-final-landscape/` 的 12 张 PNG：`settings-connection-keyboard.png`、`settings-connection.png`、`settings-root-add.png`、`settings-root-conflict.png`、`settings-reader.png`、`settings-dark-reader.png`、`settings-root-edit.png`、`settings-root-keyboard.png`、`settings-roots.png`、`settings-connection-invalid.png`、`settings-root-invalid.png`、`settings-playback.png`。

- 问题 1：横屏截图中已修好。端口标签、输入框和值 `0` 已进入数字键盘上方可见区，框周围有焦点描边；当前捕获帧未出现光标竖线，但焦点对象与值均可核对，不把光标闪烁帧当成新的缺陷。
- 问题 2：横屏已看到外置标签、浅白文字输入与开放类型/方向行，已消除首轮指出的大框化与浅绿填充差异；最终需一并查看普通与大字后判定。
- 提升 1：部分修好。常驻类型说明已经移除，但红色错误内部仍出现「请新建接入目录。请新建正确类型的接入目录。」的同义重复。保留最后一句、去掉前一个「请新建接入目录」即可满足原清单；这是原提升项的剩余部分，不另立新问题。
- 提升 2：等待大字目录截图，暂不判定。

截至横屏检查，未新增首轮清单外的问题。动效判断边界保持不变。

补充大字检查（360×740 / DPR 3 / 字号 2）：实际查看 `/tmp/lf8-settings-v8-final-large/` 的 `settings-roots.png`、`settings-dark-roots.png`、`settings-connection.png`、`settings-connection-keyboard.png`、`settings-root-add.png`、`settings-root-edit.png`、`settings-reader.png`、`settings-dark-reader.png`（8 张）。

提升 2 已修好：两类目录都把真实时间放到下一行，行首没有孤立分隔点；明暗色一致。问题 2 的大字结果成立：标签持续外置，白色输入与选中模式的浅绿分工清楚，类型和方向采用开放设置行；字号放大后方向变为上下排，但标签、值与箭头均可辨认。大字正文下方内容需要滚动属于既定约束，不据首屏未全部显示判为缺陷。大字端口键盘图中端口值及聚焦描边清楚，原问题没有迁移到此视口。

补充普通检查（390×844 / DPR 3 / 字号 1）：实际查看 `/tmp/lf8-settings-v8-final-normal-1/` 的 `settings-connection.png`、`settings-connection-keyboard.png`、`settings-root-add.png`、`settings-root-edit.png`、`settings-root-conflict.png`、`settings-reader.png`、`settings-reader-draft.png`、`settings-dark-reader.png`（8 张）。

问题 2 已修好：普通界面的文字输入具有持续可见的外置标签、浅白输入面，内容类型、默认方向和图片适配是开放设置行；三种视口共同消除了原清单指定的浮动标签/浅绿大框偏离。正常阅读双模式卡与选中态保留，图片适配、明确保存、关闭出口及真实错误也仍在。普通端口键盘图中值与光标可见。

c60b12d 的冻结清单判定：问题 1「修好」；问题 2「修好」；提升 1「部分」；提升 2「修好」。未发现需要另立的、由此次修改新引入的问题。整单尚未关闭，等待下一版本仅针对提升 1 的文案复核。此处仍不提供功能、持久化或动效通过结论。

---

# 最终同清单复核结论（81b598f）

最终版本由主 Agent 标明为 **81b598f**；本次只复核原提升 1 的最后一处重复文案。原问题 1、问题 2、提升 2 沿用上文已明确记录为 c60b12d 的复核结果；不把早先图片改称最终版本证据。主 Agent 交接说明最后一版仅改类型错误的重复下一步，未改变其余画面。本报告不读取源码核验该说明，也没有开启新一轮清单。

最终实际输入为以下三张原生 PNG，均已用 view_image 查看：

- `/tmp/lf8-settings-v9-final-landscape/settings-root-conflict.png`：844×390 / DPR 3 / 字号 1。
- `/tmp/lf8-settings-v9-final-large/settings-root-conflict.png`：360×740 / DPR 3 / 字号 2。
- `/tmp/lf8-settings-v9-final-normal-1/settings-root-conflict.png`：390×844 / DPR 3 / 字号 1。

三种视口的冲突状态均只显示一份红色解释：「已有内容的目录不能直接更改媒体类型，请新建接入目录」。上方常驻类型提示不再重复出现，错误内部也没有再次追加「请新建正确类型的接入目录」。拒绝原因、下一步与保存出口保持清楚，普通图仍能核对草稿名称、路径和类型。大字下需滚动查看前面的字段属于此前已接受的正文滚动边界。

| 冻结条目 | 判定 | 实际视觉依据版本 |
| --- | --- | --- |
| 问题 1：横屏连接端口被键盘遮住 | 修好 | c60b12d：v8 横屏键盘图，普通及大字同状态补查 |
| 问题 2：共享表单偏离 Paper 参考 | 修好 | c60b12d：v8 普通、横屏、大字与阅读暗色图 |
| 提升 1：类型限制与错误重复 | 修好 | 81b598f：v9 三种视口的冲突图 |
| 提升 2：大字状态行首孤立分隔点 | 修好 | c60b12d：v8 大字目录明暗色图 |

原冻结的 2 问题 / 2 提升均已闭合；本次修改未观察到需要另立的新问题。此结论仅针对上述视觉清单，不等同于旧服务、保存/取消写入、持久化、原请求核对、完整手势或全 App 验收通过。未看到完整手势录屏，动效质量继续不判定。不评分。

保留：Paper 留白与既有衬线标题、开放设置行、全宽短面板、模式选中态，以及明确保存、真实拒绝与管理对象身份。
最终结论：冻结视觉清单已全部修好，版本和实际查看原图的边界如上。
