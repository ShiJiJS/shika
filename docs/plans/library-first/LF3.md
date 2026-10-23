# LF3：视频固定范围（实施中）

对应 [#28](https://github.com/ShiJiJS/video_viewer/issues/28)，基于 LF2 分支，服务实现提交 `08fb641`。当前先完成服务端协议，客户端 adapter、来源恢复、原生二级预览路径与手势/生命周期回归继续实施，LF3 尚未完成。

## 服务端已实现

- `POST /rounds` 显式指定 `membership=fixed`，同时接收 search、目录、标签交集、方向/时长/类型、source、sort、anchor 与 request_id。候选由服务端全范围查询生成，和已加载的第一页无关。查询与创建使用相同的名称/相对目录搜索及排序。
- 固定会话只排除目前不可用的成员，不再重新套用原标签/目录/属性过滤；编辑或删除标签、新增文件、扫描刷新不重建会话。旧调用默认 `legacy`，保持旧客户端原有协议。
- 切换随机/顺序走独立的 `PATCH /rounds/{id}/order`；只重排存储成员，保留当前视频。顺序基于进入时的原始排序，不跟随后来变化的最近顺序。`restart=true` 从原范围重新开始，也不吸纳新内容。创建、重排和位置更新均有幂等或 revision 校验。
- `GET /playback?create=false` 在尚未开始时返回 `404 round_not_started`，允许新界面只读连接状态；原调用默认保留自动创建旧轮次的兼容行为。最终新客户端须使用只读模式。
- 最近视频只在 `POST /rounds/{id}/opened` 核对实际当前视频后去重更新；请求可幂等重试。列表、队列和封面预取不写历史。`GET /recent?kind=video` 分页读取；`source=recent` 创建范围只使用最近成员。图包最近接口留给 LF5。
- 视频撤销在固定会话中保存视频 ID，重排后按 ID 恢复；删除原过滤标签也不阻止找回原视频。旧回执按原 cursor 继续兼容。
- `0006 → 0007` 增加轮次 membership/source/sort 和成员 source_ordinal；旧轮次默认 legacy，旧候选不扩大。v1 备份投影仍为精确 0004 列，有固定会话时明确要求 LF7 的 v2，避免遗漏新语义。

## 接下来

1. Server/Demo adapter 接受独立的入口上下文，完整传递 search/source/sort，固定会话的重排与重来使用新接口。
2. 预览 route 保存并返回来源列表、类型、搜索、筛选和 anchor；实际显示后确认 opened，预取不触发。
3. 保留现有 BrowsingSession、最多三解码器、原生倍速/长按/横屏/亮度音量，补迟到回执、返回、故障与生命周期的原生回归。
4. 与 LF4 四入口衔接后对照原型入口及返回路径，完整通过后再勾选 LF3 标准。

冻结镜像的服务端全量回归 **145 项通过**；验证记录见 [服务端结果](evidence/lf3-server-results.json)，[源码哈希](evidence/lf3-server-source-sha256.json) 锁定本次代码。服务层通过不等同于 PRE-01–05/NAV-02 等原生验收已通过。所有测试仍使用可丢弃合成素材，独立原型未修改。
