# LF4 原生媒体库检查点

真实 Android App + 8761 隔离 FastAPI 服务；27 个整包 / 81 张公开花卉图片，按 24 项跨页。真实 NAS 和 8760 常规服务不参与故障或删除验证。

`390/` 为 390×844dp、3×像素密度、普通字号；`360-large/` 为 360×740dp、3×像素密度、系统字号2。截图保留真实系统状态栏与手势安全区，不能与 HTML 假 home indicator 叠加比较。`host-events.json` 记录视口和实际捕获阶段。源码、日志和图片摘要见上级的 `lf4-workspace-results.json`。

每组为视频、图包、视频标签、图包标签、设置和暗色六张。`anchor/` 保存73条深列表的可见重试和恢复位置。`390/` 已更新为修正后 `5f66d0c` 的复跑截图，`360-large/` 保留 `ee3e624` 的大字体截图。工作区最初三轮属于 `ee3e624`，可见重试修正后的深列表三轮属于 `5f66d0c`（生产修正在 `4f4e795`）；提交与复跑结果分别记录，不能跨提交冒充全部覆盖。原型对照位于独立的 `design/reference/library-first/shots/`；生产代码不加载该目录。`visual-review.md` 保留一次独立评审和三项修正后的复核，静态看图与主 Agent 的实际交互验证分别陈述。

运行（同一时间只能执行一个 Flutter 检查）：

```sh
bash scripts/dev.sh python3 scripts/run-client-connection-test.py --workspace
bash scripts/dev.sh python3 scripts/run-client-connection-test.py --workspace --workspace-viewport 360 --workspace-text-scale 2
bash scripts/dev.sh python3 scripts/run-client-connection-test.py --anchor
```

运行器只允许指定的专用 AVD，暂时改变该 AVD 的尺寸、密度与字体，退出时恢复旧值。每轮重置专用 8761 实例，保留 ordinary 8760；图包夹具仅写 `/media/shorts/图包`，通过公开根目录/扫描/标签 API 建立索引，没有直接伪造数据库中的包或标签。

验证实际库/标签来源的搜索隔离、27包跨页、同名两类标签的独立计数、查看结果和直接进入固定视频预览并返回、旧设置入口、主题切换后的搜索、鉴权封面和繁忙的有限重试。大字体下会像用户一样滚动定位标签，不把尚未构建的首屏外行误判为未加载。封面成功检查针对当前可见区域；最终失败仍有手动重试。

这不是 LF4 或整个产品验收完成：分页视频标签、完整跨页批选、更多错误/返回组合仍要补齐；图包阅读/进度/最近、快速整理和设置/备份 v2 分别属于 LF5–LF7，真机/NAS性能及完整原型一致性由 LF8 收口。
