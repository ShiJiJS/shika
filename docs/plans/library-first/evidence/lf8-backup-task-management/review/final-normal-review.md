# LF8 备份与操作任务：普通竖屏最终静态复核

复核依据：[初版冻结清单](initial-normal-review.md)的问题 1–2、提升 1–2。沿用“存量已有界面润色评审”：不评分、不增加改版方向。交接版本为 e10bbbc，390×844 / DPR 3、text 1，安全区上 47.6667dp / 下 24dp；这些运行条件来自交接，未读源码或日志核验。

## 冻结清单结论

- [问题 1：静态目标已达成] 取消正文改为“保存已取消，可在操作任务下载原备份”，成功正文改为“备份已保存到所选位置”；两者不再共用“备份内容已下载”，且与各自底部提示一致。
- [问题 2：静态目标已达成] 格式错误图仅页头下保留一次“备份不是有效的 JSON 文件”，介绍下逐字副本已删除；“选择备份文件”行仍可见。
- [提升 1：静态目标已达成] 恢复预览中确认框已经移到说明前，组成一行，完整确认措辞保留，阅读顺序与冻结参考一致。
- [提升 2：浅色静态目标已达成；暗色证据有限] 列表“全部”、详情“全部”、历史详情“未完成”的选中填充、轮廓及勾号已呈现相同 Paper 读法，旧版详情更亮的浅绿填充差异消失。暗色列表自身一致、清楚；本组没有暗色详情，不扩大为暗色跨页统一已验证。

在这 13 张普通竖屏截图可见的范围内，冻结四项没有剩余的静态修正项。

## 逐项证据与边界

### 问题 1：状态文案

亲看 `lf8-management-management-backup-cancel.png`、`lf8-management-management-backup-saved.png`。正文独立可读出“未保存 / 已保存”的结果；取消图还保留原备份的补救说明，成功图明确保存到所选位置。当前截图不再需要靠“已下载”和“已取消”之间的技术区别解释终态。

该结论只针对文案。未验证服务内容获取、本机落盘、取消是否生效，也未等待底部提示消失；正文已经提供持续状态的位置和表述。

### 问题 2：单次格式错误

亲看 `lf8-management-management-backup-error.png`。同一次错误只在页头下警示条显示一次，真实原因完整保留，正文恢复为正常介绍、操作行及恢复限制。错误条的关闭控件仍可见；关闭后的状态保留策略没有截图，不认证关闭后的行为或校验协议。

### 提升 1：确认框与说明

亲看 `lf8-management-management-restore-preview.png`。确认框已前置，说明“我知道恢复会替换现有管理数据”完整可见；摘要、两组外置目录标签、原目录、恢复限制和底部动作均保留。按初版冻结的“顺序与局部还原”目标可关闭该项，不新增间距方向。

`lf8-management-management-restore-keyboard.png` 中键盘、当前焦点目录字段及底部动作可见，确认行不在该帧视野内。该帧不能证明确认行可滚达、键盘避让过程、点击区域或未勾选不提交。

### 提升 2：列表与详情筛选

亲看 `lf8-management-management-list.png`、`lf8-management-management-pending.png`、`lf8-management-management-detail.png`、`lf8-management-management-historical.png`、`lf8-management-management-paged.png`。各页选中项均为相同的浅橄榄底色、轮廓和勾号；未选项保持纸色，列表五类状态与详情子项筛选均保留。这里是视觉比较，没有从截图反推精确色值或共享组件实现。

亲看 `lf8-management-management-dark.png`，暗色列表的选中态、次级文字与分隔线仍清楚。暗色详情、暗色恢复不在本组，留作证据边界，不另生成方向或推断问题。

## 逐张亲看记录

本轮实际打开并亲看下列 13 张，目录均为 `/tmp/lf8-management-final-normal/`。原生大图由查看工具缩放显示；未读取同目录的请求、窗口文本或日志。

| 图片 | 本轮观察 |
| --- | --- |
| `lf8-management-management-backup.png` | Paper 页头、开放操作行、v1 视频范围与恢复限制仍在；不认证备份能力。 |
| `lf8-management-management-backup-cancel.png` | 取消正文与提示一致，支持问题 1 关闭。 |
| `lf8-management-management-backup-saved.png` | 保存成功正文与提示一致，支持问题 1 关闭。 |
| `lf8-management-management-backup-error.png` | 同次格式错误仅一处，重选文件行可见，支持问题 2 关闭。 |
| `lf8-management-management-restore-preview.png` | 确认框前置、完整措辞与既有恢复信息保留，支持提升 1 关闭。 |
| `lf8-management-management-restore-keyboard.png` | 焦点字段、系统键盘及底部动作可见；确认行在此帧不可见，不认证滚动。 |
| `lf8-management-management-list.png` | 选中态与详情一致；名称、状态、数量、日期及分隔线可辨。 |
| `lf8-management-management-pending.png` | 选中态一致；本机待核对与历史只读文字保留。 |
| `lf8-management-management-detail.png` | 子项筛选已与列表统一；任务编号、完整路径及子项状态仍可读。 |
| `lf8-management-management-historical.png` | 选中态统一；历史只读说明、空未完成结果保留。 |
| `lf8-management-management-paged.png` | 选中态一致；第 2/2 页、总 27 条及当前记录可见；不认证翻页行为。 |
| `lf8-management-management-dark.png` | 暗色列表层级清楚；只覆盖列表当前帧。 |
| `lf8-management-management-task-backup-saved.png` | 原备份下载入口、前往备份入口与保存提示保留；不认证操作和文件结果。 |

## 总体证据边界

- 只复核冻结四项，未更换色板、字体、导航或布局方向，未把多条真实任务按单条参考压到相同总高度。
- 当前仍为 v1 视频备份截图。没有为匹配完整原型而要求加入图包或 archive 能力承诺；v2 完整 archive 稍后补图另记。
- 大字、横屏、长路径极端换行与完整 archive 的 8 张证据尚未提供，本文件不提前通过这些范围。
- 未读实现、测试、请求或日志，未操作设备、服务和原型。没有 HTML lint 或录屏，未认证协议、禁用点击、滚动、手势、导航与动效。未看到动效，不作动效完成结论。

保留：Paper 开放操作行和衬线页头；真实路径、原任务 / 原备份入口及历史只读说明。

不评分；普通竖屏冻结四项的可见修正完成，未覆盖范围继续按证据边界补审。
