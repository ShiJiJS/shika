# Android 开发与模拟器

Mac 环境已经独立适配，见 [Mac 开发与 VS Code 配置](macos-development.md)。下列路径和工具表用于 Windows 开发，其他设备按实际安装位置设置。

本项目使用 Flutter，Android 为开发平台。VS Code 可连接本机服务或运行独立演示模式；部署和安装见 [部署说明](deployment.md#安装与使用)。待办与设备验收在 [GitHub issues](https://github.com/ShiJiJS/shika/issues) 跟踪。

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

1. 打开仓库根目录 `C:\Project\shika`。
   首次打开时由用户信任这个项目文件夹；Restricted Mode 会禁用调试和工作区任务。
2. 在“运行和调试”中选择 **Shika (Android)**，按 **F5**。
   默认连接 `10.0.2.2:8760`，需先启动 WSL 开发服务。离线试用原有素材可选择 **Shika Demo (Android)**。
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
cd C:\Project\shika\apps\mobile
flutter doctor -v
flutter devices
flutter analyze
flutter test test/library_flow_test.dart test/connection_widget_test.dart
flutter test integration_test/client_demo_test.dart -d emulator-5554 --no-uninstall
flutter run -d emulator-5554
```

`client_demo_test` 会构建、安装客户端到模拟器，验证真实播放/全屏、标签与目录组合、快速整理删除撤销、备份恢复及失败状态；使用隔离的演示数据目录。它已经替换最初的计数器环境冒烟测试，不能代替真实 NAS 服务验收。

集成测试保留安装的参数取决于命令：`flutter test integration_test/... --no-uninstall`；`flutter drive` 不支持该参数，须使用 `--keep-app-running`，否则 drive 默认清理会停止并卸载应用、清空加密连接存储。后者还会保留运行进程，需由测试结束流程关闭自己拥有的资源。各测试使用独立存储命名空间。真实网络播放及格式测试通过仓库根目录 `python scripts/run-client-connection-test.py --playback` 运行；脚本使用独立可丢弃服务。

`flutter run` 中按 `r` 热重载、按 `R` 热重启，按 `q` 结束调试。也可以在 VS Code 中使用对应调试按钮。

Android 模拟器使用 `10.0.2.2:8760` 访问当前 WSL 开发服务。地址和端口可在 App 中修改并记住，不依赖 `adb reverse`。端到端测试另用 8761 的独立实例，步骤见 [Mac 开发说明](macos-development.md#回归与联调)。

## 首次构建与边界

首次 Android 构建需要下载 Gradle、Android 插件、Flutter 引擎产物及对应的 NDK 等依赖，会比后续构建慢。管理用 SDK、AVD 和依赖缓存不提交 Git。

本次发现 Command-line Tools 23.0 的兼容包装器会把 Flutter 使用的带分号包名拆开，导致自动安装 NDK 失败。因此 `latest` 使用兼容的 19.0，23.0 保留备用；不要在未验证前直接覆盖 `latest`。旧工具读取新版 SDK 元数据时可能提示 XML 版本警告，这与 NDK 安装失败是不同问题；已安装包应通过实际构建验证。

客户端插件首次构建按依赖安装了 Android API 35 和 CMake 3.22.1；API 36 模拟器继续沿用，无需重新配置。

本机自动图形模式出现过 `Failed to import external memory object`、OpenGL 纹理错误和快照恢复失败。因此启动脚本固定 `-gpu software -feature -Vulkan -no-snapshot`，并将此 AVD 设为软件图形和冷启动。相较快照恢复，启动需要完整等待 Android 引导；软件渲染也不适合用来评估真实手机图形性能。

## 参考

- [Flutter 手动安装](https://docs.flutter.dev/install/manual)
- [Flutter Android 开发配置](https://docs.flutter.dev/platform-integration/android/setup)
- [Android 模拟器硬件加速](https://developer.android.com/studio/run/emulator-acceleration)
- [Flutter 中国网络与镜像说明](https://docs.flutter.dev/community/china)
