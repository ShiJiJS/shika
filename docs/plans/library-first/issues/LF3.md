总任务：#24

## 目标

当前列表搜索不进入 PlaybackScope，eligible 持续重套标签，删除标签会重建轮次。原型要求先选范围再预览、预览中改标签不跳位、返回恢复入口。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

## 依赖

LF1 (#26)

## 实施范围

- 查询草稿与播放会话分开；begin 接受完整 search/directory/tags/attributes/sort/source/anchor/requestId，服务端计算全部候选，不仅已加载页。搜索覆盖视频名称与目录，列表和会话使用同一搜索语义。
- 新会话带固定成员协议，随机和顺序只重排本范围；改标签/删标签/新增内容不重新求候选，失效/回收/停用项可跳过但不越界。
- 保存 BrowseContext 与列表 anchor，结束/返回回到来源；最近视频按实际打开记录，预加载不写历史。
- 保留 revision、幂等创建、有限窗口、迟到回执保护；旧视频接口默认兼容，旧轮次不扩大为全库。
- 复用现有暂停、长按2倍、进度、横屏、亮度音量及最多3解码器，关闭相邻准备只保留当前；预览不再是主导航。

## 主要代码

- `services/server/video_viewer/playback.py`
- `services/server/video_viewer/tags.py`
- `apps/mobile/lib/library/server_repository.dart`
- `apps/mobile/lib/ui/browsing_session.dart`
- `apps/mobile/lib/ui/playback_session.dart`
- `apps/mobile/lib/ui/player.dart`

## 完成标准

- [ ] 搜索后预览总数与全部匹配一致；标签交集/目录/最近范围不泄漏。
- [ ] 预览中编辑标签不跳位；末尾不跳全库，返回滚动位置可恢复。
- [ ] 原生手势、后台/前台、快刷、网络故障、回执乱序回归通过。

验收 ID：NAV-02、LIB-01、PRE-01–05、REC-01、SET-02

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
