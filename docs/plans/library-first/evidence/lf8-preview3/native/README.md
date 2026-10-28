# 普通 APK 的覆盖安装、回退与失败记录

本段使用冻结源码4dd88cac构建的普通release APK，实际顺序为 `preview.2/code8 → preview.3/code9 → rollback.3/code9 → preview.3/code9`。三个 `adb install -r` 均成功，原Windows签名、应用身份、首次安装时间与数据目录保留。全部使用同一个自有Android 36 AVD的数据，未卸载、清数据或使用降级标志。安装记录、完整偏好与21张业务表的明确前后比较见 [summary.json](summary.json) 和各 `*-install.json` / `*-check`；[manifest.json](manifest.json) 固定333份原始输入与汇总的字节/SHA，不包括本说明和清单自身。

已验证的操作：

- 新版冷启进入媒体库，列明启动窗口只GET，无重新登录或视频stream；21表和settings/access_tokens摘要不变。旧界面则保留原浏览页及已有范围自动播放，不能称旧版零自动播放。
- 新版通过真实UI开启深色模式，旧版保留；旧版关闭相邻视频准备，升回新版后保留。完整偏好中的顺序和无关服务迁移标记也保留。公开扩展字段样本来自前阶段测试设置，未声称全部字段由本轮UI生成。
- 图包第2/3张、纵向拼接实际呈现；视频 `LEGACY_ONLY` 和图包 `PACK_ONLY` 分别可见。任务页仍显示旧视频回收/撤销等记录，进入两套标签和任务页前后21表及登录摘要不变，保留11个任务。
- host GPU比较的前两轮完成阅读→返回→两套标签→设置。第三轮打开阅读时连接失败，原三轮脚本退出非零，不能计作三轮成功。服务/ADB/SQL仍响应；只读查询原session请求404。随后明确点击一次“再次提交原请求”，数据库新增的session仍使用该404请求ID，仅一次创建POST成功，第2/3张重新呈现。`request_records`新增项是随后opened回执，session请求身份应核对 `pack_sessions.request_id`，不可混淆。

本段中断了两次：QEMU41697（software，实际lavapipe/swangle）与53619（swiftshader/swangle）均被确认进程退出且ADB消失，宿主报告包含HangDetector路径。只在确认退出后重新启动原AVD，第二次改用host GPU作比较，App/SDK未改。原日志去除ADB公钥身份行，原SHA、脱敏SHA及所选宿主报告字段见 [diagnostics](diagnostics)；未公开含宿主标识的完整系统报告。不能据此判定App内存溢出、确定图形根因、证明host GPU修复，或宣称整条安装/阅读链无中断。

`requests-prefix.jsonl` 是开始独立大图阶段前冻结的817行/74738字节请求前缀，不含请求头/正文；之后服务继续运行不会改变此证据。无口令、安全存储token或真实收藏内容；SQLite只在拥有数据库的容器内只读事务观察。截图 `tap_label` 命名通常是点击前，明确 `*-page` / `*-after` 才用于相应结果，不能把点击前截图冒称结果。保留了一次UiAutomator根节点未就绪的只读重试警告和恢复阶段路径错误说明；这些不算产品通过项。

本段只有三张合成图片，不是500页性能结果。普通APK大图检查另列；真实手机/NAS、完整减少动画动作和持续稳定性继续。图包连接失败由[#100](https://github.com/ShiJiJS/video_viewer/issues/100)单独跟进，#78/#89及总验收仍开放。
