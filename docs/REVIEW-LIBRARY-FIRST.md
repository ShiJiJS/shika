# 媒体库与图包升级：整体审阅入口

> 第33版已交付（preview.27/code33）及NAS服务preview.9：图包回收站选中后直接后台删除文件夹及全部内容，取消图片核对清单与等待弹窗。图包挂载已可写，升级前后622条回收记录及用户管理数据一致。[交付及检查记录](nas-app-preview-2026-11-03-code33.md) · [PR #187](https://github.com/ShiJiJS/video_viewer/pull/187)。其他持续开发与旧验收仍暂停。

> 第32版已交付（preview.26/code32）：修复大批量图包永久删除清单准备超时，持续显示进度并保存原请求以便续查。[安装及本次171项相关检查](nas-app-preview-2026-11-02-code32.md) · [PR #185](https://github.com/ShiJiJS/video_viewer/pull/185)。NAS服务preview.8不变，其余持续开发和验收仍暂停。

> 第31版已交付（preview.25/code31）：修复前后切换取消，完善回收按钮/顶部撤销、即时数量位置及媒体库多选回收。[安装及本次308项相关检查](nas-app-preview-2026-11-02-code31.md)。NAS服务preview.8不变；其他持续开发和验收仍暂停，下文旧版记录为历史。

> 第30版已交付（preview.24/code30）：按[#177](https://github.com/ShiJiJS/video_viewer/issues/177)精简快速整理并加入沉浸手势。[安装与本次44项测试](nas-app-preview-2026-11-02-code30.md)。NAS服务preview.8不变，其余持续开发与验收保持暂停。下文第29版及更早记录为历史。

> 2026-11-02 图包反馈修复：当前已交付第29版（preview.23/code29），NAS服务preview.8不变。[更新与测试记录](nas-app-preview-2026-11-02-code29.md) · [PR #176](https://github.com/ShiJiJS/video_viewer/pull/176)。只推进 #171–#175，总体持续目标及其余验收保持暂停；下文第28版记录为历史。

[整合PR #168](https://github.com/ShiJiJS/video_viewer/pull/168)。2026-11-02按用户要求将当前源码合并到main，暂停后续开发；已交付版本继续使用第28版App和NAS服务preview.8。

本分支汇总当前可用的第28版App、NAS服务preview.8对应的源码、规划、测试和独立原型，基于主分支`b690f508`，保留主分支新增的`apps/cli`命令行工具。

## 审阅范围

| 内容 | 入口 |
| --- | --- |
| 当前安装、同号回退及已知边界 | [第28版安装说明](nas-app-preview-2026-11-01-code28.md) |
| NAS服务、数据保持与完整备份 | [preview.8部署记录](nas-preview-2026-11-01-service8.md) |
| 已交付能力和剩余事项 | [当前进度](plans/library-first/PROGRESS-CURRENT.md) |
| 原45项的当前边界与具体下一步 | [收口核对](plans/library-first/CLOSING-CHECK.md) |
| 原始方案及45项要求 | [方案](plans/library-first/PLAN.md)、[验收表](plans/library-first/ACCEPTANCE.md) |
| Android程序 | [apps/mobile](../apps/mobile/) |
| NAS服务 | [services/server](../services/server/) |
| 主分支命令行工具 | [apps/cli](../apps/cli/) |
| 独立、可移除的参考原型 | [design/reference](../design/reference/README.md) |

从主分支直接比较全部阶段分支会产生24,026个差异文件，其中23,300个是历史证据。这里将程序、规划和原型保留为本地文件，历史记录链接改为固定提交的GitHub地址，便于查看真正需要合并的改动。原始截图、录屏、日志、失败和中间结果完整保留在[原阶段分支的固定提交](https://github.com/ShiJiJS/video_viewer/tree/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence)，没有删除或改写原分支。

历史记录里的文件路径、摘要和旧候选信息保留原意。需要运行依赖这些历史本地材料的审核脚本时，使用原阶段分支`codex/lf8-purge-selection-pending`；本分支供程序开发和整体审阅，日常构建不依赖这些截图/日志。

## 与已交付版本的关系

初始整合时App、服务和`design/reference`逐文件与固定阶段提交`c9c6363a`一致，主分支9份CLI文件与`b690f508`一致；仅文档的历史证据链接及整体入口作了整理。随后CLI更新为0.1.1，修复过期凭据自动重登录后继续旧修改命令的问题，并补隔离环境、锁文件和VS Code任务。App第28版另修复图片移除后的续读提示过早消失，实际构建来源为`fc564a96`；正常包和同号回退包已交付NAS。服务preview.8继续使用`2de02374`，独立原型未变。

复用既有验证：服务534项和客户端第27版41项相关检查。第28版仅补21项阅读相关检查、正常/同号回退包的分析和构建签名校验，以及普通APK的图片移除前后画面对照；范围见安装说明。它们不替代实体手机、性能或完整45项验收，不把累计测试数当成整版通过。

## 尚未完成

真实手机覆盖安装、声音、手势、系统/云文件选择及完整性能仍需实际设备。#78、#89、#100的历史偶发问题保持开放；已交付的可用版本和这些待确认条件分别报告。其余整版组合按原验收表继续核对。

本次合并用于固定当前可用版本，阶段PR保留作为实施历史；不因源码合并将原45项全部判定通过。其余验收及正式发布保持原边界，原型继续独立可移除。
