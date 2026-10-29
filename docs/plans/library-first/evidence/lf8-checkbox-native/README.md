# 复选框真实 Android 验证

固定测试源码 `1ad6f35e1cf2c8d172f39d1170b36f3a411bd64f`。生产 lib 树 `4052a2cc98a224fccac85d96ea9da7e05e4d130f` 与组件阶段 `2a4e9cd7` 相同，沿用该段的 777 项客户端检查、11 项针对检查和 96 组静态像素/尺寸结果。本段只增加独立 profile 测试入口，未修改生产 App、SDK、服务或独立原型。

只读复核（不启动设备、服务或打开数据库）：

```sh
python3 docs/plans/library-first/evidence/lf8-checkbox-native/verify.py
# 可选：重新完整解码六段成功录像，需要 ffmpeg
python3 docs/plans/library-first/evidence/lf8-checkbox-native/verify.py --decode
```

`manifest.json` 固定原始输入的字节和 SHA；不含 APK。`audit-native.py`、`audit-pixels.py`、`run-native.py`、`cleanup-native.py` 是当时本机执行记录，依赖私有工作目录/工具路径，不能作为公开只读入口执行。`verify.py` 从固定原始帧重新判断，不只读取汇总的通过标志。

## 成功范围

`native-5` 是唯一完整成功轮：三轮 × 实际 TrashEntryRow/实际 PaperCheckboxListTile × 15 个方向，共 90 个方向、605 个逐帧观测、36 次值回调（每种形式 18 次），终值均 false。普通/减少下正反选择、按压/取消、真实运行中切换、原生按住后由夹具模拟异步禁用均覆盖；24 次真正中途切换、6 次按住后禁用。未发仓库或文件命令，未执行删除或恢复。

真实 ADB tap/DOWN/CANCEL/UP、真实 Android 三个动画比例与读回记录在 `events.json`。`PlatformDispatcher` 和 `MediaQuery` 的原生减少动画标志一致；公开控制器与实际 `ToggleablePainter` 同时采样。普通时长选择 140ms、按压 100ms；减少时为 0。24 次切换的前一帧严格处于 (0,1)，首个原生标志帧实际绘制已到目标，此后保持。禁用时结束按压，不多发值回调。

`live-proof.json`/`disabled-proof.json` 保留前后帧；`normal-observed-spans.json` 是首个观测至到位的实际帧间差，不冒充精确输入至显示延迟。到位后额外采三个 vsync 样本只用于确认端点，不作为自然空闲帧率/性能结论。

六份 `round-*.mp4` 均完整解码，1170×2532。`pixel-proof-v2.json` 从实际原生点击位置截取未缩放 48×48 画素，确认未选与稳定白色勾号；六张 `*-visible-tick.png` 是原录像完整帧，已查看代表图。画素证明可见状态变化，不声称录像和原生标志的绝对时间同步。早期 `pixel-proof.json`/`*-selected-pixels.png` 取最大实心面积，捕到勾号出现前的中间态，故保留诊断但不作为最终勾号证明。最终裁剪使用 demux 时间基，避免初版 rawvideo 时间戳舍入警告；源录像完整解码通过。

## 未通过的四次尝试

各自目录、原始日志/局部录像/恢复记录保留，未混进 90 个成功方向，均为同一 QEMU PID 20034：

1. `native-1`：`flutter drive` 不支持 `--no-uninstall`，进入 App 前 exit64。改用该命令实际支持的 `--keep-app-running`。`flutter test --no-uninstall` 属于另一命令。
2. `native-2`：先通过 8 个方向，宿主 shell 多行串使用了字面量 `\\n`，后续原生 tap 参数失败。修正为真正换行，不改 App。
3. `native-3`：43 个方向后，取消到系统切换太早，上一观测仍为 1.0，不满足真正中途切换。触发延迟 15→40ms，保留严格 (0,1) 条件，不把端点正确当中途证明。
4. `native-4`：6 个方向后，frame 回调内使用 `WidgetTester.state/widget` 与等待中的 pump 冲突，采样超时。改为公开 Element/ToggleableStateMixin/ToggleablePainter 遍历，无 tester 查询；重建 v2 profile 后完整通过。

runner 的 `restoration.json.errors` 沿用累计 observer 列表，第二次因此仍记着原 tap 命令失败；它的 restored 读回与进入配置一致、没有 restoration failure。公开复核器初稿误把所有失败轮的此字段都要求为空，首次复核失败后按原始记录区分累计观测错误与实际恢复失败；成功轮仍严格要求 observer_errors 为空。

v1 profile 源码 `658a4282`、SHA `58671f5f4f3a2f3542c68e341fbfcb3652bac727f0b4efd9e21140337f3948aa`；v2 源码 `1ad6f35e`、SHA `b18339f4a8d23afdf541634ee394917fc28058e16e6e232145a6ee2bda513495`。元数据分别保留，两个 APK 仅在本机。审计器初版的字符串检查误把 `element.state` 当 `t.state`，改为单词边界正则；未放宽任何帧/回调判断。

## 环境与剩余边界

测试复用自有 `video_viewer_reader_perf_36` / emulator-5558 / QEMU 20034，host GPU、GLDMA off、HardwareDecoder on、无声/无窗口。每次均恢复进入时配置：已有 1170×2532/480 覆盖、字体/旋转、空字符串 immersive 设置、transition/window=1.0，缺失的 animator 比例恢复为缺失。没有将进入前覆盖误清除，也没有 root/unroot 命令。最终 `cleanup-native.json` 确认关闭自有模拟器且原四服务完整 ID/健康保持；控制器端口也已关闭。

独立原型树仍为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`。code16 正常配套两包 SHA、SDK 原文件已由本机审计核对保持；本段没有新正常包。此证据是生产组件的真实 Android 输入/动画证明，不是正常 main 中五处业务、TalkBack 全项、目标手机、NAS、有声播放或正式发布验收。#116 的正常包项以及 #24/#33 继续开放。
