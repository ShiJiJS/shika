# LF 模块契约与后续接线

LF0 保留旧版可运行路径，LF3/LF4 才切换固定会话与新导航。这份清单把已实现接口和后续接口分开，不用空实现假装新功能完成。

| 模块 | LF0 已接入的接口 | 不变量 / 下一步 |
| --- | --- | --- |
| AppShell | header/content、destinations、selected/onNavigate、showNavigation | SafeArea/Scaffold/底栏统一，保留既有 nav-* Key、尺寸和状态。LF4 更换四入口并拆出功能页，LF0 不提前丢掉旧入口 |
| VideoBrowseContext | query、search、source、sort、scrollOffset/anchor/index/inset；queryKey | 不持有播放器或发写命令；tag 集合顺序不改变查询身份，滚动不触发重查；LF1 加入类型专有的 PackQuery，LF3 保存来源恢复 |
| LibraryQueryController | load(context, more)、state、cancel/dispose | 查询只调用 LibraryRepository.loadVideos，永不 setScope/openVideo；24 条分页，迟到结果无效、翻页失败保留卡片/原 offset、停止加载、显式错误 |
| Viewing | 现有 BrowsingSession / PlaybackSession | LF3 接收完整入口范围、固定候选/revision 与返回上下文；LF0 不改变旧轮次语义 |
| PackReader | 尚未实现 | LF2 确定页清单/版本/鉴权，LF5 接 reading session；不拿视频实体占位 |
| Maintenance | 现有 LibraryRepository、ServerBackups、命令回执 | LF6/LF7 再拆页面与统一任务；未知请求只读核对，不重放删除或恢复 |

当前真实与演示实现都经过同一个 LibraryRepository 读取接口。同步 snapshot 不是完整媒体库；query controller 仅公布已读页及权威 total，不在前端伪造全库计数。来源、筛选、排序和会话完整范围的服务端协议仍以 PLAN 的 LF1/LF3 项实施。

生命周期：页面退出调用 cancel 使 in-flight 回应失效并保留已读卡片，销毁先移除监听再 dispose；controller 不拥有 repository 生命周期。连接与恢复触发旧读取失效的既有 generation/RequestScope 保护仍在 server adapter 内；LF0 增加页面读取代次，不移除网络层保护。


## LF1 已落定的数据契约

`MediaKind` 位于共享 models；`MediaRoot.kind/enabled` 缺省为 video/true。HTTP 旧 PUT 省略字段时保留服务端值，不以默认值覆盖。客户端 `ServiceCapabilities` 缺失时为旧视频协议；能力随成功连接发布，随凭据失效清空。未知能力忽略。

`PackQuery` 与视频查询独立，包含 folder / tag_ids（排序后的 ID 集合）/ search / read_state（all、unread、reading、completed）/ sort（name、newest）；`PackBrowseContext` 另存 source / scrollOffset / scrollAnchor，滚动不改变查询身份。LF2 把 folder 路径解析为目录 ID 并接真实分页，LF5 消费固定范围，查询本身不创建阅读会话。

`GET /api/v1/pack-tags` 返回 items/total/offset/limit，条目 id/name/kind=pack/pack_count；写入与视频沿用 request_id，但命名空间为 pack_tag.*。`PATCH /api/v1/pack-tag-links` 接受 pack_ids/tag_ids/mode/request_id，跨类型、缺失 ID 整次拒绝；空 tag_ids 的 replace 清空关联。标签计数只计可用、启用且在正确类型范围内的包；回收/缺失保留关联而不计数。

`GET /api/v1/directories` 及 resolve/detail 可指定 kind，旧请求默认 video。停用/另一类型的嵌套根不能被外层根绕过。LF1 仅公布 typed_roots、pack_tags；image_packs、会话、读取与维护接口将在对应真实能力实现时再扩展 OpenAPI，并锁定请求/响应测试，未实现接口不提供空成功响应。

图包稳定 ID 与历史路径分离：packs.path / pack_pages.path 可在旧缺失包与新包之间重名，packs.location_key 仅为当前占位且唯一。扫描器只有在唯一目录身份/内容证据成立时复用 ID；同名替换不得迁移标签和阅读进度。该约束已纳入尚未发布的 0005 设计与迁移/ORM 对照测试。

## LF2 已落定的查询与图片契约

`/info` 为 schema `0006`，能力新增 `image_packs`。`0006` 在包记录上保存 `directory_signature`；设备/inode 不是单独足够的身份依据，创建时间不可用时采取更保守的证据判断。

| 接口 | 参数与返回 |
| --- | --- |
| `GET /api/v1/packs` | `offset=0, limit=24`（1–200）、directory_id、search（标题/根下相对目录）、重复 tag_ids（AND）、read_state=all/unread/reading/completed、sort=name/newest、status=available/missing/trash/unreadable；返回 items/total/offset/limit |
| `GET /api/v1/packs/{id}` | 包摘要：id/root_id/path/name/status/error、page_count/readable_count、content_version/tag_ids/cover_url、progress；不写进度或历史 |
| `GET /api/v1/packs/{id}/pages` | `offset=0, limit=100`（1–200）、可选 `v`；返回 items/total/offset/limit/content_version，页含 ID、相对路径、ordinal、width/height、format/size/sha256、error、同源 image_url/thumbnail_url |
| `GET/HEAD /api/v1/packs/{id}/cover` | 首个有效页缩略图；可选 v，鉴权及 Range 同图片读取 |
| `GET/HEAD /api/v1/pages/{id}/image`、`thumbnail` | 只接受 ID、可选 v，支持 Range；Content-Type 按原图格式/缩略 JPEG，X-Content-Version 标明版本 |
| `GET /api/v1/directories` | 保留 kind/parent_id，新增 offset/limit（1–200）；响应 items/total/offset/limit。省略 limit 保留旧版全量直属目录行为 |

可阅读包要求启用、已映射、可访问的 pack 根实际拥有包和至少一个有效页；最内层根拥有图包路径，停用/未映射/另一类型子根是边界。同类型视频重叠根仍保留旧版最外层归属。隐藏子树的页不参与计数、封面、标签计数或读取；旧记录可以保留供重新启用。空包/全坏包与包级访问失败在 unreadable 列表反馈，坏页本身保留错误占位。

包/页列表的 total、条目及版本在同一短读取快照内生成；分页间内容变化须通过 v 核对。失配返回 `409 pack_changed`，无效源或越界/符号链接/替换拒绝，鉴权与未授权行为沿用旧接口。`ordinal` 可因隐藏子树留下间隙，不等于当前可见页码；按响应顺序和 offset 呈现页码。sha256 可用作 LF5 图片缓存身份的一部分，LF7 恢复/连接切换还必须作缓存与请求代次隔离。

`library-state.media.video/pack` 分别返回 ready/scanning/counts；pack 还返回 indexed。ready 表示完整首扫已结束，不能作为读取已发布图包的前置门禁。冷扫无旧身份待匹配时按已完成包发布；有旧身份时先完成对应范围核对。扫描阶段、处理数量、受限错误列表与解码峰值记在现有 task 的 result.packs，不复制另一套扫描任务。失败/延迟范围不执行缺失清理。

LF2 不提供阅读会话、进度更新、最近写入或图包整理接口；已有进度只读返回用于后续接线。新 App 的图包 adapter/UI、冷扫进度呈现、坏页重试/跳过由 LF4/LF5/LF7 实现，不以当前服务端成功替代原生路径验收。

## LF3 服务协议（客户端接线中）

初始 schema `0007` 新增 fixed_video_sessions；当前 `0008` 另有 versioned_video_queue、video_entry_anchors。轮次新增 membership/source/sort，成员另存 source_ordinal；0008 新增 sequence_revision。返回定位不新增数据库列。原有调用默认 legacy/library/path，升级旧轮次也保留此状态。

`POST /rounds` 新客户端发送 membership=fixed，source=library/tags/recent、sort=path/name/newest/recent、完整 scope（新增 search）、order、anchor_video_id 和 request_id。recent 排序只用于 recent 来源。legacy 不接受新增搜索/来源/排序语义，旧请求不会静默进入新协议。返回额外 membership/source/sort，scope 保留原查询依据，但固定会话不再次使用该依据筛成员。

`PATCH /rounds/{id}/order` 接受 order、expected_revision、request_id、restart（默认 false）。重排固定成员、保持当前视频，顺序使用创建时的基准；restart 从重排后开头开始。它不创建新轮次或重查媒体库。`POST /rounds/{id}/opened` 接受 video_id、expected_revision、request_id，只允许当前有效固定会话的实际选中项写入最近。

`GET /videos` 增加 source/sort，服务端按相同条件求完整预览候选；默认 path 保持旧分页顺序。搜索匹配名称及根下相对目录，不匹配临时主机挂载前缀。`GET /recent?kind=video` 返回相同分页结构及条目的 opened_at；图包最近暂未实现，kind=pack 明确拒绝，不返回空成功。

支持 fixed_video_sessions 的新连接已调用 `GET /playback?create=false`；无会话返回 404 round_not_started，界面停留入口。旧调用继续默认 create=true。新固定预览同时要求 versioned_video_queue、video_entry_anchors，旧服务缺少能力时明确提示升级。客户端的 begin/order/restart/opened 已接线，原生四入口和全部返回路径仍未验收完成。

`GET /videos` 可携带最多 16 个按优先级排列的 anchor_ids，offset 此时为原条目序号的回退值。服务在同一 SQLite 读取快照内，使用完整入口查询及相同排序查找第一个仍匹配的 ID；全部失效则把回退序号限制在有效范围内。返回该条目所在的一页、实际 offset 和全局 anchor_index；不会把所有前置页发送到客户端，也不创建播放会话或最近记录。

来源页保存首个可见视频及附近 ID、全局序号、行内滚动余量。恢复后按返回页内行定位；前方分页插入时补偿滚动距离，仍可向前后浏览。查询失败保留原窗口和来源，原处重试同一定位；新搜索或离页使旧读取及其滚动回调失效。后台管理数据更新也按可见 ID 刷新，避免恢复后又被第一页刷新覆盖。

`GET /rounds/{id}/entries?v=sequence_revision` 返回 sequence_revision，版本不符返回 409 round_order_changed；在同一短读取快照内检查版本、候选与总数。普通位置变化只改 revision，重排/重来还提高 sequence_revision，原候选不变。客户端窗口/队列以会话 ID + sequence_revision 隔离，遇失配先只读刷新当前会话，再拒绝迟到的旧页。长队列 UI 随机访问分页，最多保留四页元数据；重排后定位当前项。

`VideoEntryScope` 是两种 adapter 共用的完整查询输入；来源的滚动位置单独在 BrowseContext 中。`BrowsingSession` 可见时才确认 opened；普通列表和队列预取不确认。观看位置、显式队列选择、模式变更和完成命令共用该浏览会话的串行队列，关闭/换连接/换会话后未执行的旧命令取消。Demo 的原始顺序、当前顺序、最近记录和固定范围随演示管理状态保存。

`savedPreviewEntry` 只读暴露已保存固定会话的入口。一次新连接可用它初始化媒体库草稿，之后不跟随活动轮次覆盖草稿；重开不自动导航到预览，也不写 opened。连接失效时二级预览释放播放器并返回登录界面。

LF3 暂将默认顺序保存在本机 `UiPreferences.videoOrder`，与活动会话的 order 分离；仅在新 begin 时作为显式 order 发送。首次新入口沿用已有顺序形成初始默认；设置默认值不调用 setScope / POST rounds，当前范围重排也不改默认值。本机偏好写入串行执行，成功后才发布新值；外观、相邻准备和默认顺序不互相覆盖，失败保留旧值。此处只完成 SET-02 的会话隔离；PLAN 规定的服务端管理默认值及 v2 备份仍由 LF7 完成，届时迁移/冲突规则与连接隔离必须单独验证，不能以当前本机持久化代替。

## LF8 接入目录扫描（#138服务已实现，#139客户端待接）

schema0014新增root_scan_progress/scoped_scans能力，不新增表列。POST /scans旧空正文保持全扫，新正文root_id只选该接入目录；共享单工作线程和持久队列，未完成/排队范围去重。全扫中A已完成、B仍运行时，指定A允许新排队尝试；重复A合并到该队列项。停用/被外层覆盖的视频别名明确拒绝，不扩大范围。HTTP任务result.root_scans含完整每根事实，旧roots过滤disabled/covered，scope表明所选根。library-state每根scan保留最近执行结果，queued_task_ids和scan_queue单列队列；重扫A不替换B。客户端只有同时支持两项能力才发送指定根请求，失败不改发全扫。

视频progress以视频为单位；图包progress以图片为单位，packs_discovered/processed另计图包，旧root.discovered/processed仍为视频/图包。未知总量不充当分母；page_errors含缓存坏页。Task快照与本机索引同一事务发布，管理代次/相关根范围签名失配不复用数字；索引不进入便携备份。缺失与限定候选使用当前路径归属，保留原视频外层/图包内层及类型/停用边界。

首次无旧身份的根可先完成，其它根继续；需要全范围身份核对的根保留数字并显示reconciling。中断持久化，不自动重放队列/文件操作。[细则和验证](LF8-ROOT-SCAN-DATA.md)给出单位、旧协议和边界；本段未部署NAS、未验证当前客户端组合，客户端不能在不支持/请求失败时自动退成全扫。

纵向阅读缩放比例和横移仅为当前会话视图状态，不写偏好/续读。手势以稳定页ID/页内位置映射到重排后的列表，保持120条元数据及既有图片缓存预算；缩放、复位、旋转和窗口定位不报告新阅读进度，真实纵向拖动/惯性才保存。双击只识别已显示图片，错误和末尾按钮不等待双击判定。阅读器存续时允许设备方向，退出恢复入口竖屏约定；不改变视频全屏的方向管理。
