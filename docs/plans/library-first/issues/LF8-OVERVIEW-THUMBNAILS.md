属于#24/#33的PKG-03／READ-01及相关UI，发现于[PR #82](https://github.com/ShiJiJS/shika/pull/82)的实际原生图包总览。

当前开发状态：最新阶段：[总览容量与跨页 PR #85](https://github.com/ShiJiJS/shika/pull/85)，24项相关检查、同生产／跨页驱动三轮33点及六图回归8点通过，[207输入只读复核](https://github.com/ShiJiJS/shika/blob/codex/lf8-overview-pagination/docs/plans/library-first/evidence/lf8-overview-pagination/README.md)。#83已补24→6→24、排队／在途／清单取消及明确第30页写入边界，保留草稿合并／终验状态；#24/#33继续内容页强停恢复及其余验收。

最初在c994273普通390×844公开夹具截图看到两张503后的“重试”。复查相同请求记录，随后nav-device-back阶段各有200，旧代码本已有400／800ms两次退避；修正此前“没有自动恢复”的初判。本项重点为真实成功读回、上限和关闭／分页／身份变化后取消。主图已解码与范围／页码正常，仍按原导航证据边界保留。

[原生总览图](https://github.com/ShiJiJS/shika/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/nav-library-pack-panel.png)／[请求记录](https://github.com/ShiJiJS/shika/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/requests.json)（phase=nav-library-pack-reader的两个GET /pages/{id}/thumbnail 503）／[固定源码边界](https://github.com/ShiJiJS/shika/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/README.md)。全部是公开生成样本，未访问私人NAS内容。

原始要求（本轮完成范围及剩余项见文末）：

- 对临时忙碌响应增加有限次数／退避的自动重试，成功后原位显示真实缩略图；离开面板、换页或资源身份变化后停止旧请求／计时器。
- 持续失败达到上限后保留现有手动重试，手动恢复实际读回同一页；不得无限请求，401／403等鉴权错误继续走既有流程。
- 总览加载和重试不写最近／阅读进度，不改变当前包、页码、阅读模式或固定范围。
- 保留原型布局、大小比例和既有“重试”形态；补有意义的组件回归、专用夹具临时失败／持续失败／关闭后取消的原生证据。

不操作正式8760、NAS、私人文件或默认凭据，不发布APK；本项完成后更新#33／RESULTS.md的PKG-03，整体验收保持独立。

## 2026-10-27：总览缩略图有界恢复与在途取消（PR #84）

[草稿 PR #84](https://github.com/ShiJiJS/shika/pull/84)基于#82，固定源码／驱动7dbf3fd，[方案](https://github.com/ShiJiJS/shika/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/LF8-THUMBNAIL-RECOVERY.md)及[104输入只读证据](https://github.com/ShiJiJS/shika/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/evidence/lf8-thumbnail-recovery/README.md)。复查#82原始请求，旧代码已有两次退避，503后200发生于关闭阶段；修正此前“没有自动恢复”的初步判断。本段让缩略图单元格独立拥有可取消HTTP客户端，关闭动画、分页读取或地址／凭据／版本／图包变化时取消旧请求和计时器，手动重试重置预算，保留三列比例与重试入口。

22项组件检查、分析／格式／Ruff通过；普通390×844原生8点：六张503后各2–3次内真实解码，持续失败恰3次后停止并实际手动恢复；真实Android返回取消6个未完成响应，3秒无额外请求，重开6张再次解码。固定范围、当前第3页、横向模式和API图包详情相同，总览无新增写请求，26公开源文件SHA不变；5张面板矩形一致。没有SQL七表快照，不把这项读回称SQL逐行验证。

三轮原生开发失败及组件诊断单独保留，不计最终8点；原型树1cbf605仍独立可移除。AVD显示恢复并关闭，未发布APK。本段未重跑全集／release／大字／横屏／目标手机，超过24页分页目前为组件取消信号与接线检查，仍待实际原生跨页。#83及#24/#33保持开放，下一步继续该跨页与其余LF8终验。

## 2026-10-27：总览容量与跨24页实际取消（PR #85）

[草稿 PR #85](https://github.com/ShiJiJS/shika/pull/85)基于#84，增加共享3许可的缩略图下载队列，等待时不创建socket，分页／关闭取消排队项、在途连接，完成／错误释放许可，保留原两次退避和三列比例。两个新增真实HTTP组件旧版基线失败（峰值24、63次仍未全解码），修正后24项相关检查通过；分析／格式／Ruff通过。

[方案](https://github.com/ShiJiJS/shika/blob/codex/lf8-overview-pagination/docs/plans/library-first/LF8-OVERVIEW-PAGINATION.md)／[207输入只读证据](https://github.com/ShiJiJS/shika/blob/codex/lf8-overview-pagination/docs/plans/library-first/evidence/lf8-overview-pagination/README.md)。固定26aceab普通390×844同版连续三轮，各11点共33点：30页目标包实际24→6→24，清单等待阶段3下载取消、21排队无GET；真实Android返回取消未完成清单，重开仍第3页／横向／原范围，API详情及写请求相同。明确点第30页才新增一次正确进度写入，主图实际显示30/30。每轮50公开源文件SHA相同。

随后只调整未被跨页路径使用的六图驱动pending预期，56b2a74再过8点：六图503自动／恰3次上限／手动恢复、3在途＋3排队取消及重开；26源SHA不变。两提交生产／跨页驱动／夹具相同，非docs差异仅六图驱动，复核脚本明确审计，共41原生点，不称同一完整源码提交。没有SQL快照／全集／release／大字／横屏／目标手机结论。

一次footer滚动驱动失误和一次QEMU图形／主循环挂起退出均另存，不计成功；原配置重启恢复显示后完成三轮，最终AVD已恢复并关闭。原型树1cbf605继续独立可移除，未发布APK。#83跨页开发证据已补齐，issue保留草稿合并／终验状态；#24/#33继续其余验收，下一步内容页强停恢复与其它组合。
