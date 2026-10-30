# 分目录扫描页面检查记录

[实现规则](../../LF8-ROOT-SCAN-UI.md) / [草稿PR #148](https://github.com/ShiJiJS/video_viewer/pull/148)，跟踪#138/#139。生产与测试源码430fede546fe7649bdffeb7f399c6d86b6bbb212；固定镜像d9e4dfe4230774bc918a5831a59f037748b155fc5087c4ead239ad0b88c81715。source-boundary.json逐一核对233份Flutter生产/测试文件及143份服务Python/配置文件匹配Git；服务143份同时匹配实际不可变镜像。

client-full-release-scope.log为完整822项通过；analyze-release-scope无问题。targeted-stable-1/2/3分别执行新加的3个文件、每轮23项通过。模型覆盖独立单位/未知值/旧中断状态；HTTP覆盖精确root_id、缺任一能力零POST、拒绝不重发或全扫、连接关闭后旧响应不轮询；组件覆盖真实LibraryHome入口/返回、排队、失败、旧汇总、未知/离线/部分失败、空目录/空图片、被外层覆盖的根，以及四种排布。没有把多轮合计写成新增用例数。

server-related.log为相关48项通过。server-ruff-final/server-format-final分别通过，格式检查142份文件。completed-root-baseline.log在4ceb06db旧镜像执行新增的真实扫描用例失败：全扫中已经完成A的重扫仍返回旧任务；430fede5允许A排队，新增第二张图片实际入库、B事实保持。同一源码在项目标准容器环境的server-full.log完整478项通过（506.01秒）；checks.json保存准确命令。

server-space-diagnostic.log保留本轮测试命令漏掉项目规定的--shm-size=64m导致的失败：默认临时共享空间约6GB，测试要求小于256MB，尚未进入删除逻辑就在前置断言失败。按scripts/test-server.sh规定的只读容器、64MB共享空间、独立/tmp重跑，server-space-standard.log单项通过；不修改或放宽测试。最初未跑完的错误环境全量记录留在本机.dev，不能算完整检查。

screens下13幅画面均在实际Flutter组件内以公开合成响应渲染，Mac中文字体用于可读性；不是普通APK、真实NAS数字或性能结论。settings-entry记录从现有入口进入；root-a-queued保留A40/40和下一次排队、B63/已发现180；partial-and-offline保留部分错误和离线前数字；legacy-type-warnings保留旧服务类型汇总；empty-and-image-less明确没有内容。其余为390宽浅/暗、320宽两倍字体、844宽横屏的上下部。正常动画布局使用固定测试时钟，功能断言使用减弱动态，避免无限等待活动指示器。

本机早期测试辅助代码曾缺directory_id、误用Map身份比较/二次dispose及推断过窄的嵌套Map类型；已修正为真实响应字段、值比较、单次释放和JSON线格式往返，旧诊断保留在.dev，不是产品错误证据。截取排队画面时等待现有通知消失并定位到A，使A/B同时可见；离线夹具使用实际终止状态。未通过改数字或放松断言获得通过。最初追加复跑命令还误写一个不存在的测试文件名，加载失败；随后的两轮27项和本目录明确三个文件的23项三轮通过，使用后者作为固定记录。

本轮未启动AVD、生成APK或连接NAS，现有普通第23版没有本页面。真实服务V+A+B和普通安装包的连续操作/重开/断网、新旧服务组合及NAS/手机检查仍待完成；#142缩放未实现，#138/#139不关闭。原四个本机服务身份和状态见cleanup.json；冻结原型树保持1cbf605。process-cleanup.json记录只删除35幅与固定截图逐一SHA相同的早期私有副本，共2074284字节，SDK/签名/AVD/运行数据及不同画面保留。SHA256SUMS仅固定文件，不替代操作验收。
