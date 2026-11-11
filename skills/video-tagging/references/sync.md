# 软件同步与迁移

仅用户要求同步或排查软件关联时读取。使用软件 API 或正式导入接口，先检查实际 OpenAPI/代码/版本，不依赖 UI 打开视频。

## 匹配与备份

1. 使用配套 CLI 的当前用户配置或用户指定的私有配置，在程序内认证。禁止请求 stream、thumbnail、playback 或截图包含媒体的页面；接口响应只提取元数据和 tag_ids。
2. 分页读完可用视频、标签、库状态。以稳定编号、已验证旧→新路径、相对路径、大小等建立唯一映射；文件名/大小单独不足以确定匹配。任何一对多/多对一、缺失、仍在扫描的项隔离为未匹配，不继续该项导入。
3. 路径迁移/挂载改变时先确认用户已授权改挂载；保留数据库、服务器 ID、认证和历史。扫描完成后刷新映射，视频 UUID 可能改变。记录旧 UUID→新 UUID，不能靠删除库重建解决。
4. 下载完整逻辑管理备份并校验散列，保存当前标准文件、导入清单和关联快照。无可靠备份或不能唯一匹配时先保留计划，不修改服务器。

## 目录迁移后的唯一匹配

用已验证的旧→新移动清单或原始稳定编号索引生成 `targets.json`；这里填写**新路径**，mapping_ref 指向实际依据。路径属于 root_id 指定的服务根，统一斜杠分隔，区分大小写，不含电脑挂载前缀。
```
[{"video_id":"V000001","root_id":"main","relative_path":"真人/视频.mp4","size":123,
  "mapping_ref":"移动清单.json#/V000001","previous_server_id":"旧UUID",
  "managed_previous":["上次由本流程导入的标签"]}]
```

适配器从完成扫描的软件分页读取**全部**库存，生成 `inventory.json`：
```
{"server_instance":"实际库实例ID","root_paths":{"main":"软件内实际挂载根"},
 "snapshot_id":"本次完整快照标识","scan_complete":true,"inventory_complete":true,
 "records":[{"server_id":"当前视频UUID","root_id":"main","relative_path":"真人/视频.mp4",
             "size":123,"status":"available","tags":["已有标签"]}]}
```
未扫完或分页不完整不得手填 true。snapshot_id 对应保存的完整库存与库修订号；软件无修订号时以保存快照的散列标识。路径/大小只在有真实稳定编号映射来源时用于连接原台账与新索引，不能用同名文件猜出 targets。需要内容散列消歧时，targets 与 inventory 两侧均填 sha256；缺另一侧散列视为未验证。

```
python "$skill_dir/scripts/catalog.py" match --targets targets.json --inventory inventory.json --protected protected.json --output state.json
python "$skill_dir/scripts/catalog.py" plan --standard standard.json --state state.json --protected protected.json --output sync-plan.json
```

match 要求根目录＋相对路径唯一、大小一致、当前状态 available；同路径多个 UUID、同名异目录、缺失或大小不符进入 blocked，plan 拒绝带 blocked 的批次。需要先处理可匹配子集时，显式生成新子集输入并单列未处理项，不把遗漏当作完成。旧 UUID 仅留在 previous_server_id 中审计。

`managed_previous` 必须来自上次成功回执；缺记录只增加标签，人工已确认/接管的同名标签从自有集合排除。迁移后必须验证旧关联归属确实对应这一稳定编号，不能把另一个视频的旧标签带过来。

## 差量执行与竞态检查

- add = desired − current；remove = (managed_previous − desired) ∩ current。保留手工/其他来源标签，重读状态后再次计划应为空差异。
- plan 还要求标准文件与匹配文件引用同一原始保护快照，且标准标签具有对应字段依据；plan 校验 observed 与期望路径、大小及当前 UUID 一致，并携带 server_instance、root_paths、snapshot_id。实例身份来自 `/api/v1/info` 的 server_id，并额外记录 management_epoch。应用前重新读取实例、管理数据代次、挂载、扫描状态及每个目标视频元数据/标签；与计划快照不一致则重新 match/plan，不应用旧计划。这个实时检查由实际软件适配器执行；离线计划器不能发现之后的服务器变化。
- 原始文件 verify、管理备份校验及以上匹配全部通过，才执行已授权差量写入。随包计划器不联网、不写软件；按实际 API 编写/复用该应用适配器，保存请求、成功回执和最新自有标签集合。

## 拾刻接口（以运行实例实际契约为准）

标签接口：GET `/api/v1/videos`、`/api/v1/tags`、`/api/v1/library-state`；POST `/api/v1/tags`；PATCH `/api/v1/video-tags`，载荷为 request_id、video_ids、tag_ids、mode(add/remove)。当前代码每批最多 1000 个视频和 256 个标签，执行前核对实例契约。避免 replace，以免覆盖其他标签。

完整管理备份优先使用 POST `/api/v1/management-backups`，通过任务接口轮询，完成后从 `/api/v1/management-backups/{id}/download` 下载。CLI 的 `backup` 命令使用旧 `/api/v1/backups`，只包含视频管理信息，不能当作视频和图包的完整备份。按实际能力选择并说明覆盖范围；本批要求完整备份时使用 v2 API。

创建标签先按精确名称查重；网络超时结果不明时先读回，必要时用原 request_id 重试，最多两次。写入中断保留回执，续作重读当前状态重算差异。不要从一份部分分页结果判断标签“无引用”。

旧索引 UUID 的关联只在存在可靠迁移映射且能证明是本流程写入时纠正；保留旧视频记录与播放历史。删除空标签定义不是默认步骤，需要确认全库（含 missing/trash）无关联、无播放轮次等引用且属于本流程生成，再按已授权清理范围处理。

## 完成条件

逐视频读回标准标签关联；额外标签必须是保留的非本流程关联。逐视频比较“稳定编号→新路径→当前 UUID→标准标签集合”，仅总数相同可能仍错绑。比较唯一视频数、标准标签数、关联数、缺失数、重复数；保留扫描/匹配失败清单。核对原始记录散列、视频记录及播放/回收站历史未受影响，生成完成回执和同步后备份。仅 API 返回成功不能称同步完成。

完成后同时更新当前标准 JSON/MD、软件导入清单及 NAS 上用户指定的标准版副本；核对各处版本/散列一致。原版产出单独保留。历史归并脚本、旧导入清单标为历史，不能让后台旧任务重新写回已撤销的推断标签。检查后台任务是否仍运行，未授权不删除历史文件。

## 配套 CLI

先完成包内安装检查，再通过 `python "$skill_dir/scripts/shika.py"` 调用 CLI。首次连接执行 `login --base-url <拾刻服务地址>`，口令通过交互或用户提供的环境变量读取；后续使用已有用户配置。`--json` 输出仍受本技能的标签文本隐私选择约束，严格模式把输出写到私人工作区后由本地程序处理。

可用命令包括 `info`、`videos`、`tags`、`find`、`show`、`tag add`、`tag remove`。列表命令有分页，完整库存需继续读取全部页。`tag add/remove` 支持用 `@标签ID` 指定已有标签，减少名称误配；创建和关联使用不同且保留的 request_id。CLI 是独立工具，本包的 `catalog.py` 仍只生成计划，执行 Skill 的助手按已授权计划调用 API 或 CLI 完成写入和核对。

视频标签使用 `/api/v1/tags` 和 `/api/v1/video-tags`，图包标签有独立接口，本流程不跨类型写入。标准文件的分组与依据留在私人文件中；拾刻当前展示的是普通视频标签，不把模型分数、待核原因或原答塞进标签名称。
