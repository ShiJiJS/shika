# 面板与确认窗口：冻结05b322e6

结果及边界集中见[本段说明](../../LF8-OVERLAY-MOTION.md)，包/服务/SHA见[安装说明](../../../../library-first-preview.md)。正常release与profile证据分开。

- before-test.dart.txt / before-tests.log：原实现8组合中7失败，包含面板默认200ms返回、打开后偏好切换无效、确认窗口150ms与减少动画不符。after-tests.log的8组合通过，client-tests.log完整695通过；analyze-final.log无问题。最早analyze两项风格提示已处理，无产品故障隐藏。
- native-1/profile-result.json：三轮36次；真实App阅读/视频面板24，生产确认组件12。真实Android比例/PlatformDispatcher/MediaQuery、实际controller和显示代理均记录；普通有中间值，减少动画首目标值到位。18录屏由run.py完整解码，audit.json核对精确集合、原生焦点与恢复，不重复跑已通过的500页压力。
- normal/：普通代码11实际新10→新11→旧11→新11。三次身份/首次安装时间/21表/设置/登录/偏好相同；普通包面板与真实偏好切换9状态。普通状态图不作为profile帧计时替代。
- 两套cleanup分别核对自有PID/容器与进入时配置；原四服务健康、donor原文件保留，数据目录与旧包保留。无真实收藏或NAS部署。原始请求日志仅路径/状态；本段没有标签/文件/偏好/进度写入命令。
- raw日志只去掉本地临时VM服务URL（见log-provenance），未过滤失败。emulator.log不公开，避免携带ADB公钥身份；具体启动命令/SDK/进程在runtime/source记录中。脚本是本段自有夹具来源，依赖原私有目录，不是对真实数据的生产操作说明。目录不含数据库、密钥或APK。

真实手机/NAS、有声、真实阅读保存失败的原生确认流程、通知/按压/选择和完整UI-06均未据此关闭；#78/#89/#100仍未定位。窗口/请求/帧时间只证明所列组合，不作物理呈现或持续稳定性结论。
