# Android系统减少动画：原生动作检查

UI-06、#97 / PR #98的视频控件修复已进入正常preview.3，但此前只有组件、构建及整合检查。此阶段核对实际Android系统设置到Flutter/当前App控件的传递，不注入测试无障碍值或MediaQuery开关。

独立profile入口使用当前VideoViewerApp和普通隔离服务，从媒体库进入视频预览，等待真实路由进场完成，按实际布局坐标经Android input点击，执行内嵌控制条自动隐藏、实际旋转横屏后的控制条/返回控件隐藏、真实Android返回。核对原生decoder的isPlaying状态，控件隐藏不改变播放意图、当前controller或固定视频范围。各三轮比较系统动画开/关；读取真实PlatformDispatcher及当前PlayerSurface的MediaQuery值。

保留的旧式控制条和可选caption位置另用生产PlayerSurface、真实asset解码器及实际横屏做组件原生检查；这部分不称整个旧服务兼容流程。本段需要同时观察普通160ms的中间态、减少动画时首个目标隐藏帧直接为0、caption移动34dp；配置duration和设备帧时间分别记录，不把Flutter帧回调叫物理屏幕呈现时间。

Android全局window/transition/animator动画比例由拥有该AVD的宿主设置并读回，最后恢复进入阶段前的原值。全程使用独立AVD5558、独立8777服务/8778观察端、公开演示视频；保留源数据和原四服务。首段沿用软件GPU/GLDMA关闭/宿主解码开启；实测录屏时跳过160ms中间帧后，保留失败并正常关闭原进程，在同一AVD数据、APK及服务上比较host GPU。临时-no-audio用于动作观察，有声播放不在本段验收范围；SDK、产品代码、正常配套APK与独立原型不改。

各动作录屏和静态前后图配合逐帧参数，关键路径三轮；原始失败单列。其它100/140/240ms动作层级、完整手势/字号/主题组合以及真实手机/NAS继续，不能据本段关闭完整UI-06、#78或总验收。

最终固定eee62f21，当前App12点与保留组件6点共18点三轮完整通过，证据见[原生记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-native-reduced-motion/README.md)。观察器先识别系统全屏说明并确认、等实际resumed，再在暂停覆盖层移除后的当前控件树绑定动画元素；请求真实基线帧，不使用模拟时钟。各段失败、空字符串设置恢复补证、原始录屏与帧间隔保留；不据此修改产品或关闭完整验收。
