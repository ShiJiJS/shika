# 复选框源码与组件阶段

固定生产源码2a4e9cd780857ce543ccb63b926aeb23ecf96c3c，基线683306d5。13份输入由manifest冻结；离线只读检查：

    python3 docs/plans/library-first/evidence/lf8-checkbox-motion/verify.py

真实TrashEntryRow原三个反例：控制器200ms、140ms绘制进度0.55556；减少首帧0；40ms后开启减少首帧0.06255。值已即时更新、一次回调，FakeAccessibilityFeatures不是Android系统。原始诊断文件与失败日志配套保留。

新PaperCheckbox/PaperCheckboxListTile由App拥有State，通过公开ToggleableStateMixin控制自己的位置/反应控制器；沿用固定SDK绘制/默认色/ListTile布局，BSD许可保留。五处入口仅替换构造名，提交/确认/连接代次判断不变。原SDK和初版适配另复现按住后禁用导致build期setState；最终在父State更新阶段通过自己公开生成的GestureDetector取消回调先结束按压，没有调用或反射SDK私有状态。

target-1三项修正通过；target-2保留禁用问题与错误的语义观察假设；target-3语义断言通过但测试Handle清理过晚，target-4在finally释放后11项通过。语义原假设不含focus动作、父节点独自拥有全部后代标记有误，改为与原SDK恢复false的合并节点实际表示比较；不称完整无障碍已验。三态值/端点、行/框单次激活、Space/Enter与焦点、按住/取消/实时减少、快速反转/禁用另有断言。原失败不删除、不计成功用例。

同一几何检查包含96组完整RGBA和尺寸逐字节对照：深浅、M2/M3、LTR/RTL、false/true/null、启用/禁用、独立/整行。仅证实稳定终态和尺寸，不以截图冒充时序。为保留Paper其它主题参数，该兼容对照局部使用SDK尚存在的useMaterial3 copyWith参数；正式分析已处理四项测试代码提示。source-audit记录11针对、777完整客户端、分析通过；完整套件包含原有四类确认业务检查。

SDK revision与三个源文件SHA不变；原型树1cbf605独立未改，服务/SDK/原四容器、正常code16两包SHA保持。此阶段没有启动Android资源、没有真实媒体/删除/恢复或NAS部署。源码已改而code16未重建，不把旧包称已包含复选框修复。真实Android输入/系统、正常main新包与实际业务、其它展开/自有过渡和完整45项继续。
