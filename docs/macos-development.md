# Mac 开发环境与操作

Mac 使用 OrbStack Docker 和 ARM64 Android 模拟器；工具链、缓存及开发数据放在本仓库的 `.dev/`，不加入 Git。未解决问题与验证进度在 [GitHub issues](https://github.com/ShiJiJS/shika/issues) 更新。

## 文件位置

工具链、缓存和开发数据的位置：

| 位置 | 内容 |
| --- | --- |
| `Shika.code-workspace` | 已生成的本机 VS Code 工作区，可直接打开 |
| `.vscode/settings.json` | 本机 SDK、Java、Python、Dart 和集成终端环境 |
| `.vscode/launch.json`、`.vscode/tasks.json` | F5 运行配置与测试、打包、Docker 任务 |
| `.dev/flutter` | Flutter stable 3.47.7 / Dart 3.13.5，Apple Silicon |
| `.dev/jdk` | 复制本机既有 Microsoft JDK 17.0.20.1，供 Android 构建 |
| `.dev/android-sdk` | API 35/36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1、模拟器 |
| `.dev/avd`、`.dev/android-user` | API 36 / Google APIs / ARM64 Pixel 7 AVD，以及原 Windows 调试签名 |
| `.dev/pub-cache`、`.dev/gradle`、`.dev/pip-cache` | Dart、Gradle、Python 缓存 |
| `.dev/venv` | Python 本地编辑环境；正式回归使用 Docker 的 Python 3.13 |
| `.dev/server`、`.dev/e2e` | 普通开发服务和可复位联调实例的独立数据、测试媒体和口令 |
| `.dev/downloads`、`.dev/logs` | 安装包和环境/构建/测试日志 |
| `tmp/client-e2e`、`tmp/releases` | 联调截图与日志、APK 和 ARM64 镜像归档 |

`.dev/`、本机 VS Code 设置、工作区文件、`.env`、构建与运行产物均被 Git 忽略。SDK 不需要加入系统 PATH，也不需要安装 Android Studio。已有 GitHub SSH 和 NAS SSH 身份继续使用本机原有登记；连接资料仍由私有 infos 管理。

## 在 VS Code 开发

1. 打开根目录的 `Shika.code-workspace`。确认工作区信任，并安装推荐的 Flutter、Dart、Python 扩展。
2. 先启动 OrbStack。普通 F5 配置会同时准备本地 Docker 服务和模拟器，也可单独运行任务 **Server: start local Docker**。
3. 选择 **Shika (Android)**，按 **F5**。启动前任务自动启动或复用 `video_viewer_api_36`，等待引导完成，在 `emulator-5554` 构建、安装和启动 App。模拟器访问 Mac 服务使用 `10.0.2.2:8760`。
4. 无需服务时选择 **Shika Demo (Android)**。修改 Dart 后保存可热重载，调试工具栏也提供热重载、热重启和停止。
5. **Terminal → Run Task** 中还提供静态分析、客户端测试、ARM64 APK 构建、服务端回归和真实服务联调任务。

本机路径也写入工作区级设置，确保 Flutter 设备守护进程和调试器与终端使用相同的 Android SDK。移动整个项目后运行 `python3 scripts/configure-vscode.py`，再执行 **Developer: Reload Window**，并重建含绝对路径的 AVD、Python venv 和 Android `local.properties`。

## 命令行

以下命令在仓库根目录执行。`dev.sh` 为子进程设置本项目环境，适用于 Bash、Zsh 或 Fish 终端：

```bash
bash scripts/dev.sh flutter doctor -v
bash scripts/start-android-emulator.sh
bash scripts/dev.sh bash scripts/prepare-server-dev.sh
docker compose up -d --build --wait --wait-timeout 120
```

开发口令保存在 `.dev/server/passphrase`，不在日志中输出。普通服务默认媒体目录 `.dev/server/media`；可放入仓库公开演示素材，不要用个人收藏跑文件操作测试。

客户端命令在 `apps/mobile` 中执行：

```bash
bash ../../scripts/dev.sh flutter analyze
bash ../../scripts/dev.sh flutter test test
bash ../../scripts/dev.sh flutter run -d emulator-5554
bash ../../scripts/dev.sh flutter run -d emulator-5554 --dart-define=LIBRARY_MODE=demo
bash ../../scripts/dev.sh flutter build apk --release --target-platform android-arm64
```

APK 位于 `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`。当前仍按项目既有配置使用 debug 签名；原 Windows keystore 已经加密迁移到 `.dev/android-user/debug.keystore`，权限 0600，源证书与旧 0.1.4 APK 一致。后续构建必须使用这里配置的 Android 用户目录，不能丢弃或另生成签名后宣称可以覆盖升级。

## 回归与联调

```bash
bash scripts/test-server.sh
bash scripts/dev.sh python3 scripts/run-client-connection-test.py
```

联调脚本现支持 Mac/Linux 原生 Docker，并保留 Windows WSL 路径。先启动模拟器；VS Code 联调任务已设置该依赖。它只复位 `.dev/e2e` 的可丢弃数据，使用 8761 端口；普通 8760 和 NAS 实例独立。可追加 `--playback`、`--tags`、`--files`、`--external`、`--backups`、`--preparation` 或 `--interactions`，对应原有各阶段流程；LF3 另有 `--preview` 和 `--anchor`，分别验证固定预览与来源位置恢复。

OrbStack 默认共享内存容量较大，因此服务端回归容器显式指定 `--shm-size=64m`，使磁盘满故障测试与 Windows 一致。测试脚本即使格式检查失败也继续执行测试，最终保留失败退出码。

## NAS 维护和交付

命令行工具`rv`也已迁入当前整合分支。VS Code的`CLI: help`及`CLI: tests`任务使用`.dev/cli`隔离环境和锁定依赖；命令行和凭据重登录边界见[CLI说明](../apps/cli/README.md)。这些任务不重启NAS，不使用真实库做修改试验。

```bash
python3 scripts/nas-status.py
```

只读状态脚本通过私有 infos 的 `shika.connection` 选择 fnos-cli 或已有 SSH 配置，不输出口令。飞牛镜像构建、导入与项目重建见 [部署说明](deployment.md)；实际地址、存储路径和凭据不写入仓库。

Windows 和 Mac 共用 Git 仓库，修改后正常提交、推送，另一端拉取；SDK、AVD、缓存和运行数据库保持每台机器独立。不要通过复制运行中的数据库来同步开发环境。

## 重新配置

```bash
bash scripts/setup-macos.sh
python3 scripts/configure-vscode.py
```

脚本要求 Apple Silicon Mac、已有 JDK 17、Python 3.13+ 和 VS Code；Docker 使用已有 OrbStack。它固定 Flutter 3.47.7 与 Android 命令行工具 19.0，校验下载摘要后在 `.dev/` 配置 SDK、AVD、缓存、VS Code 和普通开发目录。脚本也会建立 `.dev/venv` 并按哈希锁文件安装 Python 编辑依赖。签名不通过 bootstrap 重新生成，另行保留已有文件。

参考：[Flutter 官方安装说明](https://docs.flutter.dev/install/manual)、[Android 模拟器硬件加速](https://developer.android.com/studio/run/emulator-acceleration)。本次只配置项目所需的 Android 链路；Flutter Doctor 的 CocoaPods 提示属于 iOS/macOS 开发。

## 模拟器选项

`start-android-emulator.sh` 默认软件渲染、关闭 Vulkan/GLDMA、保留宿主视频解码和音频，不读取或保存快照。可通过 `VV_EMULATOR_HEADLESS=1` 无窗口启动；`VV_EMULATOR_GPU`、`VV_EMULATOR_GLDMA`、`VV_EMULATOR_HOST_VIDEO` 和 `VV_EMULATOR_AUDIO` 用于显式诊断配置。

脚本检查实际进程和 ADB 引导状态；已有专用模拟器配置不符会提示错误并保留原进程，不清空 userdata、不操作其它 AVD。切换配置前正常退出原专用模拟器。`VV_EMULATOR_AUDIO=off` 禁用声音，只适合不需音频的诊断，不能用来验收视频声音。选择这些默认值的原因见启动脚本注释；根因与稳定性继续在 [#78](https://github.com/ShiJiJS/shika/issues/78)、[#100](https://github.com/ShiJiJS/shika/issues/100) 跟踪。

```bash
VV_EMULATOR_HEADLESS=1 bash scripts/start-android-emulator.sh
python3 scripts/tests/test_android_emulator_launcher.py
```

第二条命令使用隔离的假 SDK 检查复用、配置拒绝、离线残留及进程归属，不替代实际启动和播放验证。
