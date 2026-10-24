总任务：#24

## 目标

图包需要按漫画阅读方式浏览，管理单位始终是整包。原型的横翻/纵向/总览/沉浸、包间范围和逐包进度必须落实到真实图片和原生生命周期。

本任务属于 LF-2026-10-23 媒体库/图包改造，沿用独立冻结原型。`cb02a67`已接入固定完整范围、逐包进度/偏好、实际opened后的最近、只读回执与schema0009；完整162项服务端测试/Ruff通过。`04f57a8` / `f43a320`接入连接与恢复代次绑定的类型化客户端接口及发布归属检查。

`278a774` / `91f1112`现已接入真实原生PackReadingSession和阅读路由：卡片进入横翻/纵向拼接、方向/缩放/适配/间距、分页总览和跳页、沉浸、整包标签、固定范围内手动换包、保存/关闭后续读、返回原媒体库。实际当前图片首帧才记打开；预加载不记历史，元数据/图片provider有界，未知写结果先查回执。Paper最小52dp顶栏自然适应大字号，工具图标上对齐且避免中文孤字。

当前完整 **197项客户端测试、Flutter analyze和163项服务端测试/Ruff通过**。最近图包已按冻结原型接入纵向历史行；查询来源和排序贯穿列表、分页、全选、定位及阅读入口，与媒体库筛选互不污染。进度页码按当前清单的稳定pageId位置计算；分页边界返回先补足尾页，再恢复原视口锚点。见[最近实现及检查](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-recent-catalog/README.md)。

`d8e3082`上最近来源Android/8761完整路径连续三轮通过（390普通字号两次、360双倍字号一次）：实际新包首帧、跨24项分页、完整28包全选、末包续读、历史重排后的固定范围和原位返回、媒体库筛选保留。27条预置历史不算本轮实际阅读，见[最近原生证据](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-recent/README.md)。此前`91f1112`阅读器主路径三轮证据独立保留于[阅读原生记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/evidence/lf5-native-reader/README.md)，不混称为当前版本三轮。当前`d8e3082`在最近三轮后另跑一轮原阅读器完整回归通过（33秒），同目录保留独立日志与截图。

REC-01的回收隐藏/恢复保留状态仍需LF6联动；完整来源/异常/后台/恢复组合、左右手势/缩放/沉浸等原生验证、500页4K/8K的真实内存与延迟仍待补。全局默认设置界面和备份v2由LF7收口，快速整理由LF6实施。本issue继续开放，PR保持草稿。详见[设计契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5-DESIGN.md)、[界面约束](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5-UI-DESIGN.md)和[实施记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5.md) / [草稿PR #39](https://github.com/ShiJiJS/video_viewer/pull/39)。

## 依赖

LF2 (#27)、LF4 (#29)

## 实施范围

- PackReadingSession 独立于视频解码器；固定包范围在服务端创建并分页，手动上一/下一包不越界，纵向到底不自动切包。
- 实现横向翻页、左右方向、缩放/适配、纵向惰性拼接、间距、总览/页码跳转、沉浸与整包标签入口。
- 保存 pageId+页内offsetRatio+revision、每包模式/方向/间距/适配；模式切换保留图片，重开续读；默认仅用于未设置包。
- 实际阅读更新最近；删页后回退最近有效页并说明，后台/离页节流flush，旧请求不覆盖新包。
- 按显示尺寸解码、已知宽高占位、有限图片窗口与字节缓存，取消旧连接/旧包读取；缓存阈值以大图夹具和真机测定。

## 主要代码

- `apps/mobile/lib/features/packs/（新增）`
- `services/server/video_viewer/reading.py（新增）`
- `apps/mobile/lib/ui/preferences.dart`

## 完成标准

- [ ] 所有阅读方式、总览、沉浸、续读、包间范围和返回来源与原型一致。
- [ ] 图包标签始终作用整包，没有单张管理入口。
- [ ] 500页、4K/8K及快速切包测内存/延迟，无无限预解码；单页错误不锁阅读。

验收 ID：READ-01–06、NAV-02、LIB-02、REC-01、UI-02/04

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
