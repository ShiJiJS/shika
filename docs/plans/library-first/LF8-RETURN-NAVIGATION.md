# 新版返回旧页：首轮源码修复

跟踪[#140](https://github.com/ShiJiJS/video_viewer/issues/140) / [草稿PR #144](https://github.com/ShiJiJS/video_viewer/pull/144)，基于[反馈规划#143](https://github.com/ShiJiJS/video_viewer/pull/143)。本段处理已复现的返回路径，Android正常包、手势/预测返回及其它组合仍待核对，issue不关闭。

## 复现和修复

新增交互检查实际点击设置中的媒体目录、回收站、备份与恢复、操作任务和服务连接，再调用系统返回。旧源码12d6ca67这五例均出现nav-browse旧入口，旧服务对照通过。不是只搜索字符串推断：原始失败明确找到正在显示的旧入口。

根因路径：管理页显示时，保留目录状态的MediaWorkspace被Offstage隐藏，但它的PopScope仍注册在同一ModalRoute上。一次返回里，隐藏页的回调先将目的地改到library；共享管理页的旧回调随后按这个新目的地判断为主入口，又执行go('browse')。两处回调先后改状态，最终显示旧页。

修改三处：隐藏workspace允许路由返回且忽略返回回调；新版共享管理页返回明确到设置；新版导航边界将browse归一到library，连接状态从旧browse进入新版时也归一。旧服务仍用原返回逻辑，既有主入口、目录状态与排布保持。

五类管理页现在先回设置，再回媒体库，不创建MovieStage；旧服务设置仍返回旧浏览页。相关四入口、预览退出共20项通过，完整客户端797项及analyze通过。首次修后测试还因设置列表保留滚动位置，找不到被滚出构建窗口的“服务连接”而失败；改为验证真实设置页标题后通过，不删除防止旧入口出现的断言。该中间日志留在本机，没有计作通过。

## 后续边界

- 仍需普通Android包的多轮系统/手势返回、真实内容/全屏/标签结果/选择和弹层、冷启/后台重开及连接变化；同时检查来源锚点、页码和不自动播放。
- 目前是交互组件和旧服务测试替身证据，不是用户手机这次偶发情况唯一原因已完全排除，也不是已发布修复。
- NAS服务、真实媒体、服务源码和原型未改。已交付的preview.16/rollback.16保持；本段尚未生成新的手机更新。
- 其它五张反馈票继续按规划推进；不把#140的局部修复当六票全部完成。

[固定测试日志](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-return-navigation/README.md)保存修前失败、修后相关检查及本段完整客户端结果；没有修改旧历史manifest。
