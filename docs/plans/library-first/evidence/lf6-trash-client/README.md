# LF6 双类型回收站、批量恢复与阅读回归检查点

功能实现 **524e89f**；大字号排布 **9de2ebb**。冻结原型仍独立在 `design/reference/library-first/`，没有为本次实现改原型。行为契约见[图包回收站设计](../../LF6-TRASH-CLIENT-DESIGN.md)。两个源码清单各214份文件，已逐项核对相应Git提交的字节；原生构建期间也断言源码不变。

## 客户端和服务端

- `client-full.log`：功能实现全量271项通过（34秒），`analyze.log`无问题。
- `client-layout-full.log`：最终排布全量271项通过（51秒），`analyze-layout.log`无问题。没有为排布改动削弱任何交互断言。
- 新增29项：12项真实HTTP回收分页/搜索/完整选择/协议/取消、7项批次与部分失败/丢失响应/连接/离页session检查、8项设置入口组件检查、2项Slider语义与延迟保存检查。组件覆盖390普通与360双倍字号；1027项跨批次恢复由session/HTTP检查覆盖，原生夹具仅27包，不混称原生千包实测。
- `server-focused.log`：本轮相关30项通过（15.02秒）；`server-ruff.log`通过。本轮只扩展隔离测试夹具，没有修改生产后端。完整182项服务端基线来自[上一检查点](../lf6-reader-cleanup/README.md)，不声称本轮全量重跑。

## Android真实HTTP

Flutter3.47.7/Dart3.13.5，API36专用AVD。驱动重建并复位8761的合成花卉图包服务，测试使用ServerLibraryRepository/公开HTTP接口；主8760与真实NAS未修改。故障为夹具在请求受理后返回503，或首次读取返回503，不声称是真实TCP断线或杀进程。

| 目录 | 视口dp/字号 | 源码清单 | Flutter结果 |
| --- | --- | --- | --- |
| 07-large | 360×740 / 2 | source-sha256.json | 44秒通过 |
| 08-normal | 390×844 / 1 | source-sha256.json | 49秒通过 |
| 09-normal | 390×844 / 1 | source-sha256.json | 46秒通过 |
| 10-reader-large | 360×740 / 2 | source-sha256.json | 67秒通过 |
| 11-reader-normal | 390×844 / 1 | source-sha256.json | 68秒通过 |
| 12-reader-normal | 390×844 / 1 | source-sha256.json | 67秒通过 |
| 13-layout-large | 360×740 / 2 | source-layout-sha256.json | 45秒通过 |

每轮目录内有原始runner/Flutter日志、host-events、请求轨迹、实际Android截图及proof。proof保存当时HEAD（可能是功能提交前的基线）、工作树标记、精确源码清单、各产物哈希与当次APK哈希；以对应源码清单确定功能来源，不能仅凭base_commit判断。同源重建不声称二进制相同。驱动只领取运行开始后生成的文件，未混入旧截图或错误文件。原图未裁切或修图。

### 图包回收与恢复（07–09及13）

先实际打开一包，显示第二页并通过设置切纵向/有间距，实际滚动并保存位置。通过公开API准备27条逻辑回收和一条独立视频回收；这一步不冒充27次UI删除。随后从设置→回收站→图包入口，首次列表503后明确重新读取，不显示假零项/空列表；全选完整27项，在24项分页之外保留选择，排除一包后第二页显示已选26。

恢复请求实际受理后返回503，页面保留待核对入口；查询只GET原回执，不再POST。继续恢复剩余一包，验证整包标签IDs、页码/纵向偏移/偏好和实际最近记录；视频回收条目不被图包选择/恢复影响。每个checkpoint的`*-files.json`均含81张生成JPEG的相对路径和SHA，已核对六阶段完全一致，证明这组逻辑回收/恢复不改变源字节。

六个阶段为reader、read-error、selected、unknown、restored、recent。初次错误界面在13显示完整错误/重试与未知总数，selected总数与按钮在双倍字号分行；正常与空列表状态没有因调整挤出操作区。

### 阅读连续整理（10–12）

每轮在25包固定标签范围内执行8次连续整理：第一次原有主路径，额外7次均输出`CLEANUP_REPEAT`并断言下一包实际opened，不只核对metadata。每次未知响应查询原回执、成功后进入同一范围下一成员，再准确撤销回第二页。之后仍执行普通阅读删除返回原查询/原session恢复，以及范围末尾结束。六张checkpoint保留ready、unknown、undo、resumed、tail、return；截图等待弹出菜单退出，末尾按钮在双倍字号无单字换行。

这里的通过不证明历史两次切下一包图片失败已修复；其原始记录继续留在上一检查点。未定位原因不能被后续通过覆盖。

## Slider语义故障的确定性诊断

本轮原生纵向偏好保存触发Flutter `_SemanticsGeometry.computeChildGeometry`的父节点断言。临时扩展SDK的assert消息，未改变条件，定位到Slider的内部GlobalKey/OverlayPortal在禁用期间更换语义父节点。`sdk-diagnostic-restoration.json`记录诊断前后原始SHA均为`292ef7c3a0995054054274827417820556e3afa8211977037460b30e6240aa51`；所有后续原生proof继续核对原SDK哈希。

`semantics-before.log`保留延迟保存组件测试在两尺寸上的同一断言失败；`semantics-focused.log`保留修正后13项通过，`semantics-drag.log`保留最终两项含实际拖动通过，全量271也包含该测试。App仅按可交互状态设置Slider ValueKey，使状态切换时重建其内部节点；保留语义、原禁用条件和异常断言，没有升级或打补丁发布SDK。

上游[flutter/flutter#193706](https://github.com/flutter/flutter/issues/193706)报告相同版本的Slider语义父节点问题；这是诊断参考，不宣称上游推荐本App的具体处理。该断言与历史下一包图片显示失败是不同问题。

## 视觉与尚未完成

主Agent查看13的read-error/selected、08普通unknown及10大字号tail实际截图，确认换行与相邻元素。沿用P2/Paper方向、14搜索字号及共享MediaCatalogToolbar，没有重做视觉系统。快速整理移除多余按钮图标，保留原动作文字；错误/总数采用大字号分行，不靠缩小文字。既有路由/Sheet与进度反馈保持原动效，本次尺寸修正不另加动画。未独立视觉评审，未对完整产品作一致性验收。

- 当前每批请求先持久化，已受理命令可查询；整份多批次计划尚未持久化。离页/切类型停止后续未提交批次，App关闭后未提交选择不能自动续作。统一任务整合仍需继续。
- 图包限定图片清单永久删除、双确认、逐文件阶段/故障恢复尚未接入。
- Android安全存储强杀重开、真实设备/NAS大图内存与性能、原签名升级和全部DEL/REC/UI组合仍未验证。合成缩小花卉不是大图性能证据。
- 未发布新版APK，LF6 issue与PR保持开放/Draft，LF7/LF8继续实施。

复跑图包回收：`bash scripts/dev.sh python3 scripts/run-client-connection-test.py --pack-trash --workspace-viewport 360 --workspace-text-scale 2`。

复跑阅读连续整理：`bash scripts/dev.sh python3 scripts/run-client-connection-test.py --pack-cleanup --pack-cleanup-rounds 8 --workspace-viewport 390 --workspace-text-scale 1`。

证据文件SHA索引为`evidence-sha256.json`，不包含自身和本README，避免自引用。
