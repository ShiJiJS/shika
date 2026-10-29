# 扫描详情展开：源码与组件阶段

固定生产源码 `6af8897813df61ffc6476a4c0213624bb544f0d1`，基线 d6b67725，issue #120。13份原始输入由manifest冻结。离线只读复核，不启动设备/服务、不访问数据库：

```sh
python3 docs/plans/library-first/evidence/lf8-expansion-motion/verify.py
```

实际LibraryHome的root-scan-details六项基线检查均失败：160ms普通展开/收起高度约0.692/0.063，减少首帧仍0/1，中途40ms后开启减少仍约0.063/0.692。只设置公开expansionAnimationStyle(160/0)的更小方案在两方向中途也失败，首减少帧高度约0.094/0.622。原失败与相应诊断源文件保留；非DemoControls只读fixture触发真实目录页，FakeAccessibilityFeatures仅组件输入，不称实际Android系统证明。fixture未调用扫描或文件命令，未用Demo隐藏路径冒充。

采用仅覆盖原title/children/tilePadding用法的PaperExpansionTile，App拥有逻辑状态与控制器，160ms属于现有内容展开层级的适用判断，不冒称原型对此服务状态面板有独立160ms条文。保留固定SDK的ListTile/箭头、颜色/边框/布局、平台语义与公告、键盘/焦点、PageStorage及收起后移除内容；不访问SDK私有状态或改SDK。渲染/语义保留Flutter BSD许可。原入口只换构造名，扫描状态条件、进度/错误显示及业务调用不改。

最终12项针对通过：原六真实入口回归；一个检查内32组深浅/M2-M3/LTR-RTL/收起-展开/默认-实际13号标题的完整RGBA及尺寸相同；内容更新/正文草稿焦点、减少首帧高度与箭头、快速反转/离树、Enter/Space与原SDK的PageStorage比较、Android头部两个端点SemanticsData原表示对照，以及真实扫描进行中/失败/完成切换只显示正确一份详情。静态比对和语义对照不是完整UI-05或TalkBack认证。

完整789项客户端及分析通过。本段SDK两个源文件SHA、独立原型树1cbf605、code17两APK和原四服务完整ID/健康均核对保持。未启动AVD或容器，未操作真实媒体/NAS；服务生产源码未改。当前正常preview.11/rollback.11仍是前段候选，不含本段展开修复。

原始中间失败不计通过：target-1仅原六项通过；target-2九过/两失败，原因是测试从全树找RotationTransition而匹配多个，改为实际expand_more图标的箭头，未放宽数值；target-3完整12通过。analyze-1只有新模块if缺少花括号的一条提示，补块后analyze-2干净，最终固定源码完整789再次覆盖全部新增检查。原六失败和style-only两失败与测试选择器错误分开，不混称同一个产品问题。

源码/组件项已补齐，真实Android系统/原生输入和正常main实际目录/后续候选包仍待完成。其它自有过渡、完整手势/45项、目标手机/NAS/有声/云提供器、#78/#89/#100继续开放；原型独立可移除，不合并或正式发布。
