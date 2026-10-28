# 复杂图片阅读性能：测量进行中

本段尚未达到三轮完成，也没有500页成功结论。attempt-6收齐了每类30次计时，但该轮整体失败，必须与最终验收区分。性能分支的生产lib/Android、服务runtime镜像及原型保持PR #95不变。专用profile入口、5558新AVD和8773独立实例，未替换正常安装包或接入真实NAS服务。

已生成506页/3,423,051,928字节摄影像素压力样本（500页长包+两类各3页大图）；正常服务扫描506页无失败，扫描子进程峰值152624KiB。素材是两份公开NASA/JSC摄影原图裁切拼接，保留原像素，不是506张独立照片；来源/摄影者/原文件SHA在fixture-sources.json，生成页尺寸/字节/SHA在fixture-manifest.json。二进制仅留.dev，不提交Git。原图来自[NASA/JSC iss043e000030](https://images.nasa.gov/details/iss043e000030)与[iss043e010521](https://images.nasa.gov/details/iss043e010521)。

诊断按次分开：

1. attempt-1：timings异步回调调用受保护的WidgetTester.state，与pump冲突；20bed6bb改成只读由驱动捕获的现存State引用。属于采集代码错误，不是App异常。
2. attempt-2：Dart向仅接受Content-Length的宿主控制端发送分块消息，控制端提前拒绝导致连接重置；273ebdf0给控制消息设置明确UTF8长度。此为单独控制端的已知错误，不当成#89原因或修复。
3. attempt-3：已捕获实际4K首图；find.byTooltip返回RawTooltip，采集代码却强转IconButton失败；a7525495改成明确IconButton谓词。属于驱动类型错误。
4. attempt-4：前三处修正后实际4K重复完成0–7，随后软件GPU的SWANGLE/gfxstream出现bad color buffer handle、GL context被抢占与QEMU主循环/CPU线程挂起，进程81429离开进程表，ADB消失。采样内核PSS最大196416KiB、RSS高水位297432KiB；没有据此诊断为App OOM。该轮失败，不从8次样本外推30次分位数。保留失败结果、原采集范围、进程确实消失的证据，再切换独立AVD为官方CLI支持的swiftshader重跑；不因单次观察超时直接重启。

日志副本仅去掉临时localhost VM-service地址与ADB公开身份，原日志SHA另记；其它失败内容保留。前两次常规dumpsys meminfo可能触发进程GC，后续改为仅在自有AVD root读取/proc/PID/smaps_rollup与status，取得内核PSS/RSS和VmHWM；不将不同内存定义拼成一条峰值曲线。完整root目录flutter analyze还扫到了历史证据Dart，已改用实际apps/mobile；该包完整analyze及新增两文件检查通过。

attempt-5以相同a7525495代码和数据改为SwiftShader。QEMU90728保持存活，但第3次4K试验返回前等待“已确认保存”超时，未获完整状态，尚未归因为产品或驱动。attempt-6使用5198643e补齐失败状态采集，以同一QEMU/同一数据继续；不重启存活模拟器，不把该轮拼成稳定性成功。30次4K/8K各首图、相邻翻页、500页连续拖动、三轮同版与普通release入口仍待完成。目标手机/NAS、SMB实际时延/CPU/IO、#78/#89和整体终验保持开放。原型1cbf605独立未改。

attempt-6（5198643e）收齐4K/8K各30次首图及相邻翻页，长包到索引156（第157页）时在帧与元数据窗口重排之间采样，未取得当前可见解码帧，整体失败。保留完整120个计时样本及partial-summary：4K首图p50/p95为3418.878/4021.838ms，相邻2763.871/4187.745ms；8K首图6579.630/9289.100ms，相邻3637.860/5236.664ms。nearest-rank、未过滤；这是失败轮次的开发AVD测量，不作为READ-06通过或手机性能门槛。eac02a9a修正跨帧采样时序，并明确分开一次准备的长包诊断与默认30次最终矩阵。

attempt-7-long-diagnostic（eac02a9a）重置旧位置时点击Slider外侧空白，没有触发跳页。失败状态为索引155、无待确认/错误；d5c865e7改为实际Slider拖动，不注入业务状态。attempt-8-long-diagnostic（d5c865e7）确认该拖动回到首页，后连续到索引123；随后App报告连接超时。QEMU90728仍存活、图片/保存请求此前200，尚无根因结论；该轮不通过。实际AOT已在d5c865e7构建并开始后才切去独立播放器修复分支，未热重载；阅读器/后端未变。

当前d6f78457补采sample错误时完整状态及实际服务命令，再跑长包诊断。仅在专用8773实例增加透明ASGI请求阶段/字节计数记录，不保存头部、查询或正文，不改变请求/响应；同一正常runtime镜像、数据库和只读夹具。diagnostics/request-observer保留源码/启动命令，作为诊断观察开销，正式性能三轮前须恢复正常入口。此次服务只重建了自有lab容器，未重启仍存活的AVD或其它四个服务。

两次long-diagnostic只有每类一次准备，明确final_matrix=false，汇总器拒绝把它们当30次最终矩阵。全部500页、同版三轮、普通release和目标手机/NAS仍未完成。独立播放器减少动画修复另见#97 / PR #98；尚未纳入现有正常预览APK。

attempt-9 (d6f78457): diagnostic observer active. Reset remained at index 117; failure state had no pending operation or error. No unresolved request reached the service. 1d3fb301 now waits for the rendered Slider to be enabled and starts at its current thumb, rather than the center. An observer /proc read also raced application shutdown; it is preserved in observer-errors.json, not counted as a successful observation. attempt-10 uses the same observer/runtime/QEMU and remains diagnostic-only.

attempt-10（1d3fb301）实际连续取得索引0–284的可见解码帧，随后索引285等待图片时超时；有待确认progress，服务记录显示正文已收完，但未返回响应，另有图片与library-state查询一并挂起。宿主健康检查仍200、数据库文件头可读，但容器内SQL查询挂起，普通停止/进程强制终止也未拿到容器退出事件。不能直接归因为App、模拟器或服务逻辑错误；当前指向本机运行环境/存储锁路径，根因仍未证明。

本轮后半段额外尝试将用户授权SMB目录只读挂到新容器，停在Created；正文检查尚未运行，也没有真实图包性能结论。该尝试与失败时段重叠，列作干扰，不隐去。此前也从Mac直接打开了活跃的绑定SQLite文件做只读位置查询，后续取消这种跨系统观察，改用App报告/检查点；是否相关仍待隔离证明。请求阶段记录与前后探针保留在本轮诊断目录。正常OrbStack停止已完成（没有force参数），原有四容器ID/镜像/运行状态已记录，恢复后须逐一启动/核对，再清理唯一自建的Created容器。现有用户媒体、原型和正常安装包未改，未进行NAS部署。第286页失败不计作500页成功；918ba7fd的终态报告顺序修正尚待下一轮运行验证。

恢复结果：正常stop/start完成，失败Created容器已移除，原四服务按原ID/镜像恢复运行；本机曾短暂中断，不声称全程未中断。专用数据库在容器内 `PRAGMA integrity_check` 返回ok、3包仍在；同一QEMU90728保持存活，不因本次观察重启。另发现旧独立资源脚本在观察服务重建后仍指向setup阶段旧容器ID，attempt-9/10的该服务统计不可用，resource-observer-gap.json保留计数；不拿它计算CPU/IO。现将环境采集纳入每轮runner，绑定本轮已核验实际容器ID和QEMU PID，失败计入observer_errors，不能静默放行正式结果。下一轮保持相同夹具，取消host SQLite查询与SMB挂载干扰，验证修正后的报告/采集收尾。
