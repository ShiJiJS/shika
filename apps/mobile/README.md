# Flutter 客户端演示版

沿用用户确认的 P2「留白」界面，实现原生 Flutter 页面与 Android 播放器。当前使用演示提供方，默认进入已连接状态，可直接播放仓库中的素材；服务地址输入不会发出真实请求。服务端后续接入。

## 在模拟器试用

在仓库根目录用 VS Code 的 **Video Viewer (Android)** 按 F5，原有模拟器启动任务继续使用。命令行也可在本目录运行 `flutter run -d emulator-5554`。环境位置见 [Android 开发说明](../../docs/android-development.md)。

1. 浏览页上下滑动换视频、点画面暂停；暂停后出现进度与倍速，横版有横屏按钮，返回保留同一播放器。
2. 顶栏仍为目录、随机/顺序、更多；目录支持挂载范围逐层选择。下方标签点击即筛选，同时满足并高亮。
3. 视频库可搜索、多选批量追加/移除标签，以及按属性筛选。标签页支持搜索、新建、改名和删除。
4. 视频库 → 快速整理，或浏览页更多 → 进入快速整理。先筛选范围，再连续查看、打标签、删除，提示中撤销准确的上次删除。退出后收起操作条。
5. 设置 → 媒体目录 / 回收站 / 备份与恢复。删除只改演示记录，恢复不覆盖冲突，永久删除再确认。备份通过 Android 文件选择器导出与导入 JSON，恢复前校验、映射并确认完整替换。
6. 设置 → 服务连接可验证输入与错误；演示口令 `demo`，地址包含 `unreachable` 时连接失败，口令不保存。

所有管理修改保存在 App 私有目录，重开可读回标签、筛选与轮次。演示备份不复制视频、连接口令或运行时请求头；与 HTML 原型备份是不同格式，不能互相导入。

## 可重复场景与复位

Debug 版本的设置 → 开发工具 → 演示场景。切换会复位 **本 App 的演示记录**，不操作 NAS。正常/复位、空库、不可达、媒体目录不可用、文件写操作失败、保存失败、恢复冲突、外部改名/移动/找回，以及同路径替换/重复副本均可重现。

「目录不可用」场景第一次刷新失败，第二次刷新恢复目录，并保留视频与标签。「外部变化」场景刷新后更新稳定视频 ID 的路径并找回缺失视频；「同路径替换与重复副本」保留旧缺失记录，新文件不继承旧标签。

也可启动时指定，例如 `flutter run -d emulator-5554 --dart-define=DEMO_SCENARIO=writeFailure`。可用值与 `DemoScenario` 一致，场景选择本身不作为产品设置保存。

## 数据边界与实现

- [客户端数据契约](../../docs/client-data-contract.md)：统一的 `LibraryRepository`，界面不读写 NAS 路径，后续在入口注入网络提供方。
- `lib/library/`：不可变领域数据、演示提供方、查询与轮次、事务式演示保存及备份校验。
- `lib/ui/`：纸白/草木绿样式、页面、筛选和目录面板，以及独立播放器生命周期。
- 播放采用 [video_player](https://pub.dev/packages/video_player)，本地目录由 [path_provider](https://pub.dev/packages/path_provider) 提供，备份文件选择使用 [file_picker](https://pub.dev/packages/file_picker)。依赖版本锁在 pubspec.lock。

## 验证

```powershell
flutter analyze
flutter test test/library_flow_test.dart test/connection_widget_test.dart
flutter test integration_test/client_demo_test.dart -d emulator-5554 --reporter expanded
```

真实 Android 模拟器流程覆盖本地视频解码与进度、倍速、滑动回看、横向全屏、标签与目录组合筛选、重开读回、快速整理删除/撤销、备份文件恢复及失败状态。测试使用隔离的 App 临时目录，不接触用户演示存储和个人收藏；文件选择桥接可替换为测试文件，避免把 OS 文件管理器当成 Flutter 组件。

界面证据及最终运行结果见 [客户端验收记录](../../docs/client-validation.md)。NAS 认证、真实扫描/文件事务、网络流媒体、真实手机兼容性和性能尚未验证。客户端整体需用户试用确认后，C6 才完成并进入服务端阶段。

## 素材

6 个初始可播放条目复用 MDN 公开花卉短视频及其竖版衍生素材，多张封面来自不同时间帧；无个人视频。来源及字体许可证见 [素材说明](assets/SOURCES.md)。
