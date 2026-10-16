# Android 开发与模拟器

本项目暂定 Flutter，Android 为第一版开发与验收平台。当前 App 是 Flutter 工具链验证用的计数器脚手架，视频库业务尚未实现。

## 本机配置

| 组件 | 版本或位置 |
| --- | --- |
| Flutter | stable 3.47.7，`C:\Users\Todoki\develop\flutter` |
| Dart | Flutter 内附 3.13.5 |
| Dart 包缓存 | `C:\Users\Todoki\develop\pub-cache`，通过 `PUB_CACHE` 固定，供命令行、Gradle 和 VS Code 共用 |
| Java | Temurin JDK 21.0.12.1，`C:\Users\Todoki\develop\java\jdk-21.0.12.1+1` |
| Android SDK | `C:\Users\Todoki\develop\android-sdk` |
| Android 平台与构建工具 | API 36、Build Tools 36.0.0 |
| Android 平台工具 | ADB 37.0.1 |
| Android SDK 管理工具 | 兼容版 Command-line Tools 19.0 位于 `cmdline-tools/latest`；23.0 保留在版本目录 |
| Android NDK | 28.2.13676358，匹配当前 Flutter 模板 |
| Android Emulator | 37.2.12，WHPX 加速可用 |
| 系统镜像 | Android 16 / API 36、Google APIs、x86_64 |
| 虚拟设备 | `video_viewer_api_36`，Pixel 7，4 GB RAM，4 核 |
| 图形与启动 | 软件渲染、关闭 Vulkan、不读取或保存快照；CPU 继续使用 WHPX 加速 |
| 模拟器设备标识 | `emulator-5554` |
| VS Code | 1.142.0，已安装 Dart-Code.flutter 与 Dart-Code.dart-code 3.144.0 |

SDK 放在用户开发目录，确保独立启动的 VS Code 与命令行可访问同一位置。本机 Flutter 已配置 Android SDK 与 Java 路径；用户环境变量已添加 Flutter、Java、Android 工具和 VS Code 命令入口。

Flutter 下载与 Dart 包使用 Flutter 官方文档列出的 CFUG 镜像：`https://storage.flutter-io.cn` 和 `https://pub.flutter-io.cn`。Flutter SDK 与 JDK 下载已校验发布清单中的 SHA-256；Android 命令行工具已校验 Google 仓库提供的 SHA-1。

## 在 VS Code 运行

1. 打开仓库根目录 `C:\Project\video_viewer`。
   首次打开时由用户信任这个项目文件夹；Restricted Mode 会禁用调试和工作区任务。
2. 在“运行和调试”中选择 **Video Viewer (Android)**，按 **F5**。
3. 启动前任务会检查或启动 `video_viewer_api_36`，等待 Android 完成启动，然后在 `emulator-5554` 上调试。
4. 修改 Dart 代码并保存，使用 Flutter 热重载；需要重置状态时使用热重启。

运行配置固定目标模拟器，避免机器连接其他 Android 设备时选错。默认端口 5554 若已被其他模拟器占用，启动任务会提示冲突，不会操作其他设备。

仓库中的 `.vscode/extensions.json`、`.vscode/launch.json` 和 `.vscode/tasks.json` 可共享。本机 SDK 路径和终端环境放在未纳入 Git 的 `.vscode/settings.json` 中；其他设备自行设置本地 SDK 路径。

新终端通过用户环境变量发现工具；已打开的旧终端需重开。当前工作区也显式配置了终端与 Dart 扩展的本机环境。

本机包缓存固定在用户开发目录，避免不同进程对应用数据目录的重定向差异造成“找不到包文件”。调整缓存位置后需重新执行 `flutter pub get`；旧编辑器进程可使用 **Developer: Reload Window** 重载工作区。

## 命令行运行与验证

在仓库根目录启动模拟器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1
```

在客户端目录执行：

```powershell
cd C:\Project\video_viewer\apps\mobile
flutter doctor -v
flutter devices
flutter analyze
flutter test test/widget_test.dart
flutter test integration_test/environment_smoke_test.dart -d emulator-5554
flutter run -d emulator-5554
```

`environment_smoke_test` 会实际构建 Android App、安装到模拟器、启动界面并点击计数器，验证计数从 0 变成 1。这个测试只验证开发环境，后续功能实现时应替换或扩充为真实用户流程。

`flutter run` 中按 `r` 热重载、按 `R` 热重启，按 `q` 结束调试。也可以在 VS Code 中使用对应调试按钮。

Android 模拟器访问 Windows 开发服务时通常使用 `10.0.2.2`。未来服务监听端口和 App 的局域网访问配置随服务端实现确定；当前没有视频库服务。

## 首次构建与边界

首次 Android 构建需要下载 Gradle、Android 插件、Flutter 引擎产物及对应的 NDK 等依赖，会比后续构建慢。管理用 SDK、AVD 和依赖缓存不提交 Git。

本次发现 Command-line Tools 23.0 的兼容包装器会把 Flutter 使用的带分号包名拆开，导致自动安装 NDK 失败。因此 `latest` 使用兼容的 19.0，23.0 保留备用；不要在未验证前直接覆盖 `latest`。旧工具读取新版 SDK 元数据时可能提示 XML 版本警告，这与 NDK 安装失败是不同问题；已安装包应通过实际构建验证。

本机自动图形模式出现过 `Failed to import external memory object`、OpenGL 纹理错误和快照恢复失败。因此启动脚本固定 `-gpu software -feature -Vulkan -no-snapshot`，并将此 AVD 设为软件图形和冷启动。相较快照恢复，启动需要完整等待 Android 引导；软件渲染也不适合用来评估真实手机图形性能。

## 已完成的验证

- 2026-10-16：Android 36 模拟器中的 `environment_smoke_test` 构建、安装、启动和计数交互全部通过。
- 静态分析与基础组件测试已通过。
- 普通 App 已通过 Flutter debug 模式构建、安装和启动；调试服务返回正常视口及页面文字。修改文字后热重载成功，渲染树确认已使用新文字。
- 这些结果验证开发工具链，不能代替真实视频库业务验收；本次排查未使用 computer-use。

环境验证尚不能证明 NAS 视频的编码兼容性、真实手机解码能力或家中网络性能，后续按规格进行目标环境测试。

## 参考

- [Flutter 手动安装](https://docs.flutter.dev/install/manual)
- [Flutter Android 开发配置](https://docs.flutter.dev/platform-integration/android/setup)
- [Android 模拟器硬件加速](https://developer.android.com/studio/run/emulator-acceleration)
- [Flutter 中国网络与镜像说明](https://docs.flutter.dev/community/china)
