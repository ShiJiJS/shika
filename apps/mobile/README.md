# Flutter 客户端

## 当前媒体库版本

目前已交付第28版（preview.22），配套NAS服务preview.8。安装与同号回退包见[说明](../../docs/nas-app-preview-2026-11-01-code28.md)，Mac/VS Code入口见[开发说明](../../docs/macos-development.md)。直接覆盖安装，原连接和本机数据保留。

1. 连接后进入媒体库，在“视频”和“图包”之间切换；标签和最近也分别按类型管理。
2. 视频先在库或标签中搜索、筛选，再点击具体视频或“预览此范围”进入播放；退出回原来源。
3. 图包一包一卡，点击阅读。默认纵向拼接，支持双指缩放和双击复位，也可切换横向翻页、总览及阅读设置；已有单包偏好优先。
4. 图包菜单可移入回收站；快速整理须明确进入，成功才切换下一包，撤销对应刚才的操作。当前NAS图包源目录只读，不会移动或物理删除原图。
5. 设置中查看各目录自己的扫描进度；操作任务查询原结果，不自动重发未知的删除或恢复。
6. 备份通过系统文件保存/选取，核对目录映射后才确认恢复；不包含源媒体，也不覆盖连接口令和本机外观偏好。

第28版保留图片移除后的续读定位提示，已提交选择挤占待处理列表的修复继续保留。目标手机及完整验收见[当前进度](../../docs/plans/library-first/PROGRESS-CURRENT.md)。以下保留早期视频版开发记录，当前界面入口以上述路径为准。

## 早期视频版记录

沿用用户确认的 P2「留白」界面，实现原生 Flutter 页面与 Android 播放器。默认使用真实服务提供方，输入个人口令后连接 WSL/NAS API；可单独启动演示模式，继续试用原有打包素材和本地演示记录。I1–I6 已完成，已验证范围见 [联调记录](../../docs/integration-validation.md)。测试 APK、部署与备份步骤见 [交付手册](../../docs/deployment.md)；真实 NAS 与目标手机待 [V1 验收](../../docs/v1-validation.md)。

## 在模拟器试用

在仓库根目录用 VS Code 的 **Video Viewer (Android)** 按 F5，默认地址为 `http://10.0.2.2:8760`，在连接页可修改并记住。先按 [服务端运行说明](../../services/server/README.md) 启动 WSL Docker。访问凭据使用 Android 加密存储；不保存个人口令，401 后重新输入，网络暂时中断保留连接配置供重试。服务启动不阻塞 Flutter 首帧。

选择 **Video Viewer Demo (Android)** 可直接试用演示版。命令行演示模式为 `flutter run -d emulator-5554 --dart-define=LIBRARY_MODE=demo`；真实模式默认启用，可通过 `--dart-define=SERVER_ADDRESS=10.0.2.2 --dart-define=SERVER_PORT=8760` 修改初始值。已保存的地址优先，地址不依赖临时端口转发。环境位置见 [Android 开发说明](../../docs/android-development.md)。

下面保留第一版视频界面的路径。真实模式读写已连接服务的管理数据和允许写入的挂载文件；演示模式只操作独立本地记录。

1. 浏览页上下滑动换视频，画面跟随手指整页滑动，短拖回弹；点画面暂停/继续，中央不显示播放按钮。名称和半透明标签浮在视频下方。进度默认隐藏，左右拖动画面或底部区域时出现，松手提交进度，闲置 3 秒收起；暂停后也不常驻。
2. 播放时长按临时 2 倍速，松手恢复原速。横版的「横屏」胶囊可进入全屏；横屏点画面显示/隐藏控件，左上角无背景箭头退出，箭头和进度闲置 3 秒隐藏。左右拖动快进/后退；左半侧上下滑动调当前窗口亮度，右半侧调 Android 媒体音量，退出恢复窗口亮度。
3. 顶栏仍为目录、随机/顺序、更多；目录支持挂载范围逐层选择。画面内标签点击即筛选，同时满足并高亮。
4. 视频库可搜索、多选批量追加/移除标签，以及按属性筛选。标签页支持搜索、新建、改名和删除。
5. 视频库 → 快速整理，或浏览页更多 → 进入快速整理。先筛选范围，再连续查看、打标签、删除，提示中撤销准确的上次删除。退出后收起操作条。
6. 设置 → 媒体目录 / 回收站 / 备份与恢复。真实模式删除会移到 NAS 回收目录，恢复不覆盖冲突，永久删除再确认；演示模式只改演示记录。正式管理备份通过 Android 文件选择器导出与导入 JSON，恢复前校验、映射并确认完整替换；待确认任务重开后只查询，不重新执行。
7. 更多 → 切换暗黑/浅色模式，或设置 → 暗黑模式，两处同步并在本机保存，重开保留。关闭菜单继续原来的播放状态。
8. 设置 → 服务连接可验证输入与错误；演示口令 `demo`，地址包含 `unreachable` 时连接失败，口令不保存。
9. 设置 → 准备相邻视频，可关闭前后各一条的播放器准备来减少占用。默认最多 3 个播放器，只有当前视频播放和发声；离开浏览或网络播放进入后台释放实例，回到前台保持暂停，并保留选定的常规倍速。

真实标签、筛选、轮次、文件任务与管理备份保存在服务端；App 私有存储只保留连接、外观和待确认命令/任务等本机状态。演示管理修改单独保存在 App 私有目录。正式服务、演示和 HTML 原型备份格式不同，不能混用；管理备份均不复制视频或登录凭据。

## 可重复场景与复位

Debug 版本的设置 → 开发工具 → 演示场景。切换会复位 **本 App 的演示记录**，不操作 NAS。正常/复位、空库、不可达、媒体目录不可用、文件写操作失败、保存失败、恢复冲突、外部改名/移动/找回，以及同路径替换/重复副本均可重现。

「目录不可用」场景第一次刷新失败，第二次刷新恢复目录，并保留视频与标签。「外部变化」场景刷新后更新稳定视频 ID 的路径并找回缺失视频；「同路径替换与重复副本」保留旧缺失记录，新文件不继承旧标签。

也可启动时指定，例如 `flutter run -d emulator-5554 --dart-define=LIBRARY_MODE=demo --dart-define=DEMO_SCENARIO=writeFailure`。可用值与 `DemoScenario` 一致，场景选择本身不作为产品设置保存。

## 数据边界与实现

- [客户端数据契约](../../docs/client-data-contract.md)：统一的 `LibraryRepository`，界面不读写 NAS 路径；入口选择真实/演示提供方，视频列表和目录使用异步加载。
- `lib/library/`：不可变领域数据、演示提供方、查询与轮次、事务式演示保存及备份校验。
- `lib/ui/`：纸白/草木绿样式、页面、筛选和目录面板，以及独立播放器生命周期。
- 播放采用 [video_player](https://pub.dev/packages/video_player)，本地目录由 [path_provider](https://pub.dev/packages/path_provider) 提供，备份文件选择使用 [file_picker](https://pub.dev/packages/file_picker)。依赖版本锁在 pubspec.lock。

## 验证

```powershell
flutter analyze
flutter test test
flutter test integration_test/client_demo_test.dart -d emulator-5554 --no-uninstall --reporter expanded
flutter test integration_test/player_gestures_test.dart -d emulator-5554 --no-uninstall --reporter expanded
flutter test integration_test/player_chrome_test.dart -d emulator-5554 --no-uninstall --reporter expanded
```

真实 Android 模拟器流程覆盖本地视频解码与进度、倍速、滑动回看、横向全屏、标签与目录组合筛选、重开读回、快速整理删除/撤销、备份文件恢复及失败状态。测试使用隔离的 App 临时目录，不接触用户演示存储和个人收藏；文件选择桥接可替换为测试文件，避免把 OS 文件管理器当成 Flutter 组件。

真实服务 I1 运行仓库根目录的 `python scripts/run-client-connection-test.py`；I2–I6 分别加 `--playback`、`--tags`、`--files`、`--external`、`--backups`。脚本准备独立 WSL Docker 测试实例、在模拟器验证公开界面和 API，并真实停止容器与 Android 进程。这里的固定测试口令不用于正式实例；不要在个人媒体目录运行测试控制服务。普通开发服务不受测试实例复位影响。

演示界面证据及运行结果见 [客户端验收记录](../../docs/client-validation.md)。2026-10-16，用户已确认客户端整体演示可进入服务端阶段，C6 完成。S1–S6 已在 WSL Docker 验证，见 [服务端验证记录](../../docs/server-validation.md)；网络接入证据单独记录于 [联调记录](../../docs/integration-validation.md)，真实 NAS 与目标手机仍需 V1 验收。

## 素材

6 个初始可播放条目复用 MDN 公开花卉短视频及其竖版衍生素材，多张封面来自不同时间帧；无个人视频。来源及字体许可证见 [素材说明](assets/SOURCES.md)。
