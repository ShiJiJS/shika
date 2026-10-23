总任务：#24

## 目标

当前 home.dart 有 2624 行，列表筛选、全局播放轮次和管理页共处一个 State；后续直接叠加图包会让返回、保存和错误状态相互影响。先保存确认原型，再逐页抽出可运行骨架。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，LF0 已实现并验证；其余功能继续按后续任务实施。

## 依赖

无；本轮首项。

## 实施范围

- 固定 LF-2026-10-23 原型及依赖；提交可分享源码/非私人夹具，记录基线提交、SHA-256 和参考截图；私人图包、字体副本、密钥不上传。
- 沿用 Flutter ChangeNotifier，不引入新框架。先抽 AppShell、BrowseContext 与功能页 seam，保留旧视频兼容入口；Server/Demo 使用相同行为接口。
- 固定视频、自然排序/嵌套/坏图/500页/4K-8K图包夹具；为各验收场景分配稳定 Key。
- 复跑旧客户端/服务基线，记录已有 Ruff 格式失败；建立视觉截图及真机性能测量步骤。

## 主要代码

- `apps/mobile/lib/ui/home.dart`
- `apps/mobile/lib/library/repository.dart`
- `design/reference/library-first/`
- `docs/plans/library-first/`

## 完成标准

- [x] 旧视频播放、连接、逻辑回收、备份继续通过，不因拆分破坏现有行为。
- [x] 原型参考版本可复现，ACCEPTANCE.md 的每项可定位到原型状态和后续任务。
- [x] 没有借重构改变已确认产品入口；骨架更改与视觉改造分步可审查。

验收 ID：UI-01–06、UP-01；本任务先建立基线，不代表新产品验收完成。

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
