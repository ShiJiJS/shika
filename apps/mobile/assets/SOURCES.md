# 演示素材与许可证

这里独立记录正式 App 演示素材的来源；同一素材被多条演示记录复用，不代表独立拍摄内容。

## 视频与封面

原始视频为 MDN Interactive Examples 的 CC0 `flower.mp4`：

- [原始文件](https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4)
- [MDN video 示例说明](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/video)

原片曾在软件模拟器中出现块状解码残影，因此演示横版 `media/flower-landscape.mp4` 使用 H.264 Baseline 衍生编码；`media/flower-portrait.mp4` 是同一素材的竖版衍生。这些处理只针对打包演示素材，NAS 服务不会自动转码。

`media/flower-landscape.jpg`、`media/flower-portrait.jpg` 是对应视频约1.2秒处的封面；`media/landscape-early.jpg`、`media/landscape-late.jpg`、`media/portrait-early.jpg`、`media/portrait-late.jpg` 分别取对应横/竖视频约0.1秒和4.2秒的帧。封面沿用同一 CC0 素材来源，没有使用参考产品的图片。

## 字体

`fonts/PaperSerif.ttf` 来自 [Google Fonts Noto Serif SC](https://github.com/google/fonts/tree/main/ofl/notoserifsc) 可变字体的400字重与界面用字子集，内部名称为 `PaperSerifSubset`。未收录的用户文字由平台字体回退显示。

原字体版权声明与 SIL Open Font License 1.1 完整文本保存在 [fonts/OFL.txt](fonts/OFL.txt)，并通过 `pubspec.yaml` 随 App 打包。字体用于页名与内容名称；正文沿用平台无衬线字体。
