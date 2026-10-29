# LF8：扫描详情展开的真实 Android 验证

承接[#120 / 源码PR #121](https://github.com/ShiJiJS/video_viewer/pull/121)，生产展开模块固定6af88978。本段不改生产lib，使用实际LibraryHome目录页、非DemoControls只读fixture，真实原生点击与系统三个动画比例；不注入无障碍替身，不执行扫描或文件命令。

计划三轮，每轮普通/减少/运行中切换两方向，共18个完整展开/收起方向、6次真正中途切换；每轮再由fixture模拟扫描进行/失败/完成，检查替换正在展开的摘要和正确一份详情，共3次额外点击/9个状态，分开计数。每轮完整录屏，共3份，全部解码并独立审计。

帧回调仅用公开Element/Widget属性：实际Align高度、箭头RotationTransition、拥有控制器的公开AnimatedBuilder监听值、原生PlatformDispatcher与MediaQuery标志。普通160ms应保留中间态；减少首个原生标志帧高度/箭头直接到目标，中途切换上一帧必须严格处于(0,1)。回调不调用WidgetTester查询，不访问SDK私有State或伪造时钟。

进入前盘点AVD/QEMU及原四服务，记录实际显示/字体/旋转/比例/调试权限。只启动自有无声测试AVD，安装独立profile入口，不覆盖已交付正常code17文件。结束恢复实际进入值并关闭自有资源，核对原四服务。此证明不是正常main真实服务、手机/NAS、有声或完整UI-06/45项终验；正常包项继续单独推进，原型独立可移除。
