# 分目录扫描：服务检查记录

跟踪#138 / [草稿PR #147](https://github.com/ShiJiJS/video_viewer/pull/147)，[数据与队列规则](../../LF8-ROOT-SCAN-DATA.md)。最终生产源码4ceb06db，固定Linux测试镜像af9b5b9f461e879066f42cb17f560eb2cce63064970596147a83471e396f2665。

最终overlap-full.log：**477项通过**；overlap-ruff/format通过。overlap-related.log为最终13个新增用例所在的目录/类型/身份相关47项，通过。143个Python/配置源码文件与Git提交及镜像逐一SHA相同，见overlap-source-boundary/image-source；不是仅用镜像标签相同推定源码相同。客户端生产文件未改，不重跑Flutter或生成APK。

公开、可丢弃的V+A+B组合通过TestClient调用真实路由/Scanner/SQLite：B第2张解码受控阻塞时，A已完成1包/2张且有完成时间，B为1包已发现/0包已完成、2张已发现/1张已核对；视频完成不会被图包覆盖。另有只扫A保留B全部包/页行及上次进度、两根串行/去重/全扫排队、坏图（含缓存坏图）、变化图片待稳定、离线/停用、重叠根/类型边界、恢复和改目录后索引失效，以及指定视频范围不继承其它根缺失身份。

中断用例先在第2张抛InterruptedError，重开后保留第1张数字；另在私有夹具数据库种入运行/排队事实再重开，验证启动恢复持久化并且不执行排队内容。关闭时取消队列且保留B已完成记录；受控调用覆盖stop信号后才取出任务的竞态。**不是NAS断电或真实操作系统杀进程的压力测试**。所有SQLite写入只在隔离/tmp夹具，未访问NAS或真实收藏。

保留中间结果，不能合并成最终源码的全量复跑：

| 记录 | 结果与边界 |
| --- | --- |
| baseline-final.log | 原1757261a业务源码执行最初两项需求用例，2失败；A未独立保存完成时间、无指定scope |
| targeted.log | 首版9项中8通过，1项错用了不支持图包的v1备份测试辅助；改用真实v2接口，没有放松备份规则 |
| related.log | 早期目录/身份/图包61项通过，未包含后续关闭/范围增强 |
| full.log / media-types-diagnostic.log | 完整473通过/1失败；旧测试能力列表没有新增两项，保持严格列表并补上能力预期 |
| targeted-final.log / full-final.log | 02008c5e的22项及完整475项通过，source-boundary/image-source固定该边界；source-boundary是在提交前记录，因此base_commit为1757261a，其143文件另核对匹配02008c5e |
| overlap-baseline.log | 02008镜像上初加的2项重叠目录用例均失败：添加外层后旧数字仍有效、按旧root_id漏判缺失；基线用例草稿与最终测试文件边界分开 |
| overlap-related/full/ruff/format | 最终4ceb06db：47项及完整477项/代码检查通过；相关范围签名和当前路径归属修正后，不影响隔离的视频子树 |

build-final/build-overlap分别记录两个镜像构建。checks.json列最终事实；cleanup.json确认临时测试容器均已移除、原4本机容器ID和healthy保持，本段没有启动AVD。两个测试镜像保留用于后续客户端接线。原型树1cbf605保持。

#139页面、#142缩放仍未实现；新App/旧服务与旧App/此服务的完整原生组合、NAS/手机联调及发布仍待完成，#138不关闭。没有把CPU测试时长当作NAS速度。SHA256SUMS固定本目录；核对摘要只能说明文件保持，不能替代上述执行记录。
