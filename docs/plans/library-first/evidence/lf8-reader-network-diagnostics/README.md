# 阅读命令诊断与模拟器音频对照

App/专用诊断入口固定 `edb4a235a33fd35357289ce8f64fc8e4e00f32f0`，App树d2c497a6；启动器固定5b84b9b7。正常preview.3/rollback.3两包SHA重新核对未变，尚未生成包含本段诊断改动的下一版正常配套包。原型树1cbf605仍独立可移除，服务生产树/镜像与SDK未改；sdkmanager当前installed/available中的emulator均37.2.12。

修复的是诊断信息丢失：阅读会话现在在内存中保留最近一次命令的原ApiFailure、命令种类、请求ID和是否回执查询。UI仍显示安全提示，记录销毁清除，不写盘/上传或自动重发。677项完整客户端、17项相关检查、analyze通过，17项属于全集不重复累加。真实已关闭连接的检查保留实际IOException及阶段；已有503→404→明确重试检查核对同请求和诊断身份。初始测试把关闭已有连接误固定为opening，实际等待响应头时发现关闭，修正了测试时序假设，没有调整生产传输。没有据此称原#100已复现。

| 独立profile诊断阶段 | QEMU | 完整操作循环 | 驱动退出 | 终端报告 |
| --- | --- | --- | --- | --- |
| host GPU / 音频开启 | 87639 | 11 / 12 | 1 | 缺失，VM服务随模拟器消失 |
| 同AVD增加-no-audio | 94046 | 12 / 12 | 0 | 正常收到，bounded_sequence_completed=true |

每个循环实际从媒体库续读第2张、等待当前帧确认，再Android返回、视频/图包独立标签和设置；进入前有限等待0/4.8/5.2/9.5秒。第一阶段第12次session/图片/opened已200/201，但后续UI循环没有完成，不能算第12次通过。两段245/251条完整请求窗口均为2xx，没有捕获命令ApiFailure；原普通APK第三次创建连接失败仍由[#100](https://github.com/ShiJiJS/video_viewer/issues/100)跟进。第一段不能伪装成完整成功，第二段一次12循环也不等于长时间稳定或三轮验收。

第一段退出后核对PID/ADB均消失才重启同一AVD；SDK、host GPU、App、同一服务容器/数据/媒体均保持，第二段直接复用同一profile APK，SHA `80dafb1b6756cbd6f680abe187f9f8931d36bb973e75f985128e3fcfcb119536`。没有重置目录或剔除第一次失败。profile入口、内存登录及诊断回传与正常release入口有区别，不能用本段替代手机/NAS或正常APK验收。

四份宿主报告（87639/53619/41697/90728）共同出现CoreAudio初始化等待，主循环/其它vCPU等待qemu_mutex_lock_iothread，见[audio-lock-comparison.json](audio-lock-comparison.json)。这给出音频阻塞线索；缺少锁拥有者的完整因果验证，不能确定所有退出根因，也不是App OOM证据或原视频绿边修复。原系统报告保留私有，只公开所选符号、原SHA和必要终止字段，不公开宿主UUID。QEMU日志仅删除ADB公钥身份行；驱动日志仅替换临时localhost VM服务URL，脱敏前后SHA和次数分别保存。

[Android官方说明](https://developer.android.com/studio/run/emulator-commandline)明确-no-audio禁用模拟器音频。本次对照支持只为不需要声音的阅读诊断启用此参数；有声播放不在本段验收范围。启动器增加显式VV_EMULATOR_AUDIO=off、默认on，10项隔离CLI检查通过；真实PID94046的off复用返回0、请求on返回3且PID/命令未变。参见[Mac开发说明](../../../../macos-development.md)，未改F5默认任务或Windows启动器。

已恢复AVD进入本阶段前的实际显示覆盖（1170×2532/480，而非假设物理默认），正常关闭，专用容器移除；原四服务ID/健康保留、源donor数据全部SHA相同，实验数据目录保留。第一次按物理默认reset的准备断言失败，随后按真实保存值纠正，未计作测试通过；记录在第二段recovered-display-before-test.json。SQLite只在其容器内只读观察；本段没有21表逐行前后比较，不将次数快照称整库不变。

结果、原始请求窗口、组件/CLI日志、source及清单均在本目录。#24/#33/#78/#89/#100保持开放；没有正式发布APK、部署NAS或读取私人收藏。
