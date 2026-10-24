# LF6 普通卡片回收与客户端回执

实现与客户端检查点 **8efae13**。当前lib/test/pubspec/服务端177份文件逐字节与此提交一致，SHA见 `source-sha256.json`。后续e6b34c6只调整原生测试的可观察等待，没有修改这里的App实现、组件测试或服务代码。

- 完整 **223项客户端测试通过**（日志32秒）：`full-client.log`。
- 33项操作/卡片/面板/既有标签名称专项通过：`focused-client.log`。其中新增26项：18项HTTP/记录/协议/时间模型、6项面板与3尺寸状态、2项应用卡片流程；另7项保留既有名称与搜索断言。
- Flutter analyze通过：`analyze.log`；最终原生等待代码的静态检查见`final-analyze.log`。
- 完整 **180项服务端测试与Ruff通过**（222.23秒）：`server-checks.log`。同一服务实现仍使用只读挂载、禁网和64MiB共享内存环境；此前后端检查点的日志独立保留。

## 实际验证范围

先保存固定nonce/负载再发POST，本机写入失败不发请求。真实HttpServer夹具返回已提交后的503时，重建repository从同一本机记录查询原回执，只GET、不补POST；404保留记录。不同图包不被一个未知请求全局锁住。记录按服务endpoint/server_id分区，连接更换拒绝迟到结果，旧键同内容合并/异内容拒绝。坏记录不覆盖，错误类型/成员/计数/任务身份不清除意图。重试响应丢失走独立只读重试回执并保持原任务身份。

面板验证确认前零POST、确认后一次、保存原对象名/数量、失败与404留原对象、明确重发、采用旧请求、处理中关闭不接受迟到UI结果。应用级widget路径从真实卡片更多入口走整包确认、移除、撤销与原搜索/标签读回；另一条在已回收卡片消失后，通过列表待核对入口只读确认原请求，未多发删除。

服务端新回执带当次server_time，客户端按服务端剩余期限减去本机接收后的经过时间，最多8秒。纯模型用1970年/2096年服务时钟验证与本机时间无关的8秒窗口、1.25秒后剩6.75秒及期限后无撤销。旧回执缺server_time时兼容绝对期限，但仍最多8秒；最终超时由服务端拒绝，旧按钮只能指向原operation。

HTTP夹具返回503表示“服务已接受但客户端未确认”，没有伪称真实TCP掉线。本机重建测试使用共享MemoryFileCommandStore，不冒充Android加密存储、强杀或安装升级验证。正式App在main中接入独立SecureFileCommandStore键。

## 组件画面与边界

[320普通](screens/confirmation-320-1.png)、[360双倍字号](screens/confirmation-360-2.png)、[390普通](screens/confirmation-390-1.png) 为真实Flutter组件截图，含面板对象名称、数量、确认和保留规则。使用仓库PaperSerif与从专用模拟器只读领取的NotoSansCJK，字体SHA见`font-source.json`；不上传字体文件。生成/验证日志见`visual-client.log`。截图未经裁剪/修图，底层“打开操作”是组件测试宿主；这些不是App原生整包回收截图，也不作为完整原生验收。

主Agent检查三个实际字形画面，双倍字号自然换行，主按钮与关闭均保留。复用Paper/SheetFrame、危险动作颜色、浮层和SnackBar动效，未重设计字体/网格比例。确认规则按冻结原型保留。未做独立视觉评审；当前截图不能证明真机、系统键盘或完整原型一致性。

复跑组件图（Mac）：从专用emulator-5554只读pull `/system/fonts/NotoSansCJK-Regular.ttc`，设置`LF6_CJK_FONT`到本机字体文件、`LF6_WIDGET_SHOTS`到输出目录，再运行`flutter test test/pack_file_action_test.dart --plain-name 'whole-pack confirmation'`。不设环境变量仍能执行组件回归，只是不生成这些实际字体画面。

当前只接普通卡片回收与列表回执核对。阅读器快速整理、双类型回收站、限定文件清单的永久删除与完整DEL/REC/UI原生验收仍需实施。另有[本次菜单/标签原生回归](../lf6-tag-menu-native/README.md)，范围是标签名称流程，不代替整包回收原生验收。
