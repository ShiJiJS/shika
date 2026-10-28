# 复杂图片阅读性能：测量进行中

本段尚未达到三轮完成，也没有30次完整p50/p95或500页成功结论。当前工具代码a7525495；生产lib/Android、服务runtime及原型保持PR #95不变。专用profile入口、5558新AVD和8773独立实例，未替换正常安装包或接入真实NAS服务。

已生成506页/3,423,051,928字节摄影像素压力样本（500页长包+两类各3页大图）；正常服务扫描506页无失败，扫描子进程峰值152624KiB。素材是两份公开NASA/JSC摄影原图裁切拼接，保留原像素，不是506张独立照片；来源/摄影者/原文件SHA在fixture-sources.json，生成页尺寸/字节/SHA在fixture-manifest.json。二进制仅留.dev，不提交Git。原图来自[NASA/JSC iss043e000030](https://images.nasa.gov/details/iss043e000030)与[iss043e010521](https://images.nasa.gov/details/iss043e010521)。

诊断按次分开：

1. attempt-1：timings异步回调调用受保护的WidgetTester.state，与pump冲突；20bed6bb改成只读由驱动捕获的现存State引用。属于采集代码错误，不是App异常。
2. attempt-2：Dart向仅接受Content-Length的宿主控制端发送分块消息，控制端提前拒绝导致连接重置；273ebdf0给控制消息设置明确UTF8长度。此为单独控制端的已知错误，不当成#89原因或修复。
3. attempt-3：已捕获实际4K首图；find.byTooltip返回RawTooltip，采集代码却强转IconButton失败；a7525495改成明确IconButton谓词。属于驱动类型错误。
4. attempt-4：前三处修正后实际4K重复完成0–7，随后软件GPU的SWANGLE/gfxstream出现bad color buffer handle、GL context被抢占与QEMU主循环/CPU线程挂起，进程81429离开进程表，ADB消失。采样内核PSS最大196416KiB、RSS高水位297432KiB；没有据此诊断为App OOM。该轮失败，不从8次样本外推30次分位数。保留失败结果、原采集范围、进程确实消失的证据，再切换独立AVD为官方CLI支持的swiftshader重跑；不因单次观察超时直接重启。

日志副本仅去掉临时localhost VM-service地址与ADB公开身份，原日志SHA另记；其它失败内容保留。前两次常规dumpsys meminfo可能触发进程GC，后续改为仅在自有AVD root读取/proc/PID/smaps_rollup与status，取得内核PSS/RSS和VmHWM；不将不同内存定义拼成一条峰值曲线。完整root目录flutter analyze还扫到了历史证据Dart，已改用实际apps/mobile；该包完整analyze及新增两文件检查通过。

attempt-5以相同a7525495代码和同一数据继续，单独记录SwiftShader配置，不与SWANGLE失败混成稳定性成功。30次4K/8K各首图、相邻翻页、500页连续拖动、三轮同版与普通release入口仍待完成。目标手机/NAS、SMB实际时延/CPU/IO、#78/#89和整体终验保持开放。原型1cbf605独立未改。
