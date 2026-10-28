# 原签名 App 回退与升回：两轮实际覆盖安装

[PR #95](https://github.com/ShiJiJS/video_viewer/pull/95)，构建固定源码 **a3c7659a738619842f9923078363135299210826**。现代 App 的 lib/Android 与 cf992025 相同，仅 pubspec 改为 `0.2.0-preview.2+8`；服务沿用 b79da7b9 的正常 runtime preview.2（886b79b7…），不绑定服务源码或测试入口。独立端口8772、公开演示视频与合成三页图包、自有Android36/5556；真实手机/NAS未动。

## 可反复替换的两份包

| 用途 | 版本名 / code | 字节数 | SHA256 |
| --- | --- | ---: | --- |
| 新媒体库 | 0.2.0-preview.2 / 8 | 23308394 | 2e3d7df81c52a79a3d216cff8c8a80d2df7de6994937eafbdc219818b18a171b |
| 旧视频界面回退 | 0.1.4-rollback.2 / 8 | 21734386 | ec884743b5aa0c8c71bf534940a0c4b107580ee38e9c1e2d3f97286115cfa5ee |

两份均包名io.github.shijijs.video_viewer，沿用原Windows签名f5abd3bd…59161，普通main/release、ARM64，无integration_test插件或原型。APK留在本机tmp/releases，不提交Git。相同内部版本号可替换的依据是[AOSP版本检查](https://android.googlesource.com/platform/frameworks/base/+/ce8e50cfcea0756066a739a6390907770949b1b0/services/core/java/com/android/server/pm/PackageManagerServiceUtils.java)，本轮再用实际安装验证；不据此保证所有厂商手机。

旧UI代码取原Windows0.1.4源码f5fe32c9，仅在独立导出中覆盖偏好/凭据/ScopedJournal实现，添加旧接口适配、入口注入及连接保存management_epoch。9份覆盖各有来源与SHA，旧界面/播放器/API业务保留。不是原Windows APK的字节复刻。

旧版原偏好写入会丢新版videoOrder/defaultMigrations，旧日志会覆盖v2多范围账本；适配器仅对当前连接和代次读写，保留其它范围与未知字段，token/地址/代次变化即拒绝写。旧备份只处理v1，遇到v2备份命令保留原记录并要求回新版核对，启动不重发。7项针对适配检查，加原14份旧测试与复用的偏好/范围日志检查，共85项；现代相关4份14项，双方analyze、正常release/签名/ABI检查通过。完整672客户端/462服务是前阶段结果，本轮没有重跑。

`build/`保留冻结源码、原导出文件摘要、覆盖摘要、全部13步及原日志；SDK/依赖锁未升级。`scripts/build-app-rollback.py`可从干净已提交源导出构建，必须指定全新.dev输出目录，输出目标存在则拒绝，且不负责安装。执行前先保留现有同名产物，不能覆盖既有包；此脚本固定code8，后续提高code必须同步更新配套回退包。

## 实际安装与状态核对

同一个QEMU PID63606、六次不同App PID，顺序为：

`原预览6 → 新版8 → 旧界面8 → 新版8 → 旧界面8 → 新版8`

五次实际 `adb -s emulator-5556 install -r` 全部Success，无-d、卸载、清数据或测试入口替换。每次安装前后首次安装时间、appId、dataDir保持一致。所有冷启窗口免口令；新版四次冷启全GET，无stream/opened，旧UI保留原自动播放逻辑，不把旧界面当成新版媒体库。

数据从前阶段停止的0004公开副本复制，正常新服务迁移后加入图包根/图包专用PACK_ONLY标签；主持准备凭据已撤销。原App token留在安全存储，数据库只公开数量/摘要，原口令/token/SQLite/签名私钥未提交。媒体全部只读绑定，原副本未动。

- APK6实际从图包库进入，翻到第2页、切换纵向模式；默认设置经正常UI保存。
- 为明确覆盖“存在新版本机字段”的兼容场景，只在自有AVD的appearance.json加入公开videoOrder=sequential与另一服务迁移标记；这是**显式文件样本**，不是全由UI生成。现代8再经“沿用服务端设置”实际加入当前服务迁移标记；两条非空标记作为后续基线。
- 安装旧界面8后免口令连接，旧库2视频/LEGACY_ONLY关联可读；实际切换浅色、开启相邻准备。对应JSON准确只改这两项，顺序和两条迁移标记完全相同。
- 在旧快速整理中实际删除landscape，然后经“更多→撤销上次删除”完成撤销。两个真实operation ID、request_key及completed任务/成员保留；升回后新版任务页显示各已处理1/1、成功1，详情编号对应真实undo。
- 旧界面操作前后所有pack表完全相同，视频标签及登录摘要相同。升回新版8后图包仍第2页/纵向、独立PACK_ONLY标签仍在，旧UI设置变更保留；再完整重复8→旧8→新8。最终两套标签页、继续阅读和阅读图实际核对。
- 最终读取图包会正常产生新session/更新进度revision和时间，不宣称所有pack表与初始逐字相同；核对保留page_id/offset/completed/content_version、阅读偏好和标签关联。

`records/`包含五次安装前后真实package dump选定字段、六次冷启偏移、偏好/SQL投影、完整路径trace及实际驱动。`startup-windows.json`以冷启偏移到对应landing PNG写入时间界定只读窗口；trace只记录方法/无查询串路径/状态，不含认证头/请求体。唯一host准备登录在App窗口之外，凭据已撤销；不把整个trace说成无登录。

`screens/`22组原生PNG/XML/前台窗口，涵盖准备、两个版本、旧UI设置/视频、回收撤销、新任务结果与两轮返回。已人工查看阅读实图与旧/新设置、任务和两套标签；这不是完整产品视觉终验或多视口审查。过程中的早期7/8临时包、API早到、UI驱动误判即时操作为确认面板/短提示过期等单列`diagnostics.json`。两个样本在正式比较前恢复可用，比较基线明确为before-rollback-projection.json；不将这些驱动中断算成功验证。最终从旧菜单执行撤销，真实服务任务完成。

## 复核和清理

```bash
python3 docs/plans/library-first/evidence/lf8-app-rollback/verify.py --artifacts tmp/releases
```

只读核对148份输入、构建SHA和99项原结果、固定代码差异、五次安装连续性、窗口请求、偏好/标签/进度、真实回收撤销关系及清理，不启动服务或重放操作。省略--artifacts可只核对提交记录，不读取本机APK。原始驱动含本机私有路径，只供审计，不能直接指向真实数据运行。

结束时关闭自有AVD、停止并移除唯一实验容器；原四服务ID/运行状态相同，前阶段数据副本、视频、图包SHA不变。cleanup.json及前后服务清单记录实际清理。

切换前应先在支持的新版完成/核对管理任务。未知或正在进行的v2任务不支持由旧版接管，跨版本切换也不作该承诺。本轮只补UP-02的本机App回退组合；目标手机/NAS、完整旧客户端配新服务、500页高分辨率及其它终验继续，#78/#89、#24/#33均保持开放。原型1cbf605独立未改，未正式发布或部署NAS。
