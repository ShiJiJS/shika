[项目首页](../../README.md) · [文档导航](../../docs/README.md) · [部署手册](../../docs/deployment.md)

# 拾刻 · shika Android 客户端

Flutter 客户端以媒体库为入口，视频和图包分别搜索、筛选和管理标签。选择内容后进入播放或阅读，返回保留来源。版本由 [pubspec.yaml](pubspec.yaml) 管理，待办及验收在 [GitHub issues](https://github.com/ShiJiJS/shika/issues) 跟踪。

## 开发

先按 [Mac 与 VS Code](../../docs/macos-development.md) 配置本地环境；Windows 步骤见 [Android 开发](../../docs/android-development.md)。在 VS Code 选择 **Shika (Android)** 按 F5，连接本机开发服务；**Shika Demo (Android)** 使用独立演示数据。

以下命令在 `apps/mobile` 执行：

```bash
bash ../../scripts/dev.sh flutter analyze
bash ../../scripts/dev.sh flutter test test
bash ../../scripts/dev.sh flutter run -d emulator-5554
bash ../../scripts/dev.sh flutter run -d emulator-5554 --dart-define=LIBRARY_MODE=demo
bash ../../scripts/dev.sh flutter build apk --release --target-platform android-arm64
```

真实服务默认地址为 `10.0.2.2:8760`；已保存的地址优先，也可通过 `SERVER_ADDRESS` / `SERVER_PORT` 构建参数修改初始值。App 只保存访问凭据，不保存个人口令。NAS 部署、安装及备份操作见 [部署说明](../../docs/deployment.md)。覆盖升级必须沿用既有签名，不能重建 keystore 或通过卸载绕过。

## 可重复验证

Debug 设置 → 开发工具 → 演示场景，可复位本 App 的演示记录、模拟空库、连接失败、保存失败、目录不可用和外部文件变化。不会操作 NAS。启动也可传 `--dart-define=DEMO_SCENARIO=writeFailure`，可用值见 `DemoScenario`。

模拟器集成测试例如：

```bash
bash ../../scripts/dev.sh flutter test integration_test/client_demo_test.dart -d emulator-5554 --no-uninstall --reporter expanded
bash ../../scripts/dev.sh flutter test integration_test/player_gestures_test.dart -d emulator-5554 --no-uninstall --reporter expanded
```

真实服务联调在仓库根目录运行 `bash scripts/dev.sh python3 scripts/run-client-connection-test.py`，按需追加 `--playback`、`--tags`、`--files`、`--external` 或 `--backups`。脚本使用独立可丢弃服务和测试数据，不能用于个人媒体目录。其他专项 runner 继续保留在 `scripts/`。

## 代码与素材

`lib/library/` 保存领域模型、`LibraryRepository` 边界及真实/演示实现；`lib/features/` 保存媒体库、阅读、整理和维护功能；`lib/ui/` 保存共享界面及播放器生命周期。设计约束就近记录在代码注释，未完成工作记录到 issue。

演示媒体与字体来源及许可见 [素材说明](assets/SOURCES.md)。正式 App 不依赖 `design/reference/` 或早期原型运行；[当前设计参考](../../design/reference/README.md) 独立保留，供剩余验收使用。
