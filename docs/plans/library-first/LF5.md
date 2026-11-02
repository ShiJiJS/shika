# LF5 图包阅读器（实施中）

最新补充为文末 PR #57：纵向可见末张按所点图片跳过，保留原真实进度；此前PR #56的当前末张与横屏路径亦有回归。以下按阶段保留历史记录，完整异常、性能与目标环境范围仍继续。

对应 [#30](https://github.com/ShiJiJS/video_viewer/issues/30) / [草稿PR #39](https://github.com/ShiJiJS/video_viewer/pull/39)，基于 LF4 / [草稿PR #38](https://github.com/ShiJiJS/video_viewer/pull/38)。`cb02a67` 接入服务端阅读模块，`278a774` / `91f1112` 已让Flutter图包卡片进入真实阅读器，支持横翻/纵向/总览/沉浸与逐包续读。最近图包列表现已接入，完整异常/来源组合和大图性能仍待收口，本阶段继续实施。

## 已接入的阅读状态

服务端按完整搜索、目录、独立标签交集、阅读状态、来源与排序固化图包范围，支持顺序/随机以及分页队列；不会只取客户端已加载24项。改标签、新增包不改变固定成员，停用/失效只改变可用项，候选不会扩大为全库。当前位置失效后GET可返回附近候选；实际打开候选时才提交新位置和会话revision，原项恢复不会抢回当前阅读器。

创建/读取会话、页清单和预加载不记最近，也不固定每包偏好。首张实际显示后确认opened才更新去重的图包最近、进度及本包初始默认偏好。之后按pageId+页内比例与完成状态保存；会话位置、进度、清单与偏好各有版本检查，旧会话或旧位置不能保存到新包。响应丢失可先只读查询回执，不自动重发；复用原request_id可显式重试，同键不同内容拒绝。

每包模式/方向/间距/适配独立保存；全局默认只作用于未设置包，首次实际打开时固化到本包。最近图包与视频独立；图包列表、定位、全选和阅读入口能使用同一recent来源及完整过滤。

Schema0009在现有骨架上增加进度清单版本、删页恢复原因和偏好revision，保留旧pageId/比例/完成/进度revision/偏好。扫描删除当前页时选择附近可读页、清零比例、递增进度revision并保留说明，实际打开后确认清除。原页损坏时读取返回附近可读页和明确原因。迁移继续使用原有前快照；正式管理备份v2和全域恢复代次隔离仍待LF7。

详细字段、归属与失败处理见 [设计契约](LF5-DESIGN.md) 和 [客户端数据契约](../../client-data-contract.md)。

## 验证

`cb02a67` 上完整 **162项服务端测试通过**（206.82秒），其中阅读接口 **8项通过**；全服务端Ruff通过。测试运行时源码/迁移/测试均与该提交逐文件一致，采用只读挂载的Linux隔离容器。客户端代码本轮未变，既有171项客户端检查点仍按LF4原提交记录，不冒充本次阅读器验证。

测试走真实鉴权HTTP接口与SQLite，不是Demo。8项阅读接口用例覆盖27项完整固定范围及目录/搜索/标签/阅读状态反例、随机快照重试不重排、完整分页、失效项/新增包/改标签、进度与偏好版本冲突、旧会话和旧位置拒绝、只读回执、默认冻结、实际扫描删页、500页清单定位/损坏页回退、恢复写入门禁及回退位置不会被恢复上线的原项抢回。

日志和源码SHA-256见 [本次服务端证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reading-backend/README.md)。500页测试只有元数据和定位，不能证明4K/8K真实解码、手势或内存性能。该服务端检查点不含原生截图；本次新增阅读器截图与主路径记录另见下文，未把既有LF4截图当作阅读器验收。

## 客户端类型化接口与读取归属

`04f57a8` 增加 `createPackReader`，每个阅读句柄绑定创建时的连接、连接代次与阅读元数据代次，页面通过isCurrent判断归属。范围、页清单、队列、进度和偏好均为独立类型；写入使用不可变命令，包含固定request_id与版本。submit不自动重试；未知结果先只读receipt查询，找不到也不补发。目录先按kind=pack解析，不可用时拒绝建范围。

清单校验完整分页、稳定ID、页所属包、内容版本、尺寸与同源鉴权地址；范围和回执校验身份、版本与数量，错误/外域数据不能变成可读成功。元数据、页和队列各有取消范围，离开句柄、换连接及恢复发布新数据会取消它们。恢复待确认时拒绝新的阅读写入；确认恢复即使连接对象未变，也让原句柄失效，不能继续读写旧管理状态。

该提交完整 **179项客户端测试**与Flutter analyze通过，其中 **8项新HTTP适配用例**。覆盖完整过滤/来源、27项末项队列与500页清单尾页、回执读回无额外POST、畸形/旧版本/外域拒绝、取消/换连接/401及同连接恢复代次。服务端源码仍匹配cb02a67的162项记录，未重新冒充服务端或原生验收。证据见 [客户端阅读接口](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reading-adapter/README.md)。协议夹具完成恢复的回执，只证明这次客户端通知接线；正式v2和全域恢复隔离仍待LF7。

`f43a320` 补充读取及同步publish之后的最后归属检查：监听者在通知中销毁句柄时，不能再返回旧句柄成功结果。新增用例验证仅提交一次且保留服务端回执；当前全量 **180项客户端测试**、Flutter analyze通过（含9项新阅读HTTP适配用例），见 [发布归属证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reader-publication/README.md)。前一179项接线证据保留原实现提交。

## 原生阅读界面与会话

`278a774` 新增独立PackReadingSession，使用既有真实adapter与固定服务端范围。只认当前包/页、当前连接和当前显示首帧；清单40页分页、元数据最多120页，队列40项分页。写入串行flush，未知结果保留原请求，先查回执再显式重试；后台和离页发起保存，旧回执不能覆盖新视图。

图包卡片直接进入专用阅读路由，返回沿用LF4原来源定位。横翻/左右方向、双击缩放、完整/宽度适配、纵向惰性拼接/间距、分页总览/页码跳转、沉浸、整包标签和范围内手动换包均已接线。末页不自动换包；单页失败可重试/跳过，429/503仅有限重试。总览单独读取缩略图，不取消主阅读器清单；没有缩略图不会为总览下载原图。

Paper比例沿用冻结参考；顶栏最小52dp、双行信息按实际字体自然增高，工具21dp/12dp、真实Android安全区；大字号工具按两字一行且图标上对齐。总览标明当前页，来源显示全部图包或具体目录/搜索/标签数/阅读状态。设计见 [界面约束](LF5-UI-DESIGN.md)。原型未修改。

图片provider按视口缩小，单张最多约2M解码像素/最长4096，LRU最多6项/估算48MiB，远项与离页会evict；这是实现预算，尚不是4K/8K原生峰值验收。

`91f1112` 完整 **189项客户端测试**及Flutter analyze通过，包含6项新真实HTTP控制器测试与3项图片首帧/横屏/大字号界面测试，见 [客户端证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reader-ui-client/README.md)。同实现Android真实服务主路径连续三轮通过（390普通字号两次、360双倍字号一次），复跑与截图单独记录于 [阅读原生证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-native-reader/README.md)，不把静态截图当生命周期或性能证明。

## 最近图包与分页返回

`40e0c27` / `95c61cd` 接入最近图包：PackQuery自身携带来源与排序，列表、分页、稳定定位、完整全选及阅读入口共享同一查询；最近不继承媒体库草稿。recent默认按最近阅读排序，也支持同一查询显式名称/加入时间排序，阅读器不能悄悄重排。旧服务缺阅读能力时在最近请求/选择发出前提示升级，不回退全库。

最近页按冻结原型使用纵向历史行（20dp侧距、64×78封面、18dp包名、13dp进度）。进度摘要增加可选page_index，按当前清单中稳定pageId的真实位置计算，不能把文件名或ordinal当页码；缺失页/旧服务不猜位置。摘要GET不修改进度。阅读器默认最近来源显示“最近阅读”，保留真实范围序号。

真实联调发现分页末尾锚点返回时，只有首24项的临时窗口会提前夹住滚动位置。现在先补齐可见行所需的后续页，再恢复原视口锚点及行内偏移；历史重排到尾边界时只按完整列表合法边界夹位。媒体库两列与最近单列共用该定位策略。输入联调用可观察的页面转场结束、定位完成和输入法完成状态，不在返回动画中向旧输入连接写新搜索。

当前完整 **197项客户端测试**、Flutter analyze以及 **163项服务端测试/Ruff**通过，见 [最近来源检查](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-recent-catalog/README.md)。客户端新增4项真实HTTP/模型检查、1项来源分页控制器和3项历史行布局/分页边界回归；服务端新增非连续ordinal下的真实页码、缺页与只读摘要检查。完整服务端使用专用64MiB共享内存，满足真实ENOSPC用例约束，未削弱磁盘错误断言。旧189/162项证据仍按原实现提交保留。

`d8e3082`同实现最近来源Android完整路径连续三轮通过（360双倍字号一次、390普通字号两次）。原始记录见 [最近原生证据](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-native-recent/README.md)。最近三轮之后，同版本原阅读器完整主路径额外回归一轮通过（33秒），见[回归记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-native-reader/README.md#最近接线后的原阅读器回归)。历史夹具与本轮实际首帧打开明确区分，不把预置27条历史当作本轮显示27包。设计见 [最近页约束](LF5-RECENT-DESIGN.md)。

## 原生翻页与缩放分工

`3f693be` / `9024f88` 修正实际触控问题：InteractiveViewer即使禁用pan也会取得单指拖动，原实现按钮可翻页而手指翻页被截获。现在未放大的单指拖动转入PageView真实ScrollPosition.drag；双指或已放大时取消翻页活动，图片负责缩放与拖动。

PageView不再另注册与图片竞争的水平拖动；直接滚动时保持图片子树可命中，让第二根手指仍可加入缩放，快速连续滑动也能打断前一次吸附。组件测试显式使用touchSlop=8，覆盖较低拖动阈值；此前三种尺寸都在双指处失败，修正后均通过，保留同一断言。跟手中间位置、回弹、LTR/RTL、双指、放大拖动和返回顺序都接真实图片组件。

`9024f88`完整197项客户端测试与Flutter analyze通过；同实现Android操作专项连续三轮通过（360双倍字号一次、390普通字号两次，46/49/55秒），每轮恰有4次实际ADB返回。检查点与原生操作记录见[客户端操作回归](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reader-controls-client/README.md)、[Android操作记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-native-controls/README.md)。完整异常/后台/恢复及真实大图性能仍需继续验收。

## 图片、回执与后台恢复专项

`9ca6518`修正深色阅读画布的错误按钮对比度；`60d5bae` / `aafccee`新增隔离真实HTTP恢复流程，等待异步标签实际出现后再操作，保留大字号换行。图片连续3次503后停止自动重试，不写最近/进度，手动重试成功显示首帧后才opened。未执行的进度请求查询回执404，等待期间不自动补发，明确重试沿用同一请求键与revision；真实写入成功但响应丢失时，GET读回已是新进度，查询回执200解决客户端状态，不再PATCH。

实际Android HOME/重新前台期间核对paused/resumed，暂停时通过真实HTTP读回保存的pageId、比例和新revision。3项widget回归另在暂停通知后不推进假时钟，只处理微任务即核对落盘，避免700ms定时器替代生命周期回调使测试通过；当前完整197项客户端测试与静态检查通过。

标签入口选取2个标签与名称搜索，首批24项但原阅读范围完整25包，另外2包不属于范围。阅读中从当前包移除一个标签，留在原包原页/比例，固定session和25个完整成员不变；手动下一包仍在原范围，返回同一查询后真实结果为24项。最近最终仅包含两包实际阅读内容。每个截图阶段保存真实请求和独立故障记录，区分写入前失败与提交后丢响应。`aafccee`同实现恢复完整路径连续三轮通过（360双倍字号一次、390普通字号两次，55/54/60秒），没有中途修改App或测试。

见[客户端/生命周期记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-reader-recovery-client/README.md)和[原生恢复记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf5-native-recovery/README.md)。本专项不覆盖所有错误码、跳过、连接替换/同连接恢复/旧服务、杀进程或大图性能，不代替完整组合验收。

## 继续实施

- 最近图包列表和统一查询已接线；REC-01中回收内容不显示、恢复保留阅读状态的完整用户流程仍需LF6联动验收。
- 已覆盖整包标签移出当前交集、503图片重试、两类未知进度结果及实际后台保存；补齐其它图片错误码/跳过、连接替换/管理恢复/旧服务、杀进程与完整状态组合。左右翻、缩放/宽适配和沉浸返回的独立专项仍按原检查点保留。
- 500页、4K/8K、快速切包的实际解码、原生内存/延迟与真机性能。现有页清单/缓存限制不是这些测量。
- 全局默认设置界面与正式备份v2、全域恢复隔离由LF7收口；快速整理由LF6实施。

原型继续独立锁定在 `design/reference/`，没有为实现修改原型。真实NAS/正式服务未改，未发布升级APK。

## 2026-10-26：失败末张与横屏错误操作（PR #56）

[Draft PR #56](https://github.com/ShiJiJS/video_viewer/pull/56) 基于 #55，固定源码 `e68f487`，证据提交 `fc97f17`。原型 advance(1) 越过末张会进入 finished；App 原来把“跳过这一张”截回失败末张，且禁用了末张“下一张”。现已接到原生现有本包末尾页，可返回末张/来源，只有明确点击下一包才切换原固定范围；失败图片没有首帧，不写opened、最近、进度或完成状态。

沉浸中到达末尾显示工具，返回动作在黑色画布用白色保持可读。真实844横屏发现17像素溢出，失败/末尾区改为短视口可滚动，保留字体和操作。五项真实HTTP 404/HTTP200非图片解码及完整阅读路由检查回放旧生产代码全部失败，修正后通过。

完整客户端456项、analyze和新夹具/脚本Ruff lint通过。客户端全集在bc3c9fb执行，lib/test树与最终源码相同，最后仅改取证滚动；服务端生产树未改，402项全集沿用#55且本段未重跑。固定源码三轮（360双倍字号37.84秒、390普通36.09秒、844横屏38.74秒）通过，18张实际前台截图、六张源PNG前后SHA、原始轨迹及独立SQL投影保存，253份manifest输入已复核。SQL证实异常包没有progress行、recent只有手动进入且真实显示首帧的正常包。旧源码成功、17像素溢出、测试等待/取证偏移等开发记录单独保留。

[设计与边界](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/LF5-IMAGE-ERROR-DESIGN.md) / [固定源码及证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-reader-image-errors/docs/plans/library-first/evidence/lf5-image-errors/README.md)。本段补PKG-03、READ-01/02/04/05、UI-04/05的失败末张路径，不关闭整项。其余图片错误码/连接恢复/迟到图片、500页4K/8K性能、全原型与目标手机/NAS、原签名发布仍开放；本段使用MemoryCredentialStore，不作为强杀/安全存储证明。生产backup_v2仍关闭，冻结原型树1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24继续开放。

## 2026-10-26：按实际点中的可见末张跳过（PR #57）

[Draft PR #57](https://github.com/ShiJiJS/video_viewer/pull/57) 基于 #56，固定源码 `07d1cad`，证据提交 `92f08b8`。纵向视口顶部仍在倒数第二张时，可以点击下方可见的失败末张。旧逻辑按顶部index拒绝该点击；现按所点图片进入原末尾页，不自动换包，不把失败图片记成首帧或完成进度。

新真实HTTP组件检查在旧逻辑失败，修正后与原五项图片检查共6项通过；完整客户端457项、analyze及夹具/脚本Ruff lint通过。服务端生产代码未改，402项全集沿用#55且本段未重跑。原生390×844普通字号三轮59.20/39.59/38.89秒，顶部index=1、点击图片index=2、比例约70.94%，关键点击没有先滚动对齐；进度前后完整对象相等，包含revision与更新时间，返回原失败末张、退出重开恢复原页/比例，明确下一包才推进。独立SQL仍是上一张真实图片、未完成。

另按同源码跑既有末张/损坏图片844横屏回归一次35.93秒。三轮加兼容回归共21张实际窗口截图、6张源图前后SHA、原始HTTP与SQL投影已保存；119份manifest输入独立复核通过。普通字号三轮不冒充其它视口组合或安全存储强杀验收。

[核查与修复说明](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/LF5-VISIBLE-PAGE-SKIP-AUDIT.md) / [固定源码与证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-visible-page-skip/docs/plans/library-first/evidence/lf5-visible-page-skip/README.md)。本段补READ-02/04/05与PKG-03的明确组合，不关闭整项。接下来推进整体原型对照；其它异常/连接恢复/迟到图片、500页4K/8K性能、目标手机/NAS及原签名发布仍开放。生产backup_v2仍关闭，冻结原型1cbf605独立可移除；未改正式8760/NAS/SDK或发布APK。LF5/#30、LF8/#33及总任务/#24保持开放。
