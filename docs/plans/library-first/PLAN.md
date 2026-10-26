# 媒体库与图包改造实施方案

## 2026-10-26：图包库真实继续阅读（PR #59）

[Draft PR #59](https://github.com/ShiJiJS/video_viewer/pull/59)基于#58，固定源码c4aaf3b，证据提交daf1863。图包媒体库在无筛选/搜索且非多选时显示真实最近打开包与页码；摘要独立于24条分页和列表取消通道，只读且不创建历史。点击从该包续读，保持原媒体库完整范围，返回原位置。搜索、多选、最近来源不展示全库续读条；失败保留列表并就地重试。

普通三轮、360双倍字号及844短横屏共五轮同源码通过，每轮10个真实前台检查点，共50图；公开2视频/4包/24PNG，实际打开后从3/6翻到4/6，续读仍为完整4包范围。两次显式opened、SQL最近/进度/会话投影、只读区间、26个源文件SHA与设备配置恢复均核对。202份manifest输入只读校验通过。客户端471项、服务端续读/阅读16项、analyze/Ruff通过；不是服务端全集或目标设备性能证明。

原生字体的实际行高取代估算，普通续读86dp（参考85）、双倍字号147dp，无裁切；共享“更多”菜单收起搜索键盘，修复短横屏进入多选时的4.7dp溢出。两轮独立存量视觉复核后无本段必须修正项；首轮材料、字体/键盘失败诊断与最终五轮分别保存。长标题/错误说明省略仍是已知显示边界，未缩字号或缩短压力输入。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/LF8-PACK-CONTINUATION.md) / [原始证据与可重跑校验](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/evidence/lf8-pack-continuation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-continuation/docs/plans/library-first/RESULTS.md)。本段补LIB-02、NAV-02、READ-04/05、REC-01与UI-01/04/05的明确组合，不关闭整项；使用MemoryCredentialStore，不新增强杀/安全存储或覆盖升级证明。

下一步继续权威两类总数、保守标题/作者与服务端排序，再核对完整预览/阅读/管理、键盘和手势；500页4K/8K、目标手机/NAS和原签名升级仍待验证。冻结原型1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：共享比例与45项原型收口台账（PR #58）

[Draft PR #58](https://github.com/ShiJiJS/video_viewer/pull/58)基于#57。固定App/最终取证源码`a9da395`，证据提交`6b71cd1`：两类库统一搜索55dp/输入42dp/文字16dp、范围工具60dp，顶栏与300dp居中导航对齐；设置分组和约40×24可见开关收回原型比例，整行至少64dp可点，支持单一开关语义与键盘，原回调和存储保留。标签确认区去掉过多留白，输入填色和设置说明已调整。

真实8768新库的2视频/4包/24图，普通三轮、360双倍字号与844短横屏各一轮通过，共40个ADB检查点；16项针对组件检查、analyze/Ruff通过，235份manifest输入独立复核通过。独立存量视觉评审两轮后，本轮布局项已复核处理；早期主题过渡帧、屏外懒加载前置和组件测试清理失败单列诊断，不混入正式成功。服务端/全部业务全集本轮未重跑。

新增[45项收口台账](RESULTS.md)、[尺寸与明确差异](LF8-SHARED-GEOMETRY.md)和[原始证据/只读校验](evidence/lf8-shared-geometry/README.md)。正常原生窗口390×905，实测49/24dp安全区，和HTML390×844移除12px模拟区后按390×832内容比较，不拉伸全屏。大字/横屏另按实测安全区记录。

下一步按台账补图包继续阅读区、权威类型计数、保守标题/作者呈现与服务端排序/分页一致性，再收口完整预览/阅读/管理/键盘/动作。500页4K/8K、目标手机/NAS和原签名覆盖升级仍待验证。原型树1cbf605独立可移除，生产backup_v2仍关闭；未改正式8760/NAS/SDK或发布正式APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：按实际点中的可见末张跳过（PR #57）

[Draft PR #57](https://github.com/ShiJiJS/video_viewer/pull/57) 基于 #56，固定源码 `07d1cad`，证据提交 `92f08b8`。纵向视口顶部仍在倒数第二张时，可以点击下方可见的失败末张。旧逻辑按顶部index拒绝该点击；现按所点图片进入原末尾页，不自动换包，不把失败图片记成首帧或完成进度。

新真实HTTP组件检查在旧逻辑失败，修正后与原五项图片检查共6项通过；完整客户端457项、analyze及夹具/脚本Ruff lint通过。服务端生产代码未改，402项全集沿用#55且本段未重跑。原生390×844普通字号三轮59.20/39.59/38.89秒，顶部index=1、点击图片index=2、比例约70.94%，关键点击没有先滚动对齐；进度前后完整对象相等，包含revision与更新时间，返回原失败末张、退出重开恢复原页/比例，明确下一包才推进。独立SQL仍是上一张真实图片、未完成。

另按同源码跑既有末张/损坏图片844横屏回归一次35.93秒。三轮加兼容回归共21张实际窗口截图、6张源图前后SHA、原始HTTP与SQL投影已保存；119份manifest输入独立复核通过。普通字号三轮不冒充其它视口组合或安全存储强杀验收。

[核查与修复说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/LF5-VISIBLE-PAGE-SKIP-AUDIT.md) / [固定源码与证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/evidence/lf5-visible-page-skip/README.md)。本段补READ-02/04/05与PKG-03的明确组合，不关闭整项。接下来推进整体原型对照；其它异常/连接恢复/迟到图片、500页4K/8K性能、目标手机/NAS及原签名发布仍开放。生产backup_v2仍关闭，冻结原型1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24保持开放。


## 2026-10-26：失败末张与横屏错误操作（PR #56）

[Draft PR #56](https://github.com/ShiJiJS/video_viewer/pull/56) 基于 #55，固定源码 `e68f487`，证据提交 `fc97f17`。原型 advance(1) 越过末张会进入 finished；App 原来把“跳过这一张”截回失败末张，且禁用了末张“下一张”。现已接到原生现有本包末尾页，可返回末张/来源，只有明确点击下一包才切换原固定范围；失败图片没有首帧，不写opened、最近、进度或完成状态。

沉浸中到达末尾显示工具，返回动作在黑色画布用白色保持可读。真实844横屏发现17像素溢出，失败/末尾区改为短视口可滚动，保留字体和操作。五项真实HTTP 404/HTTP200非图片解码及完整阅读路由检查回放旧生产代码全部失败，修正后通过。

完整客户端456项、analyze和新夹具/脚本Ruff lint通过。客户端全集在bc3c9fb执行，lib/test树与最终源码相同，最后仅改取证滚动；服务端生产树未改，402项全集沿用#55且本段未重跑。固定源码三轮（360双倍字号37.84秒、390普通36.09秒、844横屏38.74秒）通过，18张实际前台截图、六张源PNG前后SHA、原始轨迹及独立SQL投影保存，253份manifest输入已复核。SQL证实异常包没有progress行、recent只有手动进入且真实显示首帧的正常包。旧源码成功、17像素溢出、测试等待/取证偏移等开发记录单独保留。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/LF5-IMAGE-ERROR-DESIGN.md) / [固定源码及证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/evidence/lf5-image-errors/README.md)。本段补PKG-03、READ-01/02/04/05、UI-04/05的失败末张路径，不关闭整项。其余图片错误码/连接恢复/迟到图片、500页4K/8K性能、全原型与目标手机/NAS、原签名发布仍开放；本段使用MemoryCredentialStore，不作为强杀/安全存储证明。生产backup_v2仍关闭，冻结原型树1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24继续开放。


## 2026-10-26：原历史删除清单与逐项结果（PR #55）

[Draft PR #55](https://github.com/ShiJiJS/video_viewer/pull/55) 基于 #54，固定源码 `cabbc68`，证据提交 `0e0c1a5`。设置→操作任务→历史详情现可查看原确认清单、包内精确文件及永久删除的原图片/目录结果。三个认证 GET 绑定原 graph、父任务、计划与包条目；缺失或无效关联不退回当前库。文件 manifest 在 SQLite 内分页，App 专用网关没有执行、重试删除或结算能力，旧服务及缺失原图明确说明。

原生隔离8763真实扫描27包/153图，0101.png权限失败后实际126图已删、27图未完成；完整恢复后读回原历史。27包末3包、127图末页、54项目录、查询503保留原页再同GET重试及原预览入口均通过。固定源码三轮（360双倍字号64.96秒、390普通55.14/58.00秒），21张实际窗口截图、54份剩余源文件、原历史SQLite与三份真实安全日志前后核对；274份manifest输入已入库并独立校验。Paper比例延续既有页面，两尺寸目录结果及“图包根目录”文案复核通过。

完整客户端451项、服务端402项、analyze、Ruff lint和132份Python语法检查通过。服务端全集启动于9199f31、客户端全集于619033c，其完整服务端/客户端lib及test树均与固定源码相同。Ruff format继承23份、Dart format继承2份既有文件，未误报全量格式通过。实际43,806,720字节SQLite/18,000条manifest的分页Python分配峰值2,550,992字节，不能当作进程RSS、Android内存或NAS性能。首次Docker未加仓库规定shm参数的401通过/1失败、原生定位/等待失败和旧源码成功均单独留存。

[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/LF7-PURGE-HISTORY-DESIGN.md) / [原始证据与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-history-purge-details/docs/plans/library-first/evidence/lf7-purge-history/README.md)。本段补齐BAK-03、SET-05、DEL-04/06的历史读取部分；其它命令/来源强停、历史图片解码/资源不可用、全原型暗色/横屏/手势、目标手机/NAS及原签名发布仍继续。生产backup_v2仍关闭，冻结原型树1cbf605独立未改；未改正式8760/NAS/SDK或发布APK。LF7/#32及总任务/#24保持开放。


## 2026-10-25：v2 App 三处真实强停与原日志重开（PR #54）

[Draft PR #54](https://github.com/ShiJiJS/video_viewer/pull/54)基于#53，固定源码2839c5d。真实v2完整替换在snapshot_written、after_replace_before_commit、restore_committed三个服务位置扣留202，安全日志先落盘；宿主强停活跃PID并确认消失后，服务在App缺席时完成同一任务，新PID免口令自动重连新代次。六条旧本机意图、原私有文件和两个真实受理的图包任务/原graph成员都保留；重开只GET和既有启动扫描，不重发原写入。实际系统快照保存取消后不结算旧记录，历史未提交选择不能继续删除。

固定源码三轮（360双倍字号115.47秒、390普通79.17/81.29秒）通过，164份manifest输入已入库并独立核对；首段有意强停的非零退出和开发失败日志分开保留。analyze/Ruff/Python语法及24项服务端针对检查通过。App/服务端生产树未改，433/398项全集沿用#53且本轮未重跑；这里不是40MiB全路恢复、Android内存或整机断电验证。[契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/LF7-ARCHIVE-RESTART-DESIGN.md) / [固定源码、原始日志与独立核对](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-archive-restart/docs/plans/library-first/evidence/lf7-archive-restart/README.md)。

接下来继续历史专用永久删除精确清单/逐页结果及只读页面（原graph绑定、有界分页、不得借用当前投影或执行/结算接口），然后其它命令/来源强停、历史图片失败、暗色/横屏/手势、目标设备/NAS和原签名发布。生产backup_v2仍关闭；原型树1cbf605独立未改，未改SDK/正式8760/NAS或发布APK。LF7/#32、总任务/#24保持开放。

用户已确认以当前完整原型为实施方向。本次先确定框架、拆分任务和验收依据，后续分阶段实现。总任务和子任务链接见 [ISSUES.md](ISSUES.md)。

## 1. 交付目标与依据

交付现有 Android App 的一次兼容升级：打开进入媒体库，视频与图包分别筛选；选定内容或范围后进入视频预览或图包阅读；返回保留来源。视频与图包的标签独立，图包管理以整包为单位。设置保留现有 0.1.4+5 能力，并扩展图包管理。

依据及优先级：本次用户要求 → 当前 `design/reference/library-first/` 完整原型与 `SETTINGS-AUDIT.md` → 本方案与验收表 → 旧 V1 文档。旧规格中“默认打开浏览播放”“图包不进入第一版”仅描述历史版本，不再限制本次升级。旧文档保留，不无声改写历史。

- 业务代码基线：Git `137ad0e7b02643d463c7e0f17365d23c06806036`；Mac 工具链改动作为开发前置单独提交；LF0 的原型、规划和骨架分别有提交锚点，详见 LF0 记录。
- 原型入口：`design/reference/library-first/app.html`，总览 `index.html`，设置补齐记录 `SETTINGS-AUDIT.md`。
- [baseline.json](baseline.json) 保存当前原型源码、运行依赖及参考截图的 SHA-256。原素材版哈希仅作历史对照；当前隔离版本由 `design/reference/library-first/baseline-sha256.json` 锁定源码和合成素材。私人图包、密钥和原素材截图不提交。
- [ACCEPTANCE.md](ACCEPTANCE.md) 是逐项验收清单，不能用“接口成功”替代“原生页面与完整路径一致”。

“与原型一样”指信息结构、尺寸层级、入口位置、操作结果与返回行为一致。Android 系统状态栏、系统文件选择器和字体栅格差异可保留；不得借平台差异省略页面、设置项、错误状态或范围语义。模拟数据中的标题、作者与页数不是正式数据协议。

## 2. 现有代码与差距

| 位置 | 当前能力 / 发现 | 改造方式 |
| --- | --- | --- |
| `apps/mobile/lib/ui/home.dart`，2624 行 | 同一 State 承担浏览、库、标签、设置、回收、备份；连接后进 browse；筛选直接改播放范围 | 拆成导航外壳、入口查询状态、功能页和管理页；视频预览作为二级 route |
| `library/models.dart` / `repository.dart` | 仅 LibraryVideo、VideoQuery、MediaRoot；同步 snapshot 只含局部网络缓存 | 保留视频实体，增加图包/页/阅读状态；所有库、计数、全选都走分页权威接口 |
| `library/server_repository.dart`，1722 行 | setScope / openVideo 修改全局轮次；列表搜索另传 search | 查询与会话命令分离；把名称搜索、排序、来源带入创建范围，不能丢失搜索或只预览已加载页 |
| `ui/browsing_session.dart` | 跟手选中与迟到回执隔离、有界元数据窗口、异步删除 | 复用机制；补来源恢复和固定范围契约，不把图包页塞入视频会话 |
| `ui/player.dart` / `playback_session.dart` / `device_controls.dart` | 原生播放、最多 3 个解码器、倍速/暂停/横屏/亮度音量 | 保留，入口改变时验证生命周期，不重写播放器引擎 |
| `ui/preferences.dart` / `paper.dart` | 本机主题、相邻准备、P2 颜色字体 | 复用，增加集中尺寸 token；本机偏好不进入 NAS 管理备份 |
| 服务端 `models.py` / `catalog.py` | roots 无类型/启停，所有扫描与查询针对 videos；视频标签名称全局唯一 | 旧记录默认 video/enabled；图包、图包标签和关联采用独立表 |
| `app.py` PlaybackScope / `playback.py` | scope 无 search；eligible 每次重新套标签条件；删除标签会重建轮次 | 新会话协议保存完整候选；开始后不因改标签重排，只有不可用/回收/停用条目不再可选 |
| `scanner.py` / `identity.py` / `streaming.py` | 视频稳定性、身份、授权文件读取已有机制 | 保留；新增图包扫描与图片读取，复用路径校验和受控后台调度 |
| `file_operations.py` / `file_command_store.dart` | 逻辑回收、幂等命令、待确认只读核对、旧物理回收兼容 | 沿用协议语义，新增图包执行逻辑和整包清单，保留原视频安全机制 |
| `backup_format.py` / `backups.py` / `server_backups.dart` | 正式备份 v1 / schema 0004，完整性/映射/前快照/断线恢复 | 引入正式 v2 导入导出；支持 v1 转换，保留现有恢复保障 |
| 最近与图包阅读 | 没有正式实现 | 新增最近记录、按包页码/偏好、横翻/纵向/总览/沉浸与整包整理 |

源码优先于过时说明：服务 README 中仍有“物理回收”历史叙述，现行逻辑以 `file_operations.py`、`docs/logical-trash-and-browsing.md`、0.1.4 补充为准。当前行为与本次新决定冲突时，在对应 issue 和测试中明确迁移，不靠旧测试文案继续旧导航。

## 3. 确定的模块框架

继续 Flutter + ChangeNotifier/不可变状态、FastAPI + SQLite/Alembic、Docker 单服务。没有为此次改造引入新的状态管理框架或后台微服务的必要。

```text
AppShell（媒体库 / 标签 / 最近 / 设置；默认媒体库）
 ├─ LibraryPage / TagsPage / RecentPage → LibraryQueryController
 ├─ VideoPreviewRoute → PreviewSession → 现有 BrowsingSession + PlaybackSession
 ├─ PackReaderRoute → PackReadingSession + ImageWindow
 └─ Settings / Roots / Trash / Backups / Tasks → MaintenanceController
                         ↓ 同一行为接口
              Server adapters / Demo adapters
                         ↓ ServerApi
 Catalog / Playback / Packs / Reading / Tags / FileOperations / Backups
                         ↓
             SQLite 管理数据 + 授权 NAS 文件读取
```

建议目录（在迁移中逐页拆出，不一次性移动全部旧代码）：

```text
apps/mobile/lib/
  app/app_shell.dart, navigation_state.dart
  library/                    # 现有 transport、凭据、命令回执、视频兼容入口
  features/library/           # MediaKind、各类型查询、分页、列表位置、标签页
  features/preview/           # 来源、候选范围、视频预览 route
  features/packs/             # 图包模型/查询、阅读 session、图片窗口与页面
  features/recent/            # 最近列表
  features/settings/          # 连接、目录、回收、备份、任务
  ui/                         # Paper、共享控件、现有播放器及设备控制
services/server/video_viewer/
  packs.py, pack_scanner.py, images.py, reading.py, pack_operations.py
  # 现有 catalog/playback/tags/backup 等按职责扩展，不复制整套服务器
```

接口按行为划分为四个模块：Catalog（查询）、Viewing（进入/推进会话）、PackReader（按页读取/存进度）、Maintenance（管理命令/任务核对）。每个模块隐藏分页取消、版本冲突和任务轮询细节；页面不调用 SQL、HTTP 或 NAS 路径。读取可取消且迟到结果不发布；命令返回已受理任务或明确失败，未知结果保持可查询；分页计数是服务端权威值，禁止同步查询全库作为 UI 前置条件。Server 与 Demo 是实际存在的两个 adapter；不为假想扩展引入额外接口层。现有 LibraryRepository 暂作兼容入口，等各页迁完后删去重复方法，不长期双写两套状态。

### 状态归属与接口契约

| 状态 | 权威归属 | 契约 |
| --- | --- | --- |
| 视频/图包元数据、两类标签、根目录、回收、缺失 | 服务端 | 稳定 ID；类型匹配；计数来自接口，不从已加载卡片估算 |
| 页面类型、两个搜索/筛选草稿、滚动位置、批选 | App 的 BrowseContext | video / pack 独立；切 tab 或退出阅读不丢来源；不写正在播放的轮次 |
| 视频预览 / 图包阅读范围 | 服务端会话 | begin(scope, source, order, anchor, requestId) 固化完整范围；分页取 entries；revision 防旧回执覆盖 |
| 当前视频播放意图与解码器 | App 播放模块 | 复用暂停/倍速/静音/资源上限，离开预览暂停释放；预加载不产生历史记录 |
| 每包进度与偏好、最近访问、默认顺序/阅读默认值 | 服务端管理数据 | 单用户本次就持久化并进入管理备份；客户端可缓存并节流同步 |
| 主题、相邻视频准备、连接凭据、窗口亮度 | 本机 | 不随 NAS 备份覆盖；口令不保存，token 仍在加密存储 |
| 未确认写命令 | 服务端任务 + 本机受保护回执 | 服务地址+实例 ID+request ID；重开只读查询，不自动重放删除/恢复 |

关键类型：`MediaKind(video, pack)`、`BrowseContext(kind, source, query, sort, scrollAnchor)`、`VideoQuery`、`PackQuery`、`PreviewScope`、`PackReadingProgress(packId, pageId, offsetRatio, revision)`、`ReadingPreferences(mode, direction, gap, fit)`。不把图片页当成可独立打标签/回收的媒体。

## 4. 数据与兼容策略

### 4.1 数据库

采用增量迁移，保留旧视频 ID、标签 ID、关联、轮次和文件操作回执。

- `roots` 增加 kind、enabled；历史根默认为 video / true。available 表示可访问，enabled 表示用户开关，两者不能混用。停用保留标签、进度及记录，排除普通列表/新会话/自动扫描；停用不能触发缺失清理。已有内容的根禁止直接改类型，需新建正确类型的接入范围。
- 保留 `tags` / `video_tags` 为视频标签；新增 `pack_tag_definitions` / `pack_tag_links`。同名跨类型合法，写入必须核对类型；这是比重写旧标签表风险更低的本轮选择。
- 新增 `packs`、`pack_pages`：稳定 ID、root、路径、可用/缺失/回收状态、封面页、页数、自然排序键和内容版本。页保存尺寸/格式/文件签名及其包 ID；缩略图是可重建缓存。
- 新增 `pack_progress`、`pack_preferences`、`recent_entries`（kind+entityId，最后实际打开时间）、`pack_sessions` / `pack_session_entries`。分页清单由服务端维护，不把全库 IDs/所有原图塞进 App。
- 图包回收索引、文件执行步骤独立存放；共用 Task 和受控执行队列。旧视频 FileStep/TrashItem 不改成无约束 polymorphic ID。
- 默认播放顺序、阅读默认值加入管理 settings 白名单；旧库从现有播放选择初始化默认顺序，旧数据没有的新字段使用明确默认值。

### 4.2 图包发现与图片服务

首版以配置根目录的直属文件夹作为包；包内子目录递归归属同一包。平铺图片不自动合为未知包，需提示调整接入根。页按相对路径各段做自然排序，数字 2 在 10 前，使用稳定 ID 作最终同序兜底；不依赖 mtime。文件夹名为默认标题，作者/编号解析可选且失败回退原名，不作为身份依据。

先支持 JPEG/PNG/WebP 常见静态图片，损坏/不支持文件返回可定位原因；压缩包直接阅读、动态图片播放、单张标签/删除、AI 标签、离线下载均不在此次范围。格式扩展不阻塞目录图包主路径。

扫描沿用完整成功范围才判缺失、离线不清理、变动文件延迟、后台并发受控原则。同目录新增/删页保持包 ID，尽量保留 pageId；同文件系统目录改名有唯一身份依据时保留；跨盘移动要有唯一完整清单/内容证据，歧义则保留旧缺失记录，不按名字或封面猜测继承标签。刷新清单后按 pageId 找阅读位置，页已删除时选择最近有效页并告知。

封面、分页缩略图和原图走鉴权接口；只接受受控 ID，不接收任意磁盘路径。缩略图失败不封锁整包；单页失败可重试或继续。纵向采用惰性列表和已知宽高占位，横向只保留当前/相邻图片；切包、离页、换连接时取消过期读取。缓存按字节设上限，具体值在 LF5 以 4K/8K 样本测定，不把无限 precache 当优化。

### 4.3 会话与接口演进

保留 `/api/v1` 现有视频协议，增加 `/info.capabilities`，新 App 遇旧服务给出兼容提示，视频路径可继续使用，图包功能明确不可用。新增路径为实施约定，LF1 落定 OpenAPI 后由接口测试锁定：

| 接口能力 | 方向 |
| --- | --- |
| roots / directories / library-state | 返回 kind/enabled，进度按类型区分；新图包首扫不阻塞已可用视频 |
| videos / rounds | 查询与创建范围都支持 search、sort、source；新会话带固定成员协议标记，旧调用保留旧默认行为 |
| packs、packs/{id}/pages | 分页包摘要、分页页清单、明确总数与内容版本 |
| packs/{id}/cover、pages/{id}/thumbnail、pages/{id}/image | 同源鉴权、版本缓存、流取消、受限并发 |
| pack-tags、pack-tag-links | 独立 CRUD/搜索/计数/交集、追加/替换语义 |
| pack-sessions / entries / position | 创建固定包范围、分页队列、revision 更新；全范围在服务端求值 |
| packs/{id}/progress、preferences；recent?kind=… | 进度/偏好和最近记录；实际进入才记历史，重复更新幂等 |
| pack-trash / operations；tasks | 按包标记、恢复、永久删除；任务按已有 request ID 查询机制扩展 |
| backups / imports / restores | 保留异步完整性校验、映射、确认与前快照，新增正式格式 v2 |

搜索按原型匹配视频名称与目录；图包匹配标题、目录及可用的作者字段，缺作者仍可正常按标题查找。新会话创建时，搜索、目录、标签交集、属性、排序和来源（媒体库/标签/最近）必须全部生效。最近来源按最近列表取候选，不偷用媒体库筛选。会话内改标签不重筛候选；删标签不会自动建立新会话。目录停用/离线、文件失效、回收后可跳过不可用项，但不添加新候选。模式切换只重排本范围；主动重新从入口进入才重新查询。旧轮次迁为已存在的条目快照，不默认扩大为全库。

App 保存来源 BrowseContext，离开二级页时恢复它并按新标签重新查结果；保存滚动 anchor，条目消失时选最近仍在的相邻项。系统返回、界面返回和横屏退出有同一约定：先退出全屏/面板，再返回来源；无来源的冷启动进媒体库。

### 4.4 删除、未知结果与备份

普通菜单移入回收站先确认；快速整理明确开启后直接整包回收，8 秒撤销绑定该操作。按当前原型，图包成功后才进入本范围下一包，已知失败留在原包，最后一包回到来源。视频保留现有跟手切换与异步提交机制：已知失败恢复条目；未知结果不显示成功。两者都保留待查询任务，撤销恢复原 ID、包内页码、队列位置与模式。

图包永久删除按确认时的已索引图片清单执行，执行前核对版本/路径/签名；目录中出现新文件、替换或身份不确定时停止并要求重新核对，不能无限递归删除。非图片附件保留；仅清理已空目录。部分成功逐项可见，重试只处理未完成项。具体确认文案在 LF6 与清单一起验收，不把永久删除伪装成逻辑回收。所有删除故障测试使用可丢弃样本。

管理备份 v2 包含两类标签、图包页身份、进度/偏好、最近、目录启停、会话、回收与回执；不含媒体字节、可再生缩略图、token、口令、主题、预加载开关。旧 v1 经校验后转换成 video 根/标签和空图包状态；这是完整替换，若当前已有图包记录必须明确展示将被替换，不静默合并。新备份不给旧服务强行导入。

升级先留旧管理快照，跑隔离实例迁移演练，再发布兼容服务端、最后 App。保留包名、原签名并提高 versionCode。回退新服务必须恢复升级前管理快照，不能拿旧二进制直接打开已迁移数据库；会明确提示回退会舍弃升级后管理修改。图包会话/备份不能复用 HTML localStorage JSON 作为正式协议。

## 5. 实施顺序与阶段完成标准

| 任务 | 交付 | 依赖 | 完成标志 |
| --- | --- | --- | --- |
| LF0 | 原型基线、接口清单、模块拆分及可运行骨架 | 无 | 保存参考证据，旧行为回归；无破坏式大重写 |
| LF1 | 增量 schema、类型根、独立图包标签、capabilities | LF0 | 旧库身份/标签/回执保留，类型隔离测试通过 |
| LF2 | 图包扫描、分页、封面/图片授权读取 | LF1 | 合成多层目录成包，变更/离线/坏图/大包通过 |
| LF3 | 视频入口范围、固定轮次、最近视频与兼容 | LF1 | 搜索/分页完整范围，改标签不跳位，播放器旧能力不退化 |
| LF4 | 四入口外壳、两类媒体库/标签/最近与 P2 比例 | LF2、LF3（骨架可先用 Demo） | 原生页面/返回路径与原型对应，真实分页不靠演示数组 |
| LF5 | 图包阅读、范围会话、进度与阅读偏好 | LF2、LF4 | 横翻/纵向/总览/沉浸/续读完整，内存有界 |
| LF6 | 图包快速整理、撤销、批量回收与永久删除 | LF3、LF5 | 操作 ID 与结果核对、原位置恢复、源文件保护通过 |
| LF7 | 设置全量接线、统一任务、v2 备份与迁移 | LF1、LF2、LF6 | 设置对照无遗漏；v1/v2 恢复、断线及前快照通过 |
| LF8 | 原型逐页验收、原生联调、升级包与目标设备 | LF0–LF7 | 验收表全部证据齐全，无“界面完成但 API 未接” |

按 LF 编号推进，不先堆阅读 UI 再猜数据契约。LF4 可提前做 Demo 页面，但不能在 LF2/LF3 未通过时标记完成。每个 PR 在正文写验收 ID、实际证据和剩余限制。Epic 只有 LF8 验收完成才能关闭。

## 6. 验证与风险控制

先建兼容夹具：含现有视频/标签/随机轮次/逻辑与历史物理回收/未确认操作的 0004 管理库，以及无私人内容的四个测试图包（自然排序、深层目录、坏图、空包、横竖混排、超长包、超大图片）。单元/接口测试覆盖不变量，原生 Android 集成测试覆盖完整路径，截图单独核对布局；不以 Demo 或 HTML 测试代替真实服务。

统一参考视口为 390×844，补 360×740 和 844×390；按逻辑像素比较 App 内容区，系统安全区单独计算。使用同一非私人素材、页码、标签、筛选和时间状态。关键尺寸：52 顶栏、49 导航内容区加系统安全留白、16 横向内容边距、12 列距、18 行距、211 封面（390 宽；360 宽 185）、16 卡片标题、15 设置行标题。禁止在 Android 底部额外画 HTML 的假 home indicator。需要增大点击区时可透明扩展，不扩大视觉卡片。

本机继续 `scripts/dev.sh`、VS Code F5、8760 开发 / 8761 可复位联调环境。Flutter analyze/unit、服务端 API/迁移/故障恢复、Android 集成、目标设备与 NAS 资源测量分层报告。当前 Mac 记录为 68 项客户端、98 项服务端历史通过，另有 12 个服务端 Ruff 格式文件基线失败；这些是历史依据，本次规划未重跑，不能作为新功能已通过。LF0 重新记录基线，后续不掩盖基线或新增失败。

主要风险及应对：

- 数据模型绑定视频太深：图包用独立表和接口，保留旧视频路径，逐模块迁移。
- 搜索/标签变动让范围泄漏：服务端固定成员 + 全量分页范围 + 明确最近来源测试。
- 新图包首扫拖慢视频：按类型准备状态、后台小并发、前台读取优先；量测再调缓存。
- 大包图片耗尽内存：惰性列表、按显示尺寸解码、有界窗口/缓存、取消旧请求；用真实机测峰值。
- 替换源文件和响应丢失：清单/版本核对、已持久化命令、只读查询、不自动重发。
- 完成后偏离原型：锁基线 + 每阶段原生截图 + [逐项验收](ACCEPTANCE.md)，行为变化先改方案/issue 并说明，不能只提交“类似的 UI”。

## 7. 范围与待实施决定

LF0–LF6 对应实现与验证见各阶段文档。LF7 任务中心见 [LF7记录](LF7.md) 和 [任务中心设计](LF7-TASKS-DESIGN.md)。各阶段保留未完成项，整份批次、完整设置、v2备份及 LF8 继续推进。尚未迁移或写入真实 NAS、发布新版 App。

技术选择（独立图包表、管理偏好服务端保存、静态格式范围、按清单永删）是本方案的实施建议，用户已确认的是产品方向与现有原型。若实施发现必须改变用户可见行为，需把差异具体列在对应 issue；无须为了普通命名/目录组织再次让用户选框架。


## 2026-10-26：媒体库权威分类总数（PR #60）

[Draft PR #60](https://github.com/ShiJiJS/video_viewer/pull/60)基于#59，固定实现910cfb2、证据提交b927026。媒体库“视频 N / 图包 N”复用library-state中的同一SQLite只读快照，按实际完整可浏览目录计数；搜索零结果和分页不改写全库数，标签/最近隐藏标记。失败显示“—”并可点分类重试，旧服务隐藏；连接代次和请求顺序拒绝旧响应，图包操作后只读重取。

客户端485项、服务端相关75项、analyze/Ruff通过。普通三轮、大字、短横屏五轮同源码共45个库存检查点，真实逻辑回收/恢复2/4→2/3→2/4，完整进度不变、最近/阅读会话0；同源码另10个续读回归检查点通过。215份manifest输入核对源码、55个前台窗口/原始图、SQL投影、26个源SHA与设备恢复；并发提交测试证明两个总数来自同一快照。75项是相关服务回归，不是服务端全集或目标机性能。

受影响147dp顶栏与4785a69已实际渲染的冻结参考同状态并排；图包正文历史、标题/作者与排序仍有差异，不宣称整页完全一致。横屏键盘过渡暴露非当前标签页61dp可用高度下的79dp溢出，改为按实际空间约束并滚动操作区；两类标签缩高/恢复与原生横屏通过。正式取证不忽略Flutter异常，早期失败日志单列；本段未新增独立视觉评审或手势录屏。

[设计与异步约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/LF8-CATALOG-COUNTS.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/evidence/lf8-catalog-counts/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-catalog-counts/docs/plans/library-first/RESULTS.md)。本段补LIB-01/02、UI-01/04/05的明确组合，不关闭整项。管理网关用于验证计数更新，不替代删除确认UI验收；MemoryCredentialStore不新增强杀/安全存储证明。

下一段继续保守标题/作者与服务端一致排序，随后完整预览/阅读/管理、键盘手势、500页4K/8K、目标手机/NAS和原签名覆盖升级。冻结原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。


## 2026-10-26：图包标题、作者与完整范围排序（PR #61）

[Draft PR #61](https://github.com/ShiJiJS/video_viewer/pull/61)基于#60，固定源码4e391a2、证据提交614b135。图包卡片分开标题/作者，未知格式回退原名；原name/path/ID保留。续读、阅读器、范围、详情和最近复用显示标题，阅读头显示作者/编号；阅读角标补实际页码并移到左上，多选隐藏。

能力pack_presentation将App图包名称排序统一映射为title；SQLite内同一ICU中文标题键贯穿分页、锚点、完整全选和创建阅读范围。保留name/默认旧调用、旧固定会话及newest/recent；不在App只重排一页。Docker固定已有ICU运行库，裸环境缺依赖不广告能力；无schema迁移或重扫要求。双倍字号切最近加入曾向右溢出51dp，现大字操作行可横向滚动，保留字号与两端完整动作。

客户端494项、服务端8文件相关111项、analyze/Ruff通过。普通三轮、大字、短横屏共50个展示/排序检查点，另库存9点与续读10点回归；262份manifest输入核对69个前台窗口/原始图、同版源码、SQL范围ID/ordinal、26个源SHA及设备恢复。服务含28包跨页与创建后改名/新增不重排。续读回归的显式refresh沿用一次扫描，标题/库存流程无扫描；不是服务端全集或目标机性能证明。

实际浏览器和原生四包顺序一致；参考以未保存snapshot配置冷库history为空、保留第三张页码，加载的HTML/CSS/运行脚本与冻结Git字节核对。完整并排不挪列或拉伸，已明确保留差异：桌面滚动条使参考列167.5dp/原生173dp，共享标签仍11dp，参考12dp/1.6行高和4dp上距；标签顺序、次要文字颜色、菜单图标与横屏列数继续复核。视频中文排序及完整管理/阅读/预览、手势、500页4K/8K、目标手机/NAS和原签名升级也仍开放。

[设计与兼容约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/LF8-PACK-PRESENTATION.md) / [原始证据及只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/evidence/lf8-pack-presentation/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-pack-presentation/docs/plans/library-first/RESULTS.md)。本段补LIB-02/03及UI-01/04/05局部组合，不关闭整项；未新增独立视觉评审或手势录屏，MemoryCredentialStore不新增强停/安全存储证明。早期验证预期、指标锚点/懒加载与真实大字溢出日志均单列，失败轮次不计正式图。

下一段继续共享卡片标签密度与横屏排布、视频中文排序，再收口完整页面和动作。原型1cbf605独立可移除，backup_v2保持关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33及总任务/#24保持开放。


## 2026-10-26：卡片标签密度与短横屏网格（PR #62）

[Draft PR #62](https://github.com/ShiJiJS/video_viewer/pull/62)基于#61，固定源码e53e173、证据提交8812d24。视频/图包标签统一12dp/1.6和元信息后4dp间距，作者/方向色对齐参考；卡片按实际字形测量高度。媒体库及标签结果短横屏四列，其余两列，键盘高度不改变列数；重排和返回共用实际几何，保存稳定成员与行内偏移，不重排或重查服务结果。最近视频完整形态继续核对。

客户端501项、analyze/Ruff通过。普通三轮、大字和短横屏30个卡片点，另共享8点、排序10点、续读10点、库存9点，共67张同源码原生前台图；277份manifest输入只读核对通过。120项组件样本验证两类双向重排及真实查询次数不增加；原生固定视口不冒充深列表旋转。26个公开源SHA、进度/会话SQL和设备恢复均保留。服务生产树未改，本段未重跑服务端测试；续读显式refresh沿用一次扫描，其余场景无扫描。

独立存量视觉评审一轮及修正复核一轮：作者/方向偏浅的唯一问题已修正，相邻标题/标签/网格未损坏。首轮大字续读脚本等屏外摘要挂载超时，现先核对真实返回锚点，再实际滚回顶部；失败与首轮图片单列，不忽略异常。并排复用已核对冻结字节的冷库浏览器参考，仅移除真实安全区并按DPR等比降采样，不挪列或拉伸。

[设计与返回约定](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/LF8-CARD-LAYOUT.md) / [原始证据与只读复核](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/evidence/lf8-card-layout/README.md) / [逐项台账](https://github.com/ShiJiJS/video_viewer/blob/codex/lf8-card-layout/docs/plans/library-first/RESULTS.md)。本段补LIB-02及UI-01/04/05局部组合，不关闭整项。标签顺序/菜单图标、桌面滚动条列宽、视频中文排序、完整最近/预览/阅读/管理及手势、500页4K/8K、目标手机/NAS和原签名升级继续。冻结原型1cbf605独立可移除，backup_v2仍关闭；未改正式8760/NAS/SDK或发布APK。LF8/#33与总任务/#24保持开放。
