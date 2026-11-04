[GitHub #100](https://github.com/ShiJiJS/shika/issues/100)，保持开放。

关联 #24 / #33 / #30。普通安装包 `0.2.0-preview.3+9`（冻结4dd88cac）反复从媒体库继续阅读三张测试图包，第三次出现“暂时无法连接服务”，停在准备阅读范围。前两次完整阅读→返回→两套标签→设置通过，第三次脚本非零退出。

此时QEMU61904仍运行、ADB正常；本机两个测试服务health返回200，容器内SQL可读，library-state继续返回200。原session请求只读查询404；请求ID为 `1793205432692561-2536143785-4`。服务完成日志中没有此次失败创建POST。未采到该次底层IOException及发生阶段，不能只凭完成日志断言传输失败具体位置。

用户路径中的“再次提交原请求”明确点击一次后，只有一次 `/api/v1/pack-sessions` 创建POST返回201，新增session的request_id与原404查询一致，第2/3张纵向图片重新呈现。随后opened回执另外进入request_records。查询后到明确点击前只有GET；未通过自动重复写命令掩盖失败。

[普通APK记录与原始证据](https://github.com/ShiJiJS/shika/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview3/native/README.md) / [汇总](https://github.com/ShiJiJS/shika/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-preview3/native/summary.json) / [草稿PR #99](https://github.com/ShiJiJS/shika/pull/99)。两次此前QEMU退出单列在#78；本次进程未退出。与备份上传#89只是提示相似，目前没有相同根因证据。

- [ ] 捕获底层传输异常及打开连接/发送/等待响应等实际阶段。
- [ ] 建立有边界的复现，并据此修复，保留前后对照。
- [ ] 重复进入/返回和连接切换稳定通过；不能用无界重试或自动重发POST代替修复。
- [x] 本次原请求404和一次明确重试恢复的同请求身份已核对。

没有修改正式服务、SDK、真实收藏或App生产传输逻辑。本条保持开放。

## 后续诊断

edb4a235补阅读会话内存中的原命令异常/阶段/请求ID，677完整客户端、17相关检查通过，没有调整连接池、正文或自动重试。带音频host轮11/12后QEMU退出，不能计完整通过；四份宿主报告共同有CoreAudio等待和QEMU锁等待。只增加-no-audio、同一profile APK/服务/数据的对照12次完整收尾，未复现原创建连接失败；这不是原#100修复或有声播放验收。启动器5b84b9b7增加显式音频参数和不符拒绝，默认on。

[边界和后续](../LF8-READER-CONNECTION-DIAGNOSTICS.md) / [原始记录](https://github.com/ShiJiJS/shika/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-reader-network-diagnostics/README.md)。会话诊断丢失已补；原始失败的实际阶段/原因、针对性修复与稳定性要求继续保持未勾选。正常preview.3两包SHA未变，专用资源已归还，原型继续独立可移除。
