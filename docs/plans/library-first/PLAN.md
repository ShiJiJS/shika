# 媒体库与图包改造实施方案

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
