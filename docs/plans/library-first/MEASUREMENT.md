# 视觉与目标设备测量约定

原型参考：`design/reference/library-first/`。截图只使用合成素材/仓库公开演示视频；当前原生版本保留旧导航，不能拿 LF0 截图宣称 LF4/LF8 已通过。

## 视觉

1. 固定设备视口内容区 390×844，补 360×740 与 844×390；记录 Android 系统安全区、字体倍率、主题、方向和数据版本。
2. 原型 `snapshot=1&state=...` 与原生稳定 Key 进入相同状态，使用相同非私人素材/页码/标签/筛选。拍摄前等字体、页面数据和图像稳定，隐藏动态时间。
3. AppShell 使用 `app-shell`、`app-navigation`；旧 `nav-*`、`video-grid`、`video-search`、`library-count`、`library-loading-more`、`video-stage`、`operation-error`、`backup-query` 等 Key 保留。未来新入口按 ACCEPTANCE 的 ID 增加 Key，不以屏幕坐标完成业务测试。
4. 并排检查层级/间距/封面/字号/入口，像素 diff 用于定位；字体栅格与系统栏单独判断。手势和过渡另录屏。基线源码哈希与截图分别记录，不拿静态看图代替功能运行。

## NAS 与真实 Android（LF2/LF5/LF8）

使用 `scripts/fixtures/generate-lf0-packs.py` 生成的四包；额外记录旧视频样本数量、码率和编码。每次记录 App/服务提交、设备/Android、网络、缓存冷/热、根数量和内容版本。

- 冷/热启动到首屏、视频首帧、图包首张和连续翻页耗时，至少 30 次，报告 p50/p95 和失败数。
- 500 页滚动、4K/8K 页面切换、横纵模式切换及连续切包前/后/峰值内存；同时记录在途图像数/缓存字节上限。禁止只报平均流畅度。
- App 可用 `adb shell dumpsys meminfo io.github.shijijs.video_viewer`；NAS 使用现有 Docker 统计，记录 CPU、内存、磁盘读取与网络流量及采样间隔，不写入私人凭据。
- 对比 idle、扫描中、视频前台、图包前台；只在可丢弃目录执行替换/删除测试。
- 性能门槛在实际基线可测后写入对应 issue，并保存原始数据。模拟器的数值单列，不作为手机/NAS性能结论；未测维持未完成。
