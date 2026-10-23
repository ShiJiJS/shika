# LF0 模块契约与后续接线

LF0 保留旧版可运行路径，LF3/LF4 才切换固定会话与新导航。这份清单把已实现接口和后续接口分开，不用空实现假装新功能完成。

| 模块 | LF0 已接入的接口 | 不变量 / 下一步 |
| --- | --- | --- |
| AppShell | header/content、destinations、selected/onNavigate、showNavigation | SafeArea/Scaffold/底栏统一，保留既有 nav-* Key、尺寸和状态。LF4 更换四入口并拆出功能页，LF0 不提前丢掉旧入口 |
| VideoBrowseContext | query、search、source、scrollOffset/anchor；queryKey | 不持有播放器或发写命令；tag 集合顺序不改变查询身份，滚动不触发重查；LF1 加入类型专有的 PackQuery，LF3 保存来源恢复 |
| LibraryQueryController | load(context, more)、state、cancel/dispose | 查询只调用 LibraryRepository.loadVideos，永不 setScope/openVideo；24 条分页，迟到结果无效、翻页失败保留卡片/原 offset、停止加载、显式错误 |
| Viewing | 现有 BrowsingSession / PlaybackSession | LF3 接收完整入口范围、固定候选/revision 与返回上下文；LF0 不改变旧轮次语义 |
| PackReader | 尚未实现 | LF2 确定页清单/版本/鉴权，LF5 接 reading session；不拿视频实体占位 |
| Maintenance | 现有 LibraryRepository、ServerBackups、命令回执 | LF6/LF7 再拆页面与统一任务；未知请求只读核对，不重放删除或恢复 |

当前真实与演示实现都经过同一个 LibraryRepository 读取接口。同步 snapshot 不是完整媒体库；query controller 仅公布已读页及权威 total，不在前端伪造全库计数。来源、筛选、排序和会话完整范围的服务端协议仍以 PLAN 的 LF1/LF3 项实施。

生命周期：页面退出调用 cancel 使 in-flight 回应失效并保留已读卡片，销毁先移除监听再 dispose；controller 不拥有 repository 生命周期。连接与恢复触发旧读取失效的既有 generation/RequestScope 保护仍在 server adapter 内；LF0 增加页面读取代次，不移除网络层保护。
