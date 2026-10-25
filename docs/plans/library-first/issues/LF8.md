总任务：#24

## 目标

功能有按钮或APK能启动不等于实现了原型。最终需要同状态原生截图、完整真实服务流程和现有版本升级证据。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

## 依赖

LF0 (#25), LF1 (#26), LF2 (#27), LF3 (#28), LF4 (#29), LF5 (#30), LF6 (#31), LF7 (#32)

## 实施范围

- 按 ACCEPTANCE.md 的 NAV/LIB/TAG/PRE/PKG/READ/REC/DEL/SET/BAK/UP/UI ID 填 RESULTS.md，每项附实现提交、步骤、证据、残余差异。
- 复用VS Code/F5与8760/8761隔离环境，旧视频回归+新图包API/迁移/任务故障测试；关键原生路径连续3轮。
- 同非私人素材、同状态做390×844并排，补360×740/横屏/暗色/大字体/键盘；动作与手势另录屏。
- 真实手机+NAS测首屏/首帧/翻页、p50/p95、内存、NAS CPU/IO/流量；破坏性测试仅可丢弃样本；模拟器不冒充真机性能。
- 先兼容服务端再App，保存升级前快照；原包名/签名、递增versionCode覆盖安装。回退服务用旧快照，不能旧二进制直接读新schema。

## 主要代码

- `docs/plans/library-first/ACCEPTANCE.md`
- `apps/mobile/integration_test/`
- `services/server/tests/`
- `scripts/run-client-connection-test.py`
- `docs/macos-development.md`

## 完成标准

- [ ] 所有验收ID有证据；必要功能、尺寸层级和返回行为与原型一致，偏差具体说明。
- [ ] 旧ID/标签/回执/连接/本机偏好保留，旧版覆盖升级可重复。
- [ ] 总任务只有此验收完成才关闭；未实测或仅Demo完成的项目保持未完成。

验收 ID：全部验收项；真实目标环境验证是独立门槛。

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。这些文件目前已写入 Mac 工作区，尚未推送，LF0 (#25) 负责纳入 Git 基线。当前原型：`prototypes/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。

## 2026-10-25：PR #47 原生截图复查项

#47的目录类型/启停、分类型缺失页、固定清理与原回执路径在固定59f78b6原生三轮通过，27检查点的窗口/请求/文件/数据库与源码已独立复核；不等于LF8整项通过。证据：[目录与缺失管理](https://github.com/ShiJiJS/video_viewer/blob/codex/lf7-roots-missing/docs/plans/library-first/evidence/lf7-roots-missing/README.md)。

- [ ] 新建目录尚未首次扫描时，当前沿用红色“目录暂不可用”；统一未扫描、离线、停用状态与提示，避免混淆。
- [ ] 任务详情SelectableText编号在部分普通/双倍字号截图中缺字或裁剪；需复查实际渲染与采集时序并修正，不能以接口任务ID正确替代文本显示验收。
- [ ] 继续完整深浅色、横屏、视频手势与目标手机/NAS验收；当前App/Repository重建是在同一进程，不算新增强停证据。

系统ANR曾真实遮挡早期截图，已保留诊断和受控恢复记录。正式三轮每个截图均要求App持有Android前台焦点，系统窗口遮挡会让宿主验收失败。原型基线保持独立未改，未发布APK。
