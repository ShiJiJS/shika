# LF8：复选框的选择反馈与实时减少动画

[草稿PR #117](https://github.com/ShiJiJS/video_viewer/pull/117)按[#116](https://github.com/ShiJiJS/video_viewer/issues/116)承接菜单/下拉与原版服务首页补证，继续UI-06。固定基线683306d5的真实TrashEntryRow组件三项诊断均失败：普通140ms实际绘制进度约0.556（控制器200ms），减少动画首帧仍0，进行40ms后开启减少动画仍约0.063。回调即时且只有一次；这是组件FakeAccessibilityFeatures输入，不是Android系统证明。原始日志和诊断源文件保留，不把首次编排模板转义错误（命令未执行）计作测试。

范围清单为四处CheckboxListTile（图包/视频永久删除确认、v2/旧格式恢复确认）与共享回收行内一处Checkbox。调用点数不是缺陷数；当前只有真实回收行有上述失败证据。展开项另按自身契约核对，不与复选框混成同一问题。

采用一个App内复选模块，沿用现有Checkbox/CheckboxListTile的参数形式、SDK公开ToggleableStateMixin输入/键盘/焦点/语义机制，以及固定SDK的绘制/颜色/尺寸规则。仅由App拥有的State通过公开控制器管理140ms选择反馈、100ms按压，以及减少动画首帧/中途立即到位；不访问SDK私有状态、不升级SDK。整行原布局与单一合并语义保留，四个确认仍只更新草稿，原确认提交和连接代次判断不改。适配代码保留Flutter BSD许可。

先核对针对普通/减少/运行中切换、取消/快速反转/禁用/空值/三态、键盘/焦点/单次回调；深浅、LTR/RTL、普通/整行/禁用/三态的静态RGBA与原SDK比对。再运行受影响业务与完整客户端/分析，按证据区分源码/组件、真实Android、正常包各阶段，不用测试替身冒充系统输入。不操作真实删除或恢复。原型仍独立可移除、服务与现有code16两包保持；手机/NAS/有声和完整45项继续。

源码与组件结果：五处入口已接入PaperCheckbox/PaperCheckboxListTile。正常仅Material接口，继续由公开ToggleableStateMixin处理原生输入/焦点/语义；保留固定SDK的绘制、M2/M3默认色及ListTile布局，Flutter BSD原许可沿用。State仅管理140ms位置、100ms按压；普通焦点/悬停淡入保留原50ms，减少动画均0并在依赖变化首帧到位。

11项针对检查通过，包含真实TrashEntryRow三个回归、文本/框点击各一次、Space/Enter/焦点保留、普通/减少的按住取消、中途减少的按压、快速反向与禁用、三态；同一检查内96组深浅/M2-M3/LTR-RTL/false-true-null/禁用/普通-整行RGBA与尺寸逐字节相同。完整777客户端（含既有四种确认页面回归）与分析通过。语义检查仅对恢复false后的原SDK合并节点表示做对照，三态值和绘制端点另外核对，不据此关闭完整UI-05。

新增发现：原SDK与初版适配都在“按住→禁用”时因子手势识别器销毁触发父State在build期间setState而失败，原SDK独立诊断已复现。最终适配在didUpdateWidget阶段通过自己公开GestureDetector的取消回调先结束按压；保留原输入机制，不反射或调用SDK私有状态，确认值不变/不多发回调。针对检查覆盖该修正。

原始失败分开保留：最初三个真实回收行反例、原SDK按住禁用、初版适配同问题；语义测试错误假定原合并父节点独自包含全部后代标志/没有focus动作，改为与原SDK真实表示对照；随后语义Handle测试清理晚于框架核查，改为finally内释放。四项仅测试代码的分析提示已处理。失败不计入成功11项，未改SDK。

真实Android系统/输入已由[独立三轮补证](LF8-CHECKBOX-NATIVE.md)完成：90方向、24次真正中途切换、6次按住后禁用、6录像和恢复通过；普通正常包业务已由[code17配套段](LF8-CHECKBOX-PACKAGE.md)补齐本机检查。当前code16两APK不含本段源码，SHA不变；展开/其它自有过渡另核查，完整UI-06/45项与手机/NAS、有声等仍开放。

固定源码2a4e9cd7，[13份原始输入与离线复核](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-checkbox-motion/README.md)已保存；本段源码/组件证据保持；后续原生项已补，#116整合包本机项现由code17配套段补齐，整体终验继续。
