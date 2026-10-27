属于#24/#33的PKG-03／READ-01及相关UI，发现于[PR #82](https://github.com/ShiJiJS/video_viewer/pull/82)的实际原生图包总览。

生产／驱动c994273，普通390×844专用8768公开夹具。打开图包总览时，两张缩略图请求返回503，随后停在“重试”，没有自动恢复；主阅读图片已实际解码，范围／页码和返回行为正常。现象与导航验收分开，本轮没有将这些缩略图记作成功解码或重试通过。

[原生总览图](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/nav-library-pack-panel.png)／[请求记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/library/requests.json)（phase=nav-library-pack-reader的两个GET /pages/{id}/thumbnail 503）／[固定源码边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-navigation-restart/docs/plans/library-first/evidence/lf8-navigation-restart/README.md)。全部是公开生成样本，未访问私人NAS内容。

需要完成：

- 对临时忙碌响应增加有限次数／退避的自动重试，成功后原位显示真实缩略图；离开面板、换页或资源身份变化后停止旧请求／计时器。
- 持续失败达到上限后保留现有手动重试，手动恢复实际读回同一页；不得无限请求，401／403等鉴权错误继续走既有流程。
- 总览加载和重试不写最近／阅读进度，不改变当前包、页码、阅读模式或固定范围。
- 保留原型布局、大小比例和既有“重试”形态；补有意义的组件回归、专用夹具临时失败／持续失败／关闭后取消的原生证据。

不操作正式8760、NAS、私人文件或默认凭据，不发布APK；本项完成后更新#33／RESULTS.md的PKG-03，整体验收保持独立。
