# Android 开发与模拟器

Mac 按 [Mac 与 VS Code 配置](macos-development.md) 设置工具链；下面说明 Windows 开发入口。App 版本由 [pubspec.yaml](../apps/mobile/pubspec.yaml) 管理，部署与安装见 [部署说明](deployment.md#安装与使用)。

## Windows 环境

准备 Flutter、对应 JDK、Android SDK、平台工具和模拟器，在 VS Code 安装仓库推荐的 Flutter/Dart 扩展。Flutter 所带 Dart 与项目依赖使用同一套 SDK，依赖版本以 `pubspec.lock` 为准。仓库的 Mac 安装脚本 [setup-macos.sh](../scripts/setup-macos.sh) 记录本项目使用的固定工具链，不能直接在 Windows 执行。

| 配置 | 用途 |
| --- | --- |
| Flutter SDK | 终端能找到 `flutter`；VS Code 使用相同 SDK |
| `ANDROID_HOME` | 实际 Android SDK 路径；启动器依次读取当前进程、用户环境变量，未设置时尝试用户目录 `develop/android-sdk` |
| Java | 与 Android Gradle 配套的 JDK，终端与 VS Code 使用同一安装 |
| `PUB_CACHE` | 可选的固定 Dart 缓存目录；调整后重新取依赖并重载 VS Code |
| `video_viewer_api_36` | 默认 API36 / Google APIs AVD，默认端口5554 |

首次配置时创建对应架构的 API36 Google APIs AVD，名称使用 `video_viewer_api_36`；项目沿用这个内部名字，不影响 App 的拾刻名称。安装构建需要的平台、NDK 和 CMake 后，运行 `flutter doctor -v`、`flutter devices` 检查实际状态；不要用旧环境的版本列表代替本机检查。

## VS Code

1. 打开仓库并确认工作区信任。
2. 真实模式先准备 WSL Docker 服务，再选择 **Shika (Android)** 按 F5；演示模式选择 **Shika Demo (Android)**。
3. 前置任务检查或启动默认 AVD，等待引导完成，在 `emulator-5554` 调试。端口被其他 AVD 占用时提示冲突，不操作其他设备。
4. 保存代码后热重载，也可用调试工具栏热重启或停止。

共享配置位于 `.vscode/launch.json`、`.vscode/tasks.json`、`.vscode/extensions.json`；本机 SDK 路径放在被 Git 忽略的工作区设置中。改路径后执行 **Developer: Reload Window**，并重新打开终端。

## 命令行

在仓库根目录的 PowerShell 启动模拟器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1
```

服务启动见 [服务端说明](../services/server/README.md#本机开发)。模拟器使用 `10.0.2.2:8760` 访问宿主机服务，App 中已保存的地址优先。手机连接 NAS 时填写 NAS 实际局域网地址。

在客户端目录执行：

```powershell
cd apps\mobile
flutter pub get --enforce-lockfile
flutter analyze
flutter test test
flutter test integration_test/client_demo_test.dart -d emulator-5554 --no-uninstall
flutter run -d emulator-5554
```

`flutter run` 中按 `r` 热重载、`R` 热重启、`q` 结束。首次构建可能需要下载 Gradle、插件和引擎依赖；SDK、AVD、缓存和签名不提交 Git。

## 测试与签名

演示集成测试使用隔离数据。真实服务联调通过 `scripts/run-client-connection-test.py` 使用独立可丢弃实例，复现命令见 [客户端说明](../apps/mobile/README.md#可重复验证)，不能用于个人收藏。

保留安装的参数按命令区分：`flutter test integration_test/... --no-uninstall`；`flutter drive` 使用 `--keep-app-running`，其默认结束清理会卸载 App，清除连接存储。测试结束流程只清理自己创建的资源。

Windows 启动器使用软件渲染、关闭 Vulkan 和快照，参数见 [启动脚本](../scripts/start-android-emulator.ps1)；Mac/Linux 的选项和诊断开关见 Mac 开发说明。模拟器结果不代替手机解码、声音和性能验收。

覆盖升级必须使用已有签名。迁移开发机器时安全保留 keystore，不用卸载或清数据绕过签名差异。
