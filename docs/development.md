[项目首页](../README.md) · [文档导航](README.md) · [部署手册](deployment.md)

# 开发指南

## 环境准备

- Android 客户端：Flutter stable（Dart 版本满足 [pubspec.yaml](../apps/mobile/pubspec.yaml)）、JDK 17、Android SDK、平台工具及模拟器或真机。
- 服务端：Docker 与 Docker Compose；Windows 在 WSL2 中运行服务端命令。
- 测试脚本：Python 3；CLI 的依赖由其 `uv.lock` 管理。

设置 `ANDROID_HOME`、`JAVA_HOME`，将 Flutter 和 Android 平台工具加入 PATH。执行 `flutter doctor -v` 和 `flutter devices` 检查工具链与设备。SDK、模拟器、签名、缓存和个人编辑器配置不加入 Git。

VS Code 安装 Flutter、Dart 扩展，打开 `apps/mobile`，选择设备后按 F5 调试。SDK 路径在本机设置中指定；修改 Dart 后可热重载。需要同时修改服务端时可打开仓库根目录。`.vscode/` 和 `*.code-workspace` 属于个人配置。

## 本地服务

在仓库根目录执行：

```bash
bash scripts/prepare-server-dev.sh
docker compose --env-file .env -f deploy/local/compose.yaml up -d --build --wait --wait-timeout 120
docker compose --env-file .env -f deploy/local/compose.yaml ps
```

准备脚本创建开发目录及忽略跟踪的根目录 `.env`，已有文件保持原值。可在运行前设置 `VV_SERVER_DEV_HOME` 指定数据位置；口令位于该目录的 `passphrase` 文件。手动配置可参考 [环境变量示例](../deploy/local/.env.example)，路径使用绝对路径。开发和测试使用可丢弃媒体，NAS 正式安装见[部署手册](deployment.md)。

服务默认端口 `8760`，健康检查 `/health`。Android 模拟器使用 `10.0.2.2:8760` 访问宿主机；真机使用可达的局域网地址。

## 运行与构建 Android

在 `apps/mobile` 执行：

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test test
flutter run -d <设备ID> --dart-define=LIBRARY_MODE=server
flutter run -d <设备ID> --dart-define=LIBRARY_MODE=demo
flutter build apk --release --target-platform android-arm64 --dart-define=LIBRARY_MODE=server
```

APK 位于 `build/app/outputs/flutter-apk/app-release.apk`。覆盖升级必须沿用原签名，安全保管 keystore；不要通过卸载或清空数据绕过签名差异。当前 Gradle 配置使用开发环境的 debug 签名，分发前检查实际签名配置。

`SERVER_ADDRESS` / `SERVER_PORT` 构建参数可修改初始连接值，App 已保存的地址优先；没有保存地址且未设置参数时，服务地址输入框留空。Debug 设置中的演示场景可模拟空库、连接失败和保存失败，使用独立演示数据。

## 测试

服务端检查在仓库根目录运行：

```bash
bash scripts/test-server.sh
```

它在 Docker 内执行 Ruff、格式检查及服务端测试。CLI 的安装和测试见 [CLI 说明](../apps/cli/README.md#开发)。

客户端集成测试需要专用 Android 模拟器，例如在 `apps/mobile` 执行：

```bash
flutter test integration_test/client_demo_test.dart -d emulator-5554 --no-uninstall
```

与真实服务实现联调时，在仓库根目录运行 `python3 scripts/run-client-connection-test.py`，可追加 `--playback`、`--tags`、`--files`、`--external` 或 `--backups`。该脚本通过 [测试 Compose](../deploy/tests/compose.yaml) 启动独立服务，并核对专用 AVD 名称（默认 `video_viewer_api_36`，可通过 `VV_AVD_NAME` 设置）。`FLUTTER_ROOT`、`ANDROID_HOME` 应指向本机 SDK。

界面场景测试使用 `scripts/test-client-ui.py`，只依赖当前 App、合成图片和公开演示视频：

```bash
docker build --target test -t shika-server:e2e services/server
python3 scripts/test-client-ui.py --output tmp/client-ui-run --scenario workspace
```

输出目录每次使用新名称；更多场景与参数运行 `--help` 查看。脚本使用 `emulator-5554` 和独立的 `127.0.0.1:8768` 服务，不对个人收藏运行测试。`flutter drive` 默认可能卸载测试 App，使用专用测试设备并留意其生命周期；模拟器不能代替真机解码、声音与性能验证。

## 代码位置

`apps/mobile/lib/` 为 Flutter 客户端，`services/server/` 为 FastAPI 服务，`apps/cli/` 为独立 HTTP CLI，`deploy/` 存放正式、本地和测试部署配置。演示媒体及字体许可见[素材来源](../apps/mobile/assets/SOURCES.md)，字体授权文件需随素材保留。
