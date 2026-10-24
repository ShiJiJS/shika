总任务：#24

## 目标

图包需要按漫画阅读方式浏览，管理单位始终是整包。原型的横翻/纵向/总览/沉浸、包间范围和逐包进度必须落实到真实图片和原生生命周期。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，当前服务端阅读会话实施中，客户端阅读UI尚未接入。`cb02a67` 完整162项服务端测试（含8项阅读接口用例）与Ruff通过。`04f57a8` 又接入连接/恢复代次绑定的类型化客户端句柄、不可变写命令与只读回执、严格清单/回执校验；接线179项检查后，f43a320补发布后的最终归属检查，当前180项客户端测试（含9项新HTTP适配）与静态检查通过，原生阅读会话/界面仍待接入。固定完整范围、分页队列、位置/进度/偏好版本、实际打开后的独立最近和默认值均已接入真实接口；schema0009保留原进度并增加删页回退原因和偏好版本。详见 [设计契约](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5-DESIGN.md)。见 [实施记录](https://github.com/ShiJiJS/video_viewer/blob/codex/lf5-pack-reader/docs/plans/library-first/LF5.md) / [草稿PR #39](https://github.com/ShiJiJS/video_viewer/pull/39)。横翻/纵向/总览/沉浸、客户端生命周期与大图内存验收仍待实施，本issue继续开放。

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
