# 第23版正常Android包：原生操作记录

2026-10-30，[范围和限制](../../LF8-PREVIEW17-NATIVE.md)。生产源码dcc1d22f，正常入口lib/main.dart，原Windows签名；APK摘要见cover-install.json / cover-cycle-checks.json。这里没有重新跑源码测试或重新构建。

API36 ARM64模拟器，1080×2400、密度420、手势导航，软件GPU、音频关闭。仅使用公开花卉素材：3图包×4页、1视频；服务127.0.0.1:8777是自有可丢弃夹具。NAS未改。原始包状态明确为0.1.4/code5，不能写成code22→23。

- navigation-checks：15个管理页序列、30次返回；第2轮仅管理页→设置这5次使用左边缘手势，其余系统返回键。所有业务XML/窗口记录保留；PNG只保留有代表性的最终状态。
- reading-checks：新包纵向、既存横向第2页/.37、阅读设置/默认设置/取消及标签文案。默认选中语义在父View，最初检查子按钮失败后修正观察；没有为检查通过改设置。
- cold-start-checks：视频实际解码、横屏全屏返回预览再返回来源；3次force-stop后启动均为不同PID，回媒体库、保留登录。不代表带声音或真机检查。
- trash-undo-checks：C的实际逻辑移除→撤销→恢复。只改变C generation+2、两条成功任务/操作/步骤、一条restored回收记录，并新增精确last_pack_delete_operation指针；其它原有设置和token摘要保持。初版审计漏列generation和指针变化而失败，修正只读审计，没有重复文件操作。原始trash-copy-runner.log保留失败，verify-trash-undo.py核对实际记录。
- cover-cycle-checks：实际install -r回退版23→新版23、安装后base.apk摘要核对、应用身份和业务快照保持。旧UI回退版在新服务上保留“浏览”兼容行为；不代表新App已在真实旧服务上验证。appearance.json本来不存在，以缺省状态保持；covers-runner.log在安装前因假设文件存在而失败，v2记录有效过程。

*-all-catalog.json：在所属容器内BEGIN短快照、mode=ro，35张业务表；access_tokens/settings只存摘要，settings另按key存值摘要。公开夹具快照不是NAS数据库。HTTP清单/server.log在覆盖回退前截取，**不覆盖随后覆盖安装阶段**；覆盖阶段结论来自安装包/界面/数据库对照。

保留29张原始PNG及biz0003–0154的XML/窗口记录，省略登录/密码画面；ui-events密码值已在采集时写为占位符。未提交配置、token、口令、SQLite/WAL、AVD内部文件或完整安装包。media-before/after中13文件摘要相同。cleanup.json记录仅自有模拟器/容器关闭，4个原有本机容器仍为原ID且healthy，AVD未清数据。

`python3 verify.py`仅对固定记录做离线一致性核对；不等于再执行Android交互。SHA256SUMS固定本目录文件，校验脚本的输出不得替代原始记录中的范围和限制。
