# 扫描详情：真实 Android 展开验证

固定测试源码 `0846cdecd0672b340824cdfacb7ead54139cc232`。生产 lib 与源码阶段 `6af88978` 完全相同，沿用该段 789 项客户端、12 项针对检查（含 32 组完整 RGBA/尺寸）和分析结果。本段只增加真实 Android 测试入口，未修改生产 App、服务、SDK 或独立原型。

只读复核（不启动设备、服务或访问数据库）：

```sh
python3 docs/plans/library-first/evidence/lf8-expansion-native/verify.py
# 可选：重新完整解码三份成功录像，需要 ffmpeg
python3 docs/plans/library-first/evidence/lf8-expansion-native/verify.py --decode
```

manifest 固定每份输入的字节/SHA，不含 APK。`verify.py` 从原始帧重新计算，不只读通过标志。其它 runner/audit/cleanup 是当时本机执行记录，依赖私有工作路径，不能作为公开只读入口运行。

## 唯一完整成功轮 native-4

三轮实际 LibraryHome 目录页，每轮普通/减少/运行中切换的展开与收起，共 18 个方向、136 个逐帧观测、6 次真正中途切换。实际 ADB 点击和三个系统动画比例的读回保留；原生 PlatformDispatcher 与 MediaQuery 标志相同，普通控制器 160ms，减少时 0ms。公开 Element 遍历观测实际 Align 高度、RenderBox 像素高度和 RotationTransition 箭头：普通有中间态，切换前一帧严格在 (0,1)，首个原生减少标志帧直接到目标。箭头与高度一致，到位后再采三个 vsync 仅确认端点，不证明空闲帧率或性能。

每轮额外一次原生点击，收到真实 pointer-UP 后请求一个 40ms 真实 Timer，在回调中记录最近已绘制的严格展开中间态，再让只读 fixture 替换扫描状态。40ms 是 Timer 请求间隔，不是精确输入到显示延迟。三次额外点击与 18 个动画方向分开计数；扫描中/失败/完成共 9 个状态，核对标题、错误详情和正确一份卡片。完成时原摘要恢复且折叠。夹具不执行扫描、文件或任何业务写命令，不是正常 main 真实服务验收。

三份 `native-4/round-*.mp4` 1170×2532，分别完整解码并独立重解码；每份导出 0.45 秒原完整帧 `*-visible-detail.png`，代表图已查看，实际详情可见。扫描/失败/完成各有原始截图；录像与原生标志不声称绝对时钟同步。host 事件应为 tap15（普通/减少12+状态3）、tap_reduce6、capture9、begin/end各3；原始事件和复核器均核对。

## 三次未通过尝试

全部同一 QEMU60176，分开保留，不累计到成功计数；各次均完整恢复进入配置，observer_errors 为空。

1. native-1：六个方向通过；等宿主 tap 回复后才找展开中间态，此时160ms已结束，状态替换前等待超时。实际失败截图显示点击已落下、详情展开。改为在原生UP后本地真实Timer触发夹具更新。
2. native-2：六方向通过；Timer内观察函数调用测试 expect，触发 OutsideTestException，尚未记入生命周期。将观察改为公开节点的纯读取，所有断言移到测试控制流；未改生产组件。
3. native-3：六方向和扫描中状态通过，已抓到 value约0.104/height约0.0182 的真实展开中间帧。随后 failed更新只等一次pump就读值，benchmarkLive下一帧尚未绘制，仍读到扫描中文字。最终改为等待实际渲染字段达到目标，再执行相同严格断言，未放宽文字、详情数量或中间态条件。

失败轮各有一份finally回收的完整解码局部录像，不能当作完整三轮成功录像。v1–v4测试源码、构建元数据与原日志各自固定；同字节长度不等于同APK，v2/v3/v4 SHA均不同。第一次v4精确文本替换在写文件前因缩进不匹配中断，analyze6仍针对v3；正确应用后analyze7通过，才提交/构建最终v4。该脚本诊断未改生产模块。

## 环境与边界

自有 reader_perf_36/emulator-5558、QEMU60176，host GPU/GLDMA off/HardwareDecoder on、无声无窗口。进入前已有1170×2532/480覆盖；每次恢复这些原值、字体/旋转、空secure值以及transition/window=1.0和缺失animator值。保持进入时uid2000 shell，不执行root/unroot。最终关闭自有模拟器，原四服务完整ID/健康保持，未新建业务服务、访问SQLite或操作用户媒体/NAS。

正常code17两包、固定SDK文件及独立原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 均由本机审计核对保持；没有新增正常安装包。本段完成 #120 的真实Android项；正常main目录/实际扫描状态与后续配套包、完整45项/其它动画和手势、手机/NAS/有声/云提供器及 #78/#89/#100仍待验证。
