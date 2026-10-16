# 演示素材

视频与封面沿用仓库 P1/P2 已有素材；同一素材被多条演示记录复用，用于验证横竖播放与管理流程，不代表独立实拍内容。原始来源和许可记录见 `prototypes/p1/assets/SOURCES.md`。

- `media/flower-landscape.mp4`：MDN flower 示例的 H.264 Baseline 衍生编码，CC0，原始地址 https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4 。原片在当前 Android 软件模拟器出现明显方块残影，原素材抽帧清楚；对 App 内演示片重新编码后，模拟器实际横屏画面恢复正常。P1/P2 原素材保持原样；这不是 NAS 自动转码功能。
- `media/flower-portrait.mp4`：上述素材的竖版衍生；JPG 为该素材不同时间帧或同一竖版的封面。
- `fonts/PaperSerif.ttf`：Google Fonts 仓库 Noto Serif SC 可变字体的 400 字重与当前界面用字子集；内部字体名改为 PaperSerifSubset，约 300 KB。未收录的用户文字由 Android 字体回退显示。
  原始字体：https://github.com/google/fonts/tree/main/ofl/notoserifsc 。许可证为 SIL Open Font License 1.1，完整文本随附 `fonts/OFL.txt`。

字体只用于宋体风格页名与内容名称；正文沿用平台无衬线字体。原始字体和制作工具留在工作目录的忽略区，不随 App 打包。
