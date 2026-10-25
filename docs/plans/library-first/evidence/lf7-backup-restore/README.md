# LF7 完整管理恢复：固定源码证据

实现04d9834、初始化修复8193272，固定最终源码：`0c841f390d1ee43ecaacb3a3f6766f4e45803042`，基于 PR #51 的 `e1bbf5b`。Draft PR #52，Refs #32 / #24。`source.json` 固定完整服务目录逐文件SHA、Git树与隔离测试镜像；`manifest.json` 固定本目录输入，`verify.py` 复核源码/日志摘要及测试输出中的实际断言。

本阶段完成服务端协调与公开只读历史，App v2文件/系统选择器/预览映射与历史页面仍继续；`backup_v2`未发布。下一步见 [App文件流程](../../LF7-APP-ARCHIVE-PLAN.md)，实现契约见 [恢复设计](../../LF7-RESTORE-V2-DESIGN.md)。

## 固定源码结果

`server-full.log`：固定源码服务端全集396项通过，433.47秒（1条既有Starlette弃用警告原样保留）。新增21项纳入全集；下面4项是另行复跑，不叠加为400项。

- `process-http.log`：4项通过，32.01秒。三项在真实HTTP服务进程的 snapshot_written、after_replace_before_commit、restore_committed 检查点实际 SIGKILL，再以新进程启动；提交前旧库/旧代次可读、提交后结果和代次稳定；旧POST拒绝，原请求与前快照可查，源视频SHA不变，没有历史文件命令重放。已提交任务不再执行，私有恢复工作目录清除，正式历史目录保留。
- 同一日志的大文件项：实际文件40,949,448字节，网络按64KiB上传/下载并核对SHA，真实完整恢复；独立SQLite查询18,000行各2048字符，源视频SHA不变。服务进程tracemalloc峰值5,634,876字节，配置64MiB。它是服务端Python分配量，**不是总RSS、Android内存或性能结论**；当前默认文件限制仍32MiB。
- `ruff.log` 全目录检查通过；`compile.log` 编译111个服务/测试Python文件通过。Flutter与原生代码本轮未变，398项客户端及三轮原生是PR #51基线，本轮未重跑，不冒充v2 App验收。

## 覆盖与实际边界

生成的真实视频/图片树与SQLite通过鉴权HTTP建立：33张管理表全部非空，两套同名标签、阅读/播放偏好、会话/队列/最近、回收、整份恢复父子成员、永久删除清单及缺失清理都保留关联。恢复后19张不应变化的表逐字段对照、明确本机设置保留；历史图保存原任务结果，活动投影不可执行。连续两次恢复核对两个原epoch、同图成员、缺失/冲突代次不回退，并保留历次本机备份控制回执及可下载前快照。

文件核对覆盖映射/null停用、SHA/大小/文件身份、符号链接/变更、当前逻辑回收及真实父来源、已明确恢复不重新回收、实际部分永久删除后旧页ID退休。恢复只读源媒体；媒体字节未写入归档。HTTP覆盖预约下另一数据库连接拒写、仍可登录/退出和读原任务、提交前回滚、提交后清理异常不改完成结果、旧未完成任务冷启动不重放、坏文件/超限/模拟客户端中止/磁盘异常与临时文件归属、历史图SHA变化拒绝原结果。

历史默认列表排除当前仍存在的本机备份控制任务，显式原图保持完整。原任务、图包操作、整份恢复、视频文件及缺失清理等旧GET已适配；永久删除清单/页明细及其它专用旧GET尚需继续审计。通用8类历史回执和严格原epoch路由已经提供，不能把它当作App所有页面均已接线。

SIGKILL覆盖进程死亡，不代表机器断电或真实NAS故障；上传中止项使用TestClient生成器中止，网络大文件项另用真实HTTP。显式单个历史回执仍受文件协议的单记录上限，旧v1仍使用已有限制下的整份JSON兼容解析。

## 执行环境与命令

Docker `video-viewer-server:e2e`，只读挂载固定 `services/server`，独立临时数据/媒体、回环HTTP随机端口、64MiB共享内存和可写tmpfs；具体镜像ID在source.json。正式8760/NAS、SDK与发布APK未改。冻结原型 `design/reference/library-first` 及tag树均为 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca`，独立可移除。

```sh
docker run --rm --read-only --shm-size=64m --tmpfs /tmp:mode=1777 \
  -v "$PWD/services/server:/source:ro" -w /source --entrypoint pytest \
  video-viewer-server:e2e -q

docker run --rm --read-only --shm-size=64m --tmpfs /tmp:mode=1777 \
  -v "$PWD/services/server:/source:ro" -w /source --entrypoint pytest \
  video-viewer-server:e2e -q -s tests/test_management_archive_recovery.py \
  tests/test_management_archive_large_http.py
```

## 开发诊断（不计固定源码通过数）

`diagnostics/` 原样保存开发日志：初次选错缺Pillow镜像、用例文件/名称错误导致的未执行、readonly容器缺tmpfs导致Ruff缓存失败、连续恢复样本根停用造成错误的投影预期、旧POST只读返回与v2拒绝策略、TestClient取消的异常组、默认值响应键断言错误等。对照默认值时还发现GET曾开启写事务，已修成只读；当前明确恢复与旧回收标记的优先级也已修正。首次04d9834全量出现底层WAL用例失败后停止；初始化修复后的8193272轮次为修复新增测试的导入格式而提前停止，原始日志均保留，不计完整通过。f40f917全量179通过/1项旧能力清单断言失败，0c841f3更新该协议预期并确认backup_v2未开放；旧轮次不计最终全集。其余开发中6/9/39/86/26/16等检查、三处强停和约39MiB量测均只作诊断，不能叠加成最终总数。

完整LF7/原型验收尚包括App文件流程、其它命令强停组合、历史图片失败根因、暗色/横屏/手势与目标设备/NAS及原签名升级；本阶段不关闭总任务。
