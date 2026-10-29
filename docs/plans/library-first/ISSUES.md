# GitHub 实施任务

当前补证（2026-10-30）：[原版服务首页菜单](LF8-LEGACY-HOME-MENU.md)本机完成。正常preview.10/code16真实连接0.1.4镜像980c9a01（24个Python文件与f5fe32c9相同、无capabilities），普通/减少动画下取消、详情和快速整理进出均保持同一视频/位置；14张明细表及设置/令牌不变、19个成功GET/HEAD，无图包/管理误请求。切回新版35张明细表与设置保持，仅主动登录新增令牌。[109份输入、只读复核与恢复](evidence/lf8-legacy-home-menu/README.md)通过；原四服务/donor/媒体保持，App/服务/SDK/原型和两包未改。#110最后组合已补，初始模拟器安装路径异常/ART缓存差量单列，未定位原因；其它UI-06/45项与手机/NAS/有声等继续。

当前交付段（2026-10-30）：[菜单/下拉正常包 PR #114](https://github.com/ShiJiJS/video_viewer/pull/114)本机完成。preview.10/rollback.10同code16、固定a154d783/原Windows签名，额外完整766客户端/分析通过；三次基线覆盖保留身份/登录/完整偏好/21表，之后实际媒体库筛选/取消、多选、阅读设置、更多菜单、内嵌/全屏倍速及历史筛选通过，主动写入差量单列，旧UI菜单再回新两次覆盖保留操作后数据。[219份输入与只读复核](evidence/lf8-menu-dropdown-package/README.md)、环境恢复完成；原四服务/donor保持、旧14/15包保留。该段当时未覆盖的原版服务首页组合已由[后续补证](LF8-LEGACY-HOME-MENU.md)完成。原型独立未改，服务未改/未部署，目标手机/NAS、有声/云提供器、其它UI-06、45项终验和#78/#89/#100仍开放。

最新阶段：[复杂图包性能测量与诊断 PR #96（进行中）](https://github.com/ShiJiJS/video_viewer/pull/96)。新增两份公开摄影原图衍生的506页/约3.4GB夹具（500页长包含400页4K/100页8K），正常服务扫描无失败；profile重复计时、被动内核PSS/RSS/VmHWM与汇总工具已提交，生产App/服务/原型未改，正常安装包仍为PR #95配套版本。三处采集错误已修正并分开保留；SWANGLE/GLES出现bad color buffer/GL context异常，QEMU81429挂起并确认退出，该轮失败，不诊断为App OOM。现以同数据SwiftShader复测，另一次进度确认等待超时正补状态诊断；尚无完整30次分位数/三轮500页结论。真实手机/NAS与READ-06完整验收继续，#24/#33/#78/#89均不关闭。

当前视频预览：[全屏/后台行为 PR #77](https://github.com/ShiJiJS/video_viewer/pull/77)，45点/12段录屏与15项相关检查；实际绿边登记[#78](https://github.com/ShiJiJS/video_viewer/issues/78)，保留UI-02未通过状态。[台账](RESULTS.md)。

图包阅读阶段：[图包瞬断重试与500页/大图 PR #76](https://github.com/ShiJiJS/video_viewer/pull/76)，三轮原生、646项客户端与开发签名release构建的范围见[逐项台账](RESULTS.md)。#24/#33继续开放。

阅读器继续补证：[可见末张跳过 PR #57](https://github.com/ShiJiJS/video_viewer/pull/57)，原生三轮及兼容回归见 [LF5 记录](LF5.md)。整体原型对照继续。

阅读器最新补证：[失败末张与横屏操作 PR #56](https://github.com/ShiJiJS/video_viewer/pull/56)，固定源码/原始证据见 [LF5 记录](LF5.md)。LF5、LF8及总任务仍开放。

总任务：[媒体库与图包升级 #24](https://github.com/ShiJiJS/video_viewer/issues/24)。最新阶段状态统一见 [PLAN.md](PLAN.md) 和对应LF记录。当前LF8整体验收推进中，最新验证范围与未完成项见[RESULTS.md](RESULTS.md)；以下保留LF7实施历史：任务中心、整份恢复/停止、永久删除剩余选择及服务端默认值/本机迁移已接入；目录类型/启停和图包缺失管理已接入，实际验证见LF7证据；备份v2文件/校验和v1转换模块已落地，只读历史包与查询已落地，服务端恢复代次已接，App代次与历史分册由PR #51接入；完整替换协调、正式历史路由、有界传输及原历史删除专用清单/逐项结果已接入，三处v2 App强停及历史只读原生验证已补；其它命令/来源强停、历史图片资源错误及最终原型/目标设备继续推进，生产backup_v2仍关闭。近期草稿：[任务中心 #41](https://github.com/ShiJiJS/video_viewer/pull/41) → [恢复服务端 #42](https://github.com/ShiJiJS/video_viewer/pull/42) → [恢复App #43](https://github.com/ShiJiJS/video_viewer/pull/43) → [删除选择 #44](https://github.com/ShiJiJS/video_viewer/pull/44) → [真实1003包强停 #45](https://github.com/ShiJiJS/video_viewer/pull/45) → [设置默认值 #46](https://github.com/ShiJiJS/video_viewer/pull/46) → [目录与缺失管理 #47](https://github.com/ShiJiJS/video_viewer/pull/47) → [备份文件模块 #48](https://github.com/ShiJiJS/video_viewer/pull/48) → [只读历史 #49](https://github.com/ShiJiJS/video_viewer/pull/49) → [服务端代次 #50](https://github.com/ShiJiJS/video_viewer/pull/50) → [App代次与历史分册 #51](https://github.com/ShiJiJS/video_viewer/pull/51) → [完整恢复协调 #52](https://github.com/ShiJiJS/video_viewer/pull/52) → [App文件接线 #53](https://github.com/ShiJiJS/video_viewer/pull/53) → [v2 App真实强停 #54](https://github.com/ShiJiJS/video_viewer/pull/54) → [原历史删除明细 #55](https://github.com/ShiJiJS/video_viewer/pull/55)。以下依赖是实施顺序，不是完成状态。

| 编号 | 任务 | 依赖 |
| --- | --- | --- |
| LF0 | [[LF0] 锁定原型基线与可运行的模块骨架](https://github.com/ShiJiJS/video_viewer/issues/25) | 无 |
| LF1 | [[LF1] 兼容迁移数据模型：媒体类型、图包标签与服务能力](https://github.com/ShiJiJS/video_viewer/issues/26) | [LF0](https://github.com/ShiJiJS/video_viewer/issues/25) |
| LF2 | [[LF2] 图包扫描、分页目录与授权图片读取](https://github.com/ShiJiJS/video_viewer/issues/27) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26) |
| LF3 | [[LF3] 视频从入口范围进入固定预览会话，保留原生播放能力](https://github.com/ShiJiJS/video_viewer/issues/28) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26) |
| LF4 | [[LF4] 原生四入口外壳、双类型媒体库与独立标签页](https://github.com/ShiJiJS/video_viewer/issues/29) | [LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF3](https://github.com/ShiJiJS/video_viewer/issues/28) |
| LF5 | [[LF5] 图包阅读器：横翻、纵向拼接、范围与续读](https://github.com/ShiJiJS/video_viewer/issues/30) | [LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF4](https://github.com/ShiJiJS/video_viewer/issues/29) |
| LF6 | [[LF6] 图包快速整理、准确撤销及安全的回收站操作](https://github.com/ShiJiJS/video_viewer/issues/31) | [LF3](https://github.com/ShiJiJS/video_viewer/issues/28)、[LF5](https://github.com/ShiJiJS/video_viewer/issues/30) |
| LF7 | [[LF7] 设置完整接线、统一任务与兼容的管理备份 v2](https://github.com/ShiJiJS/video_viewer/issues/32) | [LF1](https://github.com/ShiJiJS/video_viewer/issues/26)、[LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF6](https://github.com/ShiJiJS/video_viewer/issues/31) |
| LF8 | [[LF8] 原型一致性验收、真实服务联调与兼容升级包](https://github.com/ShiJiJS/video_viewer/issues/33) | [LF0](https://github.com/ShiJiJS/video_viewer/issues/25)、[LF1](https://github.com/ShiJiJS/video_viewer/issues/26)、[LF2](https://github.com/ShiJiJS/video_viewer/issues/27)、[LF3](https://github.com/ShiJiJS/video_viewer/issues/28)、[LF4](https://github.com/ShiJiJS/video_viewer/issues/29)、[LF5](https://github.com/ShiJiJS/video_viewer/issues/30)、[LF6](https://github.com/ShiJiJS/video_viewer/issues/31)、[LF7](https://github.com/ShiJiJS/video_viewer/issues/32) |

当前依赖 PR：[LF0 #34](https://github.com/ShiJiJS/video_viewer/pull/34) → [LF1 #35](https://github.com/ShiJiJS/video_viewer/pull/35) → [LF2 #36](https://github.com/ShiJiJS/video_viewer/pull/36) → [LF3 草稿 #37](https://github.com/ShiJiJS/video_viewer/pull/37) → [LF4 草稿 #38](https://github.com/ShiJiJS/video_viewer/pull/38) → [LF5 阅读会话草稿 #39](https://github.com/ShiJiJS/video_viewer/pull/39) → [LF6 逻辑整理草稿 #40](https://github.com/ShiJiJS/video_viewer/pull/40)。

代码按任务分批提交，PR 引用对应 issue 和 [验收 ID](ACCEPTANCE.md)。方案、独立原型及合成夹具已随 LF0 纳入版本控制；提交、验证和当前边界见 [LF0 记录](LF0.md)、[LF1 记录](LF1.md) 与 [LF2 记录](LF2.md)。

旧 [#1](https://github.com/ShiJiJS/video_viewer/issues/1) / [#23](https://github.com/ShiJiJS/video_viewer/issues/23) 保持原状态，不把原型规划当作既有目标环境验收完成。


## 2026-10-26：LF8共享比例与收口入口

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)补齐两类库共享几何、设置与标签确认密度及独立复核证据；[RESULTS.md](RESULTS.md)现逐项登记45个验收ID。#33/#24保持开放，下一段优先真实续读区、权威类型总数、保守标题/作者与全范围排序一致性，详见[差异审计](LF8-SHARED-GEOMETRY.md)。本轮只有共享区域局部证据，不能替代完整管理/阅读/动作或目标设备验收。

## PR #88：系统文件、完整恢复与大文件取消

[系统文件备份往返与取消 PR #88](https://github.com/ShiJiJS/video_viewer/pull/88)。固定5373baa，小文件19,207字节与大文件40,964,503字节各一次真实系统保存／选取、HTTP上传、27目录确认及完整恢复，共24点、26张PNG；取消保存保留原任务与日志，取消选取没有导入或恢复。18,000条记录摘要、恢复后SQL投影及媒体SHA核对，271输入只读复核通过。生产代码未改、backup_v2仍关闭；下一步审计并开放正式完整备份能力、保留旧服务／v1兼容，再做发布前整版回归。不是三轮稳定性、客户端／服务端全集或目标手机验收，未发布APK；#24/#33/#32保持开放。

[实现边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-native-backup-roundtrip/docs/plans/library-first/LF8-NATIVE-BACKUP-ROUNDTRIP.md)／[固定源码与原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-native-backup-roundtrip/docs/plans/library-first/evidence/lf8-native-backup-roundtrip/README.md)。保留host文件读取引号、同名文档拒绝和遗留选择器启动诊断，中间流程不计最终24点；最终两例无需手动启动。图包版本按既有恢复规则＋1，SQL只比较明确投影，不称整库字节相同；Android实际处理未压缩文件，Git仅gzip保存同字节证据。独立原型与原四个服务未改，临时容器／显示／AVD已归还。

## PR #90：完整备份公开入口与旧版兼容

[完整备份公开入口 PR #90](https://github.com/ShiJiJS/video_viewer/pull/90)。开发源码已声明backup_v2、移除测试额外注入，旧服务入口／v1任务协议与默认32 MiB保留。2f62dd0完整回归：客户端670项、服务端447项通过；27个既有文件格式未过，与基线相同。6287cc4正式原生一轮14点／15图、283输入只读复核通过，公开入口、真实系统文件与完整恢复走通。偶发上传连接失败尚未定位，已登记[#89](https://github.com/ShiJiJS/video_viewer/issues/89)，一次成功不能算修好。下一步定位该失败并验证原请求保留／重开只读核对；仍为草稿，未部署正式8760／NAS或发布APK，#24/#33/#32/#89保持开放。

[实现／后续](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/LF8-PUBLIC-BACKUPS.md)／[固定源码与原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-public-backups/docs/plans/library-first/evidence/lf8-public-backups/README.md)。原生19,204字节同文件保存／读回SHA一致，27目录明确恢复、代次变化、两类后来标签移除与快照只预览通过；系统两种取消不新建导出／不上传。此前桌面无响应、上传失败、初扫409及文档XML未就绪分别保留；临时日志诊断通过不并入正式14点，通用传输未改、无自动重发。原型独立未改，容器／显示／自有AVD归还、原四服务ID不变。目标手机、云文档提供器、NAS及原签名覆盖升级仍待验收。

## PR #91：上传失败记录与真实进程找回

[上传失败原因与原任务找回 PR #91](https://github.com/ShiJiJS/video_viewer/pull/91)。App保留底层异常／等待阶段，提示及不重发写命令的规则不变；672客户端、28相关检查通过。848a1b8正式受控回复中断／双进程找回12点和普通完整恢复14点，共26点／28图，325输入复核通过；旧PID停止并移除本机输入后，新PID免口令只GET原任务、27目录预览且确认关闭。原始[#89](https://github.com/ShiJiJS/video_viewer/issues/89)未复现，原因／针对性修复仍未完成，不把已受理回复中断当作原始问题。先前host归还显示失败已修，原配置恢复后重新验证通过；服务生产源码未改，27个旧格式问题待处理。原型独立未改、资源已归还，未部署NAS／发布APK，#24/#33/#32/#89保持开放。

[实现与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/LF8-BACKUP-UPLOAD-DIAGNOSTICS.md)／[原始证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-backup-upload-diagnostics/docs/plans/library-first/evidence/lf8-backup-upload-diagnostics/README.md)。组件的真实拒绝连接／重建对象／缺少本机输入／两次原请求404，日志保留且零POST；明确区分内存日志与原生安全存储。受控样本读取回复时HttpException，重开14次GET、零POST、原键／同任务／SQL回执／代次相符；普通样本完整替换及快照只预览。中间d22d6fc覆盖屏幕配置变量导致归还失败，两例单列不计最终点，修正并使归还失败非零后重新验证。两类各一次，不称三轮稳定性；原始偶发原因、目标手机／NAS／云文档及覆盖升级继续。

## PR #92：正常入口预览包与原签名覆盖升级

最新阶段：[原签名预览包与覆盖升级 PR #92](https://github.com/ShiJiJS/video_viewer/pull/92)。固定cf992025，27个旧格式文件已修，139份服务Python前后AST相同；原型移除副本十步全部通过，客户端672项／服务447项。正常入口0.2.0-preview.1+6沿用Windows原签名，独立AVD实际APK5→6覆盖安装：免口令、原地址／设置及七表选定投影／登录摘要保留，新服务下启动进媒体库且零自动播放。两套标签、图包第2页横向转纵向／返回已实测；实际旧服务0004按原兼容模式保留视频UI。APK与Linux ARM64配套镜像仅输出本机预览，原型独立未改，未正式发布或部署NAS。完整服务迁移／回退、App回退、目标手机／NAS及其它验收继续；#89原始故障未复现、#78保持开放，#24/#33不关闭。

[安装与回退说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/library-first-preview.md)／[源码、原始记录和只读校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-preview-package/docs/plans/library-first/evidence/lf8-preview-package/README.md)。产物源码cf992025、证据4f82213，APK的SHA256为d87e98c70d4999b50165ce854f2e4f7156d25cc378f0431ed885f061c1cb9f87。旧／新包首次安装时间及数据目录相同，新PID启动26次GET、没有登录或自动流请求；深色开／相邻准备关保留。图包合成三图2/3实测，不冒充高分辨率长图包或真实手机验收。旧服务兼容可能按旧逻辑直接播放，完整新媒体库需要配套新服务。独立5556及8771/8772已归还，原四服务ID和运行状态不变；服务归档仅linux/arm64，正式NAS部署还需核对实际环境。

## PR #94：视频任务状态与真实旧数据升级回退

[草稿PR #94](https://github.com/ShiJiJS/video_viewer/pull/94)基于#92。服务源码b79da7b9、证据1b31995，正常runtime为preview.2，App仍是cf992025的正常release APK6，客户端生产源码未改、未重跑客户端全集。真实旧任务成功1/失败0却显示待核对，已登记#93并修正；旧JSON/回执不改，异常与部分成功保持原分类。最终15项新增检查在旧代码5失败/10通过，修正后相关21项、完整服务462项及Ruff/格式通过。

`accepted-1/2/3`三轮同一公开样本全部完成：2视频（可用1/回收1）、1标签2关联、原轮次2成员及3请求记录，正常启动迁移0004→0014，自动快照旧表相同；原凭据免口令，新媒体库无自动内容，旧任务已完成、原回执不变。UI新建标记标签后停机恢复完整基线，核对容器内版本/完整性/SHA，再启动原旧镜像，旧UI及原记录保留、标记消失。六个App PID、51成功图（另3基线/5诊断）、336输入只读复核通过；控制登录窗口单列，不冒充整份trace零登录。

首次cf任务问题、一次QEMU退出与一次旧容器首启报告0014而宿主恢复为0004的失败均保留，未计入最终三轮；后者原因未确定。最终驱动关闭SQLite连接，在原绑定目录和数据库文件内恢复内容，并先做容器侧核验。当前三轮通过不等于#78已修复。最终自有AVD关闭、11容器移除，原四服务ID/状态、上一阶段数据与媒体SHA未变。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/LF8-UPGRADE-ROLLBACK.md)／[固定源码、原始记录与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/plans/library-first/evidence/lf8-upgrade-rollback/README.md)／[配套安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-upgrade-rollback/docs/library-first-preview.md)。本段补UP-01/02和SET-05明确组合；App回退包、真实手机/NAS、当前新服务配旧客户端完整终验、禁用根其它组合及其余原型验收继续。#89原始上传故障未复现，#78仍开放；原型1cbf605保持独立可移除，未正式发布或部署NAS，#24/#33/#32保持开放。

## 2026-10-28：App回退包与反复覆盖安装（PR #95）

最新阶段：[原签名App回退与反复覆盖安装 PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)。固定a3c7659a，配套新媒体库0.2.0-preview.2和旧界面0.1.4-rollback.2均code8、原Windows签名。旧界面窄适配保留新版偏好/多范围日志及凭据代次，未知v2备份任务保留并要求回新版核对；85旧版/兼容+14新版相关检查、双方analyze及正常release通过。独立Android36同一QEMU实际6→新8→旧8→新8→旧8→新8，五次install -r、首次安装时间/身份/数据目录保持、六次免口令冷启，新版零自动播放。旧UI主题/相邻准备修改后新版顺序/迁移标记保留；旧视频回收/菜单撤销完成，升回任务可核对；图包第2页纵向/两套标签保留。148输入及两包只读复核通过，22组原生截图；一容器/自有AVD已归还，原四服务及前阶段数据/媒体未动。配套服务仍b79da7b9 preview.2，原型1cbf605独立未改；未正式发布/部署，目标手机/NAS、500页高分辨率和其余终验继续，#78/#89与#24/#33保持开放。

[方案和边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/LF8-APP-ROLLBACK.md)／[固定构建、两轮实际安装与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/plans/library-first/evidence/lf8-app-rollback/README.md)／[安装说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-app-rollback/docs/library-first-preview.md)。本段只补UP-02的本机App回退组合。内部code相同可反复替换已在该AVD实测；不能覆盖code>8，后续版本需同步生成回退包。切换前先完成/核对管理任务，进行中或未知v2任务不交旧版接管。偏好扩展字段使用明确公开文件样本，再经真实UI写当前迁移标记；不把文件样本称为全由UI生成。原旧界面、播放器和API业务保留，属于附兼容存储的回退包，不是原Windows APK字节复刻。当前新服务配旧客户端只核对列明组合，完整旧功能/禁用根其它组合、目标手机/NAS和其它终验继续。

## 2026-10-28：复杂图包性能测量（PR #96，进行中）

两份公开NASA/JSC摄影图以原像素裁切拼接为506页/3,423,051,928字节：500页长包中400页4000×6000、100页8000×8000，另两类各3页。是摄影像素压力样本，不是506张独立照片，不代替真实图包/SMB。正常runtime preview.2完整扫描无失败，解码子进程峰值152624KiB；生产App/服务及原型未改，普通安装包仍按PR #95。

新增独立profile入口，计划每类30次Flutter缓存冷首图、正常相邻翻页、连续拖过500页、内核PSS/RSS/VmHWM和帧时序；静态检查通过，原型独立。前三次采集错误（异步tester保护、控制消息分块协议、Tooltip类型）分别修正/留档，不算产品故障。随后SWANGLE/GLES在8次4K重复后bad color buffer/GL context异常、QEMU81429挂起并离开进程表；内核PSS采样最大196416KiB、RSS高水位297432KiB，不能据此诊断App OOM。只在确认进程消失后换官方CLI支持的SwiftShader复测；另一次进度确认等待超时，正在加完整状态诊断，尚未归因。所有失败均不算成功轮次，不用8次样本冒充30次分位数。

[方案](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/LF8-READER-PERFORMANCE.md)／[当前诊断记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-reader-performance/docs/plans/library-first/evidence/lf8-reader-performance/README.md)。完整30次、三轮500页、普通release入口与目标手机/NAS仍待完成；#78/#89与#24/#33保持开放。指定SMB目录在Mac可读，目前只确认路径可达；未把它当成真实图包已验收，未扫描/修改真实收藏或NAS服务。
