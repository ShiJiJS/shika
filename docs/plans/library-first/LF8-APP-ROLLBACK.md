# LF8：App回退包与升回新版

基于PR #94，继续UP-02。Android覆盖安装不能降低内部版本号。为支持从当前新版退回再升回，两份配套包均使用code8：旧界面0.1.4-rollback.2，新界面0.2.0-preview.2；保留同包名和原Windows签名。AOSP允许相同code、相同base/split revision的替换；仍需在自有AVD实际验证反复install -r，目标手机尚未验证。下一次提升code时必须重新生成配套回退包，不能用本次包覆盖code大于8的版本。只在独立源码导出中构建旧版，正常main入口，不卸载、不清数据、不用降级安装标志。

旧界面及视频业务来自原0.1.4源码f5fe32c9。纯旧代码写主题时会丢掉新版videoOrder/defaultMigrations，操作日志也不能直接覆盖新版多范围格式；回退导出因此复用当前偏好/凭据/ScopedJournal兼容实现，并用窄适配器连接旧接口。视频与旧v1备份日志保持当前凭据范围；遇到新版v2备份任务则保留原记录并要求回新版核对，不交给旧协议执行。其它范围和未知字段保留，启动不重放操作。原界面、播放器和旧API业务不改。所有覆盖文件和构建参数分别列SHA，不称其为原Windows APK的字节复刻。

构建前后核对实际versionCode/name、签名、ARM64 Flutter引擎、普通release及无integration_test插件，锁文件不升级、SDK不改；原型不进入导出。旧源码全部现有组件检查加兼容存储检查通过后生成回退包。现代App仅变更版本号，复核相关偏好/连接/日志检查与正常release；配套服务继续为b79da7b9的preview.2，不重复无关服务全集。

在之前自有AVD及独立配套服务上，先用现有APK6准备已确认、无待核对操作的数据，记录连接/偏好、视频与图包状态；实际install -r先升到现代APK8，再替换到回退APK8，再升回现代APK8；重复一次同号回退与升回以验证可复用。验证原地址/token、主题/相邻准备及新版默认顺序/迁移标记保留；旧UI可读写视频，升回新UI后图包/独立标签/进度和任务仍在。先把回退期间操作明确完成，再切换版本；未知结果的管理任务需先在支持它的新版里核对。对进行中/未知v2任务的旧版接管不作支持声明。

本轮不触碰真实手机/NAS；回退仅更换App，服务数据仍使用新版或已演练恢复的旧服务。保留原始截图、请求窗口、包版本/首次安装时间/数据目录、存储兼容检查及清理记录，按issue更新后再说明支持范围。目标手机、真实NAS、#78/#89、500页高分辨率与其余终验继续。

版本比较依据：[AOSP PackageManagerServiceUtils.checkDowngrade](https://android.googlesource.com/platform/frameworks/base/+/ce8e50cfcea0756066a739a6390907770949b1b0/services/core/java/com/android/server/pm/PackageManagerServiceUtils.java)。build-2/3的7→8临时包仅保留于私有诊断目录，未安装/交付。

已完成本机组合：[PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)，[两轮实际覆盖、99项检查及只读复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-app-rollback/README.md)。两份包实际code8、原签名；五次install -r覆盖、六次免口令冷启、偏好/标签/第2页纵向保留及旧回收撤销已核对。目标手机等边界继续按台账推进。
