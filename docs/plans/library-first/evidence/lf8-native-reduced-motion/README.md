# Android 系统减少动画：视频控件三轮原生检查

固定入口源码 `eee62f21a095ad976ce23178c917be83c9e6c075`，基于 PR #101 / d520d684；本段只增加原生测试入口及证据，`apps/mobile/lib`、Android 产品代码、服务端均未改。四处播放器修复已在 preview.3，正常 code9 两包字节仍相同；原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 独立可移除。

最终 `native-9-current-elements` 完整通过 18 点：普通动画／减少动画各三轮，当前 App 的内嵌自动隐藏与真正旋转后的横屏轻点隐藏共 12 点，另用生产 PlayerSurface 和真实 asset 解码器检查旧式控制条／可选 caption 共 6 点。后六点是原生组件检查，不代表整个旧服务界面流程。

实际 Android 全局 window／transition／animator 比例设为 1 或 0 并读回，真实 PlatformDispatcher 和当前 MediaQuery 均与设置一致；没有注入无障碍值。按实际布局坐标经 `adb input tap` 操作、真实 Android 返回，测试入口明确启用设备指针传递并等待路由进场完成。独立 8777 服务、真实网络视频、同一固定范围及当前视频保持；12 个 App 点 controller 标识相同，每次测量结束均 isPlaying=true。视频为 5 秒循环，位置读数保留，不能把回绕当作倒退，也不以此声称有声播放通过。

逐帧记录直接读取生产 AnimatedOpacity／FadeTransition 和 caption RenderBox，先请求一个真实引擎帧取得稳定基线，再执行动作；未使用模拟时钟。普通模式各控件有中间透明度、配置 160ms，首个观察到全隐藏的帧位于 166.666–200ms；减少动画时配置 0，首个目标隐藏帧透明度已为 0，caption 首帧到达最终位置，总位移 34dp。所有原始帧及缺帧间隔保留于 [报告](native-9-current-elements/profile-result.json)、[帧摘要](frame-summary.json)和[独立复核](audit.json)。这些是 Flutter 引擎帧回调观测，不是物理显示呈现延迟证明，也不把较大帧间隔抹平。

18 段原生 MP4 全文件独立解码通过；36 张原始前后图与窗口焦点均在 App，静态图核对控件显隐、视频画面、横屏返回位置及 caption。三张汇总图仅等比缩小、留白和标注，没有挪动原图内部元素：[第一轮](visual-round-1.jpg)、[第二轮](visual-round-2.jpg)、[第三轮](visual-round-3.jpg)。旧式组件采用独立 Material 容器，不能拿其背景或排布充当当前产品视觉一致性验收。没有新增独立视觉评审。

| 原生尝试 | 终端结果 | 已通过点 | 保留的失败／调整 |
| --- | --- | --- | --- |
| native-1 | 1 | 0 | 初次播放等待失败；补按钮实际启用条件，不能仅据此认定产品故障 |
| native-2-enabled | 1 | 0 | 录制器把运行中 MP4 大小超过 4096 字节误当首帧条件；停止后实际片段有效，后改为头部就绪及停止后全解码 |
| native-3-recorder | 1 | 0 | 软件 GPU 录屏时从 1 跳到 200ms 后的 0，没有观察到普通动画中间帧，原断言保持失败 |
| native-4-host | 1 | 1 | 正常关闭原 QEMU 后仅比较 host GPU；全屏 finder 无元素，本轮没有失败时前台图，不独自推断其根因 |
| native-5-canvas | 1 | 1 | 视频区域改为避开中央播放按钮；全屏仍无元素，保留原日志 |
| native-6-lifecycle | 1 | 0 | 测试点击未达到暂停断言；真实前台／播放状态保留，后续改用系统点击并等路由完成 |
| native-7-adb | 1 | 1 | 实际失败图确认 Android “Viewing full screen” 系统说明覆盖 App，生命周期 inactive |
| native-8-system-hint | 1 | 1 | 确认并关闭系统说明后，恢复播放移除暂停覆盖层，测试仍引用旧 exit 元素而漏采；画面已隐藏，不能算动画失败或通过 |
| native-9-current-elements | 0 | 18 | 在恢复播放后的当前控件树绑定观察器，完整三轮通过；观察端无错误 |

首段自有 QEMU 6364 使用软件 GPU，确认正常退出后启动同 AVD 数据的 host GPU 15327；后续全部沿用该进程和同一服务容器／数据，没有清空服务夹具或通过超时重启补成成功。各测试入口的源码与 profile APK SHA 单独记录；不是所有尝试都用同一 APK。软件和 host GPU 不构成手机性能比较。

系统全屏说明只按 UI XML 中明确的 SystemUI 标题及 “Got it” 按钮确认，保留原图和 XML，不修改 App 或假造恢复状态。第八次恢复空字符串 secure 设置时，ADB 参数丢失空值而失败；原 `restoration.json` 保留，随后正确引用空值恢复并逐项读回，见 `restoration-recovered.json`。最终观察器已修正此引用；九次原始恢复记录及恢复补证均保留。

最终自有 AVD 的实际显示覆盖 1170×2532／480、字号、旋转、三项动画比例及全屏说明设置均恢复进入前原值，再正常关闭。专用容器移除，原四服务 ID／健康及 donor 的 12 个完整文件 SHA 不变；实验数据目录保留。[清理记录](cleanup.json)、[只读次数快照](catalog-after-counts.json)均可复核；次数快照不代表 21 张业务表逐行不变。SQLite 只在其所属容器内只读观察，没有在宿主打开运行中的数据库。

本段相关播放组件 8 项与最终应用目录 analyze 通过；677 项完整客户端检查是前段 edb4a235 的历史基线，本段未重跑全集。专用 profile 入口、内存登录、`-no-audio` 与正常安装包有区别，未重建或发布正常 APK，未升级 SDK、修改 Mac 音频或部署 NAS。#97、完整 UI-06、#78、#100、#24／#33 保持开放：其它 100／140／240ms 动作、完整手势组合及目标手机／NAS 继续。

归档的 `observer-*.py` 是各阶段自有 `.dev` 实验观察器的原始来源，不是产品启动入口；运行需要对应隔离目录、容器身份和本机路径。QEMU 日志只删除 ADB 公钥身份行，驱动日志只替换临时 localhost VM 服务 URL；脱敏前后 SHA 与次数列于各段 log-provenance.json。公开请求窗口不含口令／认证头。原始失败不会计入最终 18 点，最终完整清单见 manifest.json。
