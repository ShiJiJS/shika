# 复杂图片阅读性能：正式三轮完成，正常包与目标机待验

当前正式accepted-1/2/3均完整通过：每轮四组各30次、全部500页、同页切换/返回来源、单App PID和采集收尾均通过，见下方逐轮汇总、matrix-summary.json与原始文件。506页/3,423,051,928字节已逐个复核SHA，与生成清单相同。此前失败或零样本端口预检均另存，不混入成功统计。性能分支的生产lib/Android、服务runtime镜像及原型保持PR #95不变；普通release与目标手机/NAS仍未在本段验收。当前指定SMB挂载不可用，真实图包未读取；继续按授权暂跳过需配合部分。

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

attempt-11（58b071bf）实际资源采集ID匹配，终态报告先落盘、内存采集再停止，observer_errors为空；该修正已在失败路径运行验证。首页重置成功、会话无pending/错误，但点击阅读设置后未出现纵向模式选项，脚本提前失败，未开始连续500页。补充控件实际渲染帧与IconButton祖先onPressed可用判断，避免只凭会话保存完成和命中范围就点击；不改生产阅读器。此轮只有每类一次准备，不计算30次分位数，也不作为存储挂起已消失的证明。


构建兼容修复：显式声明既有SDK flutter_driver后，当前锁文件与旧回退源码只在direct dev/transitive角色上不同，原构建器的整文件相等断言会拒绝导出。build-app-rollback.py现在只允许该角色字段不同，版本/来源/说明/校验和仍须与旧版完全一致，并各自保留原锁文件SHA；真实旧/新锁差异获准，版本/来源/校验和三类篡改均被拒绝，记录见packaging-lock-check.json，Ruff通过。未运行新一轮APK构建，也未覆盖已有预览包。

后续版本准备：同一打包器现在从冻结源码读取preview.N+CODE，自动配对rollback.N及同code，目标文件名也由版本决定；拒绝覆盖已有APK的检查保留。packaging-version-check.json记录现有preview.2/code8、下一版preview.3/code9及四类非法声明拒绝，Python3.9语法和人工编写文件的diff检查通过；三轮结束后Ruff检查/格式也通过。这不是新APK构建/安装证明，尚未修改App版本或code8产物。

attempt-12（311d2c86）诊断通过：1205次真实拖动覆盖索引0–499共500张，无漏页，同一范围、本包末尾未自动切换，横纵切换保留第500页，10个前台检查点已核对PNG SHA。单一App PID16437，实际解码像素峰值2053350、provider最多6、估算49280400字节、元数据最多120；内核采样PSS峰值259.03125MiB、RSS峰值358.21094MiB、VmHWM378.73047MiB，含profile/采集开销，未加memtrack。211份环境采集对应正确容器/QEMU，未观察到本轮崩溃。长包实际拖动1142.11秒，整轮1295.96秒；本机软件GPU数据不当作手机/NAS性能。

该轮每类只做一次小包准备，final_matrix=false；正式汇总器已确认拒绝它作为最终30次结果，不给n=1计算p95。本轮取消host SQLite查询及SMB挂载，属于隔离因素后的成功，不宣称此前存储挂起根因已证实或#78/#89已修好。完整数据、内存/环境原始值、图像、请求阶段及明确诊断摘要均在diagnostics/attempt-12-long-diagnostic。

随后将专用8773实例恢复普通video_viewer.app:create_app入口（同镜像/数据/只读夹具，不再ASGI封装）；通过普通HTTP读取同一范围，确认第500页、horizontal、completed=true、仍在3包范围第1包。控制探针登录后已注销，不直接打开活跃数据库。正式矩阵runner支持--ref冻结同版，核对整份App、开发启动脚本、runner/汇总器和原型均一致，文档可另外更新。60/65/70分钟为整轮测试/驱动/runner的收尾预算，依据本次完整长包约22分钟加每类30次准备留余量；单次请求超时和60秒状态等待不变，也不删慢样本。环境汇总核对身份、单一App PID、计数重置及单位，Docker计数只是近似采样差值，不充当NAS物理IO；相关正反检查见environment-summary-check.json。下一步为相同冻结版本三轮正式运行及普通release入口，目标手机/NAS保持待验。

正式final-1（81a11a98）失败：日志完成4K的30次完整试验和8K第0次，随后VM service消失、ADB offline，内存采集和App停止清理也失败。终态原始报告未生成，不从日志拼凑缺少的全部30次首图/相邻翻页分位数。宿主确认QEMU90728已不存在，ADB无设备；同PID的macOS退出报告显示SIGSEGV，触发栈位于CrashReporter.GenerateDumpAndDie/HangDetector。退出前可采到的App PSS最大220.118MiB、VmHWM317.117MiB，不作为排除全部内存或环境原因的证明。选择性退出字段、符号栈、日志、检查点和采样完整保留在diagnostics/final-1-qemu-exit，私有原始系统报告仅记录SHA，未提交设备UUID。

已确认本机Emulator为37.2.12/build16428233，[官方版本说明](https://developer.android.com/studio/releases/emulator)将其列为Stable。没有更新SDK或改App；仅在确认旧QEMU退出后，以同AVD数据和同命令重新启动87970，恢复1170×2532/density480/font1.0及专用ADB root，未wipe data。启动日志实际显示GLES仍经SWANGLE/ANGLE使用SwiftShader，CLI名称变化不被当作已证明的独立GLES修复。三轮正式结果仍缺，#78/#89不关闭；accepted-1目录为81a11a98重试中的候选，只有完整30次和500页、采集无错后才计成功。

## 正式accepted-1完整通过；另两轮待完成

冻结81a11a98，普通服务入口、同一QEMU87970：四组各30个样本全部收齐，1206次真实拖动覆盖全部500页，无漏页、模式切换同页、返回来源。终态报告和两类采集线程正常收尾，观察错误为空，正式汇总器通过；不与此前失败或一次准备诊断拼接。

| 本机profile指标 | 次数 | p50毫秒 | p95毫秒 | 最大毫秒 |
| --- | --- | --- | --- | --- |
| 4K缓存清空后打开 | 30 | 3176.275 | 4919.976 | 5037.579 |
| 4K相邻翻页 | 30 | 2895.849 | 4784.493 | 5057.832 |
| 8K缓存清空后打开 | 30 | 6822.233 | 8434.438 | 15525.253 |
| 8K相邻翻页 | 30 | 3935.984 | 5003.714 | 5056.049 |

nearest-rank、未过滤，包括15.525秒的8K慢样本。以上为M3软件GPU上的注入点击到当前解码RawImage/帧结束墙钟，服务OS缓存未清，不当作真实手机延迟或可接受的产品速度。单App PID3727，1602份内核观察：PSS采样峰值255.491MiB、RSS峰值356.023MiB、已采到VmHWM373.070MiB；6 provider/49280400字节估算、120元数据、实际像素2053350有界。328份环境记录绑定正确容器，Docker统计和QEMU宿主RSS与App内存定义分别记录；长包拖动1257.15秒。原始数据、所有慢样本、帧时序和独立汇总在accepted-1。

accepted-2已用同一81a11a98、同一素材/服务和仍存活的QEMU87970启动；三轮尚未全部完成，未关闭READ-06，也未重建或更新普通安装包。旧正式final-1的模拟器退出仍保留为失败，不因本轮通过就算作已修复。

## 正式accepted-2完整通过；第三轮进行中

同一81a11a98/App树71e6caf、普通服务容器1b87c4f9与QEMU87970，第二轮完整通过。四组各30次，1206次真实拖动覆盖全部500页，12个检查点PNG SHA核对一致；人工查看末尾图为500/500、仍在3包范围第1包，并有手动下一包/返回来源/返回最后一张入口。终态报告、内存/环境采集及App停止全部正常收尾，observer_errors为空，正式汇总器通过。

| 本机profile指标 | 次数 | p50毫秒 | p95毫秒 | 最大毫秒 |
| --- | --- | --- | --- | --- |
| 4K缓存清空后打开 | 30 | 3321.217 | 4243.746 | 6424.237 |
| 4K相邻翻页 | 30 | 2930.461 | 4209.021 | 4458.477 |
| 8K缓存清空后打开 | 30 | 6383.599 | 9897.607 | 11848.153 |
| 8K相邻翻页 | 30 | 3773.777 | 6111.717 | 6867.050 |

nearest-rank，所有慢样本保留。单App PID11487的1525份内核观察：PSS采样峰值254.464MiB、RSS355.934MiB、已采到VmHWM375.203MiB；6 provider/49280400字节估算、元数据120、缓存53474704字节、实际像素2053350峰值，未见本轮持续增长到OOM。309份环境记录匹配本轮容器/QEMU；长包拖动1171.834秒，整轮约1893秒。帧时序和Docker近似计数保留在summary与原始文件，不作为手机/NAS性能。

第三轮的首次接续在guard.bind宿主8774时返回Errno48，创建的输出目录为空，尚无source/驱动/App启动或样本；详见diagnostics/accepted-3-startup-port-busy。随后lsof/netstat未发现监听/TIME_WAIT，同一普通bind检查成功；没有失败时的socket归属快照，因此只怀疑端口释放时序，不能定性。保留原日志SHA与零样本说明后人工启动第三轮，同冻结源码/素材/服务及存活QEMU不变，未修改runner超时或绕过端口检查。第三轮已有首个4K检查点，但仍未完成；READ-06、正常release与目标手机/NAS继续待验。

## 正式accepted-3完整通过；三轮逐项汇总核对通过

同冻结81a11a98、App树71e6caf、普通服务容器1b87c4f9与QEMU87970，第三轮四组各30次完整通过；1205次真实拖动覆盖全部500页，无漏页，同页切换、固定范围及返回来源通过。12个检查点PNG SHA核对，末尾图确为500/500与3包范围第1包，最终图已回媒体库。long-horizontal-end截在设置面板保存过渡，不能据此声称该截图中所有控件已可用；同页/模式由终态数据与后续返回共同证明。

| 本机profile指标 | 次数 | p50毫秒 | p95毫秒 | 最大毫秒 |
| --- | --- | --- | --- | --- |
| 4K缓存清空后打开 | 30 | 3288.073 | 4753.124 | 4844.062 |
| 4K相邻翻页 | 30 | 2942.317 | 3760.177 | 4159.368 |
| 8K缓存清空后打开 | 30 | 6222.590 | 6986.575 | 7249.085 |
| 8K相邻翻页 | 30 | 3741.494 | 4261.450 | 4704.375 |

nearest-rank，未过滤慢样本。单App PID18643，1489份内核采样：PSS峰值255.510MiB、RSS357.039MiB、已采到VmHWM363.441MiB；6 provider/49280400字节估算、120元数据、缓存53474704字节、实际像素2053350峰值。300份环境观察对应正确容器与QEMU，observer_errors为空，报告/采集线程/控制端/App停止收尾均通过；长包拖动1151.011秒，整轮约1844秒。帧总耗时最大8.331秒的卡顿也原样保留，不只报告较好分位数。

正式汇总器对三轮逐一通过，并确认同源码/容器/QEMU、每轮单一且轮间不同App PID；matrix-summary.json保留逐轮统计，不把不同阶段内存定义拼接，也不把失败轮/诊断n=1合并。fixture-after.json逐个读取全部506页并核对3,423,051,928字节SHA，均与生成清单相同。本段只是本机软件GPU/profile的完整稳定性与测量结果，延迟偏高；目标手机/NAS、物理IO与产品速度门槛、普通release入口仍待验证，#78/#89及父任务不关闭。下一步整合PR #98与构建原签名同code9配套包。
