# NAS健康监测超时

跟踪：[#154](https://github.com/ShiJiJS/video_viewer/issues/154)，关联#135/#33。

[草稿PR #156](https://github.com/ShiJiJS/video_viewer/pull/156)，基于#155。

2026-11-01追加：实现6a119b1c/runtime preview.4，491项服务检查通过，新NAS镜像已在完整备份后启动。探测改为固定回环HTTP、少量CPython导入；内部2秒总期限保持，进程整体预算10秒。真实Docker已验证200健康→503不健康→200恢复，3秒慢响应仍失败。数据核对、繁忙扫描连续记录与未定位的宿主压力边界见[本次修复与部署](../LF8-NAS-HEALTHCHECK.md)。客户端仍为code26，不需要重装App；本票保持开放等待审阅及后续使用。

以下是修复前的原始发现，保持其时间和版本范围（430fede5/runtime preview.3）：

第26版分发前检查记录Docker unhealthy/连续53次3秒超时，重启0/OOM=false，日志无异常栈；直接健康接口200约0.164秒。三次独立容器内Python探测均200，urllib导入分别1.30/2.05/1.34秒，HTTP约0.52/0.46/0.64秒。含SSH/Docker执行总耗时3.29/4.47/3.29秒，不等同HTTP本身耗时。后续及复制26前后曾恢复healthy，保留此前失败。

当前Docker整体预算3秒、内部HTTP预算2秒。新进程/导入开销可能挤占整体预算，仍须区分宿主/容器资源与IO调度影响、业务响应阻塞；不能仅根据后来的成功宣称根因已解决。具体去敏时点见[本轮记录](https://github.com/ShiJiJS/video_viewer/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-pack-restore-code26/README.md)。

下一步优先读取现有服务和运行任务状态，补新进程/导入/HTTP与资源压力样本；根据证据调整监测方式或外层预算，保留真实无响应检测，不用修改业务请求超时掩盖失败。若需重建服务，保留备份、原目录/身份/凭据/标签/阅读数据，并在繁忙扫描期间连续核对健康与实际接口。

本轮只分发APK：初次脚本在任何写入前因监测失败停止；后续明确记录直接HTTP结果和Docker状态，原容器/启动时间/重启次数保持。没有新登录、数据库写入或真实媒体删除试验。原完整NAS/Mac成对备份、旧镜像及旧包保留，本票保持开放。
