# 拾刻 · shika 改名与图标

副标题为「边看边整理的私人媒体库」。用户确认采用深绿底、暖黄色衣服的原创鹿娘图标，图标母版存放于 `assets/branding/shika-icon.png`。README 只介绍软件用途和现有功能。

GitHub 仓库与本机实际项目目录改为 `shika`。Flutter 包为 `shika`，Android 源码 namespace 为 `io.github.shijijs.shika`，Python 服务模块为 `shika`，CLI 新增 `shika` 入口，`rv` 入口继续可用。VS Code 工作区为 `Shika.code-workspace`，移动后的工具链路径已重新配置。

Android 的 applicationId 继续使用 `io.github.shijijs.video_viewer`，构建沿用原Windows签名，保证第35版可覆盖安装到已有App。加密存储键、API、备份格式、运行中的NAS持久目录、现有模拟器名称继续承担各自的兼容用途。既有备份、阅读进度和连接资料因此能继续读取。当前聊天使用的旧路径保留为指向新目录的兼容链接，实际代码和工具链只有一份。

本次发布为 `0.2.0-preview.29+35`。正常APK和同号旧界面回退APK使用 `shika-` 文件前缀。发布构建从固定提交导出，并校验原签名、包名、版本号、正式入口与ARM64。
