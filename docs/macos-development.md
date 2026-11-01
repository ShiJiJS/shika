# Mac 开发环境与操作

本目录从 Windows 项目的同一私有仓库迁入，基线提交 `137ad0e`，客户端 `0.1.4+5`，NAS 服务源码 `f5fe32c`。需求、规格、接口和既有验收记录继续沿用仓库文档。Mac 使用 OrbStack Docker 和 ARM64 Android 模拟器。

## 文件位置

所有本次新增的工具链、缓存和开发数据都放在当前仓库内：

| 位置 | 内容 |
| --- | --- |
| `Video Viewer.code-workspace` | 已生成的本机 VS Code 工作区，可直接打开 |
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

1. 打开根目录的 `Video Viewer.code-workspace`。本次已对该项目建立工作区信任，并安装 Flutter、Dart、Python 扩展。
2. 先启动 OrbStack。普通 F5 配置会同时准备本地 Docker 服务和模拟器，也可单独运行任务 **Server: start local Docker**。
3. 选择 **Video Viewer (Android)**，按 **F5**。启动前任务自动启动或复用 `video_viewer_api_36`，等待引导完成，在 `emulator-5554` 构建、安装和启动 App。模拟器访问 Mac 服务使用 `10.0.2.2:8760`。
4. 无需服务时选择 **Video Viewer Demo (Android)**。修改 Dart 后保存可热重载，调试工具栏也提供热重载、热重启和停止。
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

开发口令保存在 `.dev/server/passphrase`，不在日志中输出。普通服务默认媒体目录 `.dev/server/media`；本次已复制并索引两段仓库公开演示视频到 `media/demo`，不要用个人收藏跑文件操作测试。

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

```bash
python3 scripts/nas-status.py
mkdir -p tmp/releases
docker buildx build --platform linux/arm64 --target runtime \
  -t video-viewer-server:local-arm64 \
  --output type=docker,dest=tmp/releases/server-arm64.tar services/server
```

只读状态脚本按本机 infos 登记解析现有 NAS 身份，严格校验已信任主机，不输出口令。镜像归档构建不改动 NAS。需要发布时按 [部署手册](deployment.md) 先做管理数据备份和快照，再通过已有 SSH 传输、`docker load` 和 NAS 已安装的独立 Compose 更新。实际地址、部署路径和口令从 `video-viewer.connection` 读取，不写入仓库。

Windows 和 Mac 共用 Git 仓库，修改后正常提交、推送，另一端拉取；SDK、AVD、缓存和运行数据库保持每台机器独立。不要通过复制运行中的数据库来同步开发环境。

## 重新配置

```bash
bash scripts/setup-macos.sh
python3 scripts/configure-vscode.py
```

脚本要求 Apple Silicon Mac、已有 JDK 17、Python 3.13+ 和 VS Code；Docker 使用已有 OrbStack。它固定 Flutter 3.47.7 与 Android 命令行工具 19.0，校验下载摘要后在 `.dev/` 配置 SDK、AVD、缓存、VS Code 和普通开发目录。脚本也会建立 `.dev/venv` 并按哈希锁文件安装 Python 编辑依赖。签名不通过 bootstrap 重新生成，另行保留已有文件。

参考：[Flutter 官方安装说明](https://docs.flutter.dev/install/manual)、[Android 模拟器硬件加速](https://developer.android.com/studio/run/emulator-acceleration)。本次只配置项目所需的 Android 链路；Flutter Doctor 的 CocoaPods 提示属于 iOS/macOS 开发。


## 本次验证（2026-10-23）

- Android Toolchain、Hypervisor.Framework 加速、API 36 ARM64 模拟器通过；CocoaPods 提示不影响 Android 链路。
- 在 VS Code 中实际完成 F5 构建、安装、启动与调试服务连接；点击热重载成功。集成 Fish 终端直接执行 `flutter --version` 返回 3.47.7。
- Flutter 静态分析通过，68 项客户端测试通过；Docker Python 3.13 中 98 项服务端测试通过。
- I1 真实服务联调及独立 Android 进程重开两个阶段通过，包含登录/凭据过期、缩略图、滚动分页、目录断开、真实 Docker 停启及恢复。修复了旧 I1 用例对手动分页、同步按钮旧文案与凭据失效时机的过时假设；App 业务代码未改。
- 普通开发服务 8760、联调服务 8761、NAS SSH 与 HTTP 健康检查分别通过；NAS ARM64 镜像已构建导出并核对架构。独立空管理实例重建后，28 个测试媒体文件的哈希全部保持一致。
- ARM64 release APK 构建、`apksigner` 校验通过。在模拟器先覆盖安装原 Windows 0.1.4，再覆盖安装 Mac 构建版，两次 `adb install -r` 均成功。产物为 `tmp/releases/video-viewer-0.1.4-mac-arm64.apk`，版本仍为 0.1.4 / code 5；本次没有客户端业务变更。该包初始默认连接本机开发服务，已保存的连接地址仍优先；首次装到手机时需输入自己的 NAS 地址。
- APK SHA-256：`15baad35244ea94cee9f6fff271df4f4469b0e02224032f3b1c1c8e1ef6bd820`。

当前基线有 **12 个服务端文件未通过 Ruff 格式检查**，因此 `scripts/test-server.sh` 完整命令仍返回非零，但其中 98 项业务测试通过。未为迁移批量重排原业务代码。I2–I6 和完整演示集成测试本次未全量重跑，其中部分历史用例仍使用“刷新媒体目录”旧文案，运行前需与当前“同步外部变更”及后台扫描行为对齐。

环境摘要在 `.dev/toolchain-verification.json`，详细日志在 `.dev/logs/`，I1 原生截图、请求记录和宿主操作事件在 `tmp/client-e2e/`。NAS 服务和管理数据未更新；签名迁移使用的临时密文已清理。


### LF1 模拟器渲染回归

2026-10-24 的原生 I1 回归中，software / SwiftShader 渲染出现 QEMU 图形线程卡死并离线；使用 `-gpu host -feature -Vulkan -no-snapshot` 后两个阶段均通过。当时据此将 Mac 默认设为 host、Linux 设为 software；这是历史结果，当前默认见下方 LF8 验证，可用 `VV_EMULATOR_GPU` 显式覆盖。脚本复用已运行设备时不会重启或切换其后端，需要退出原模拟器后重新启动才生效。此设置不改变正式 APK 的解码策略，也不宣称所有设备后端都已验证。

### LF3 模拟器崩溃后的恢复

LF3 播放器回归中，长时间运行的 host 后端也发生过一次 QEMU 主循环/CPU 线程挂起，模拟器退出，导致 Flutter 测试报设备丢失。保留崩溃日志后冷启动；该次不计为测试通过。恢复时还出现了发送崩溃报告的模态询问，已选择“不发送”。启动脚本现使用本机 Emulator 帮助明确支持的 `-no-metrics -crash-report-mode never`，避免无人值守启动被此对话框挡住。

如果自动化终端会在命令结束后清理后台子进程，可在一个独立、持续运行的终端中以前台方式启动模拟器，再从另一终端运行联调：

```bash
bash scripts/dev.sh emulator -avd video_viewer_api_36 -port 5554 \
  -no-window -no-boot-anim -gpu host -feature -Vulkan -no-snapshot \
  -no-metrics -crash-report-mode never
```

仅在 `adb devices -l` 及进程状态确认设备已退出后重启；测试日志暂时没有输出不能当作模拟器已停止。无需删除 AVD 或清空用户数据。

冷启动首次横屏可能出现 Android 自己的“全屏查看”指引，覆盖 Flutter 的触控。联调 runner 会先核对专用 AVD 名称，再设置并读回 `immersive_mode_confirmations=confirmed`。播放后台测试使用实际 ADB Home 和 `am start --activity-single-top` 返回，宿主记录 `android-backgrounded` / `android-foregrounded`；不能用直接注入不完整的 Flutter 生命周期来冒充真实后台验证。此准备仅用于可丢弃模拟器。


### LF8 视频画面与启动器（2026-10-27）

当前启动器默认 `VV_EMULATOR_GPU=software`、`VV_EMULATOR_GLDMA=off`、`VV_EMULATOR_HOST_VIDEO=on`，显式关闭 Vulkan；对应专用 API36 ARM64 AVD。最小同源播放器对照表明，仅切换 Skia 不能消除关闭宿主解码时的纹理绿条；保留宿主解码并关闭 GLDMA 的候选配置画面正常。完整 App 复核进度及限制见 [LF8 渲染方案](plans/library-first/LF8-VIDEO-RENDERING.md)。不据此推定实际手机解码器表现。

VS Code 的 **Start Android emulator** 任务在 macOS/Linux 调用此脚本；两个 Android F5 配置通过原有前置任务使用同一入口。`configure-vscode.py` 只生成本机路径/设置，不重写共享 launch/tasks。当前调整实际验证了脚本命令入口，未重新声称完成一次 VS Code F5 点击流程。

启动器按真实同端口进程判断设备是否存在，ADB 离线残留且没有进程时会启动；已有设备必须通过 GPU、GLDMA 与宿主 AVC 属性核对，配置不符会保留设备并返回错误。切换配置前正常退出原专用模拟器，不删 userdata。独立 session 启动使模拟器不依赖短暂的前置任务 shell；PID 文件仅用于记录，真实进程和 ADB 引导状态才是就绪依据。可用 `VV_EMULATOR_HEADLESS=1` 启动无窗口验证。

```bash
VV_EMULATOR_HEADLESS=1 bash scripts/start-android-emulator.sh
python3 scripts/tests/test_android_emulator_launcher.py
```

后一个命令以隔离的假 SDK 检查离线残留、复用、配置拒绝、其它 AVD 保留和独立 session，不替代实际启动及视频播放验证。默认配置不修改 Flutter SDK、产品播放器实现或 release 签名。

### 阅读诊断的可选音频开关（2026-10-29）

四份已退出的自有QEMU宿主报告都出现CoreAudio启动等待，同时主循环及其它vCPU等待QEMU锁；这是比“图形线程卡死”更具体的线索，尚未证明所有退出或视频绿边有相同根因。SDK仓库当前emulator仍为37.2.12，本段没有升级SDK。完整比较记录见[阅读连接诊断](plans/library-first/LF8-READER-CONNECTION-DIAGNOSTICS.md)。

macOS/Linux启动器增加显式 `VV_EMULATOR_AUDIO=off`，向该模拟器传 `-no-audio`，默认仍为on。已有设备的音频参数不符时保留原进程并返回3，正常退出原专用AVD后再切换，不清数据或自动重启。这个开关也适用于从VS Code终端调用同一脚本；本次没有改动F5默认任务或Windows启动器。

```bash
VV_AVD_NAME=video_viewer_reader_perf_36 VV_EMULATOR_PORT=5558 \
  VV_EMULATOR_GPU=host VV_EMULATOR_AUDIO=off \
  bash scripts/start-android-emulator.sh
```

该命令要求已经创建此专用AVD；图包/标签等不需要声音的诊断可用此配置。[Android官方说明](https://developer.android.com/studio/run/emulator-commandline)明确该参数禁用模拟器音频，因此这里的阅读结果不能证明有声视频播放通过；产品播放器和手机音量不受此项目启动参数修改。持续稳定和真实设备继续按#78/#100验收。
