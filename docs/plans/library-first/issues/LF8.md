总任务：#24

## 目标

功能有按钮或APK能启动不等于实现了原型。最终需要同状态原生截图、完整真实服务流程和现有版本升级证据。

本任务属于 LF-2026-10-23 媒体库/图包改造；用户已确认当前完整原型为方向，本次登记计划，尚未实现。

## 依赖

LF0 (#25)、LF1 (#26)、LF2 (#27)、LF3 (#28)、LF4 (#29)、LF5 (#30)、LF6 (#31)、LF7 (#32)

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

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
