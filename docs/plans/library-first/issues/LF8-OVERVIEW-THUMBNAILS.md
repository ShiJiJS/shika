属于#24/#33的PKG-03／READ-01及相关UI，发现于[PR #82](https://github.com/ShiJiJS/video_viewer/pull/82)的实际原生图包总览。

最初在c994273普通390×844公开夹具截图看到两张503后的“重试”。复查相同请求记录，随后nav-device-back阶段各有200，旧代码本已有400／800ms两次退避；修正此前“没有自动恢复”的初判。本项重点为真实成功读回、上限和关闭／分页／身份变化后取消。主图已解码与范围／页码正常，仍按原导航证据边界保留。

[原生总览图](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/nav-library-pack-panel.png)／[请求记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/requests.json)（phase=nav-library-pack-reader的两个GET /pages/{id}/thumbnail 503）／[固定源码边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/README.md)。全部是公开生成样本，未访问私人NAS内容。

原始要求（本轮完成范围及剩余项见文末）：

- 对临时忙碌响应增加有限次数／退避的自动重试，成功后原位显示真实缩略图；离开面板、换页或资源身份变化后停止旧请求／计时器。
- 持续失败达到上限后保留现有手动重试，手动恢复实际读回同一页；不得无限请求，401／403等鉴权错误继续走既有流程。
- 总览加载和重试不写最近／阅读进度，不改变当前包、页码、阅读模式或固定范围。
- 保留原型布局、大小比例和既有“重试”形态；补有意义的组件回归、专用夹具临时失败／持续失败／关闭后取消的原生证据。

不操作正式8760、NAS、私人文件或默认凭据，不发布APK；本项完成后更新#33／RESULTS.md的PKG-03，整体验收保持独立。

## 2026-10-27：总览缩略图有界恢复与在途取消（PR #84）

[草稿 PR #84](https://github.com/ShiJiJS/video_viewer/pull/84)基于#82，固定源码／驱动7dbf3fd，[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/LF8-THUMBNAIL-RECOVERY.md)及[104输入只读证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-overview-thumbnail-recovery/docs/plans/library-first/evidence/lf8-thumbnail-recovery/README.md)。复查#82原始请求，旧代码已有两次退避，503后200发生于关闭阶段；修正此前“没有自动恢复”的初步判断。本段让缩略图单元格独立拥有可取消HTTP客户端，关闭动画、分页读取或地址／凭据／版本／图包变化时取消旧请求和计时器，手动重试重置预算，保留三列比例与重试入口。

22项组件检查、分析／格式／Ruff通过；普通390×844原生8点：六张503后各2–3次内真实解码，持续失败恰3次后停止并实际手动恢复；真实Android返回取消6个未完成响应，3秒无额外请求，重开6张再次解码。固定范围、当前第3页、横向模式和API图包详情相同，总览无新增写请求，26公开源文件SHA不变；5张面板矩形一致。没有SQL七表快照，不把这项读回称SQL逐行验证。

三轮原生开发失败及组件诊断单独保留，不计最终8点；原型树1cbf605仍独立可移除。AVD显示恢复并关闭，未发布APK。本段未重跑全集／release／大字／横屏／目标手机，超过24页分页目前为组件取消信号与接线检查，仍待实际原生跨页。#83及#24/#33保持开放，下一步继续该跨页与其余LF8终验。
