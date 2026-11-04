# LF8：目录扫描详情的展开与减少动画

[草稿PR #121](https://github.com/ShiJiJS/shika/pull/121)已提交，源码/组件完成，[真实Android](LF8-EXPANSION-NATIVE.md)与[正常包实际服务](LF8-EXPANSION-PACKAGE.md)本机项均已补齐。后续持续目标已恢复，总验收继续开放。

按[#120](https://github.com/ShiJiJS/shika/issues/120)继续UI-06，承接正常code17候选PR #119。实际唯一入口为LibraryHome的root-scan-details，完成扫描时折为摘要，异常仍外置详情。基线d6b67725的真实目录页/非DemoControls只读fixture六项反例：普通160ms展开/收起高度系数约0.692/0.063，减少动画首帧仍0/1，中途40ms开启减少仍约0.063/0.692；逻辑输入为组件替身，不算Android系统接入。

100/140/160/240ms来自既有UI-06契约。扫描明细采用160ms内容展开层，与快速整理展开同层；这是本段在已有层级内的适用判断，不声称原型为此服务状态面板单列了160ms。原SDK默认200ms且运行中不读减少偏好。只设置公开expansionAnimationStyle(160/0)也不能完成已有动画，两方向首减少帧仍约0.094/0.622；原始诊断保留。

使用范围明确的App展开组件，仅接原入口的title/children/tilePadding。App拥有逻辑展开状态和动画控制器，普通160ms/减少首帧直接完成；逻辑和语义立即切换，内容更新不重置展开。保留固定SDK此用法的ListTile/箭头、颜色/边框/布局、键盘/焦点/语义、PageStorage和折叠后卸载约定；不访问SDK私有State，不替换或修改SDK。借用的渲染/语义保留Flutter BSD许可，不承诺未使用的ExpansionTile全量参数接口。

先以原六失败作回归；补普通/减少/中途双向、快速反转、内容更新、离树、键盘/焦点、读回状态和深浅/M2-M3/LTR-RTL/闭合-展开的静态RGBA/尺寸对照，再跑受影响与完整客户端/分析。后续真实Android仍须使用系统设置/原生输入及独立审计，正常main与新候选包另外核对。源组件通过不关闭后两项。

不调用扫描/删除/恢复命令，不操作文件、服务或NAS。保留code17两APK及独立可移除原型，服务/SDK不改；其它自有过渡、完整手势/45项、目标手机/NAS/有声/云提供器及#78/#89/#100继续开放。

## 源码与组件完成

固定生产源码6af8897813df61ffc6476a4c0213624bb544f0d1。PaperExpansionTile为原三参数用法拥有状态/160ms控制器，减少偏好变化时同步跳到逻辑目标。保留固定SDK此用法的布局、颜色、箭头/边框、ListTile平台语义/公告、键盘、PageStorage与内容卸载；Flutter BSD许可保留。原根状态/扫描业务没有重写，只替换构造名。

12针对通过：六个真实目录回归，一个检查内32组深浅/M2-M3/LTR-RTL/收起-展开/默认-13号标题RGBA与尺寸完全相同；内容变更/草稿与焦点、双向减少首帧/箭头、快速反转/离树、Enter/Space/PageStorage与原SDK比较、两个Android端点原语义表示、扫描进行/失败/完成替换保持一份正确详情。完整789客户端与分析通过。

[13份原始输入与离线复核](https://github.com/ShiJiJS/shika/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-expansion-motion/README.md)已冻结。实际基线六失败、style-only两失败、全树箭头选择器过宽导致的两项测试失败，以及if花括号的一条分析提示分开保留；未放宽高度/端点或像素断言。最终源含花括号修订，完整789再次涵盖全部新增检查。

源码/组件项已完成；真实Android系统/输入现由[三轮18方向、6中途切换及9个扫描状态](LF8-EXPANSION-NATIVE.md)补齐，正常main实际服务目录/扫描状态和后续配套包仍待验收。SDK/服务、原型1cbf605与当前code17两包保持；本源码段未启动AVD/容器或操作真实媒体/NAS，不称完整UI-05/06或45项完成。
