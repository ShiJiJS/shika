# 拾刻迁移到飞牛 NAS

2026-11-06，服务迁移到 FN EVO2（Intel N150，linux/amd64）。部署目录采用 `docker/shika`，Compose 项目为 `shika`，容器为 `shika-server`，镜像为 `shika-server:0.2.0-preview.10`。App 第35版仍可使用，手机只需修改服务器地址，端口8760、原口令不变。真实地址和媒体路径在私有 infos 的 `shika.connection` 中。

## 数据与命名

新部署使用迁移过来的管理数据、配置与口令副本。原 `docker/video-viewer` 目录保留，作为迁移前副本；没有同时启动旧部署。复制前后43,676个文件、2,240,931,127字节一致。

启动前通过 SQLite 只读检查核对复制前后的标签、关联、阅读进度、偏好、固定阅读范围、最近记录和视频/图包回收记录。数据库完整性通过，没有待执行的文件操作；另外通过SQLite backup API保存一致性备份到新目录 `backups/pre-fnos-2026-11-06.sqlite3`。启动后再次比较上述记录摘要，保持一致。备份只包含管理数据，不能恢复已被永久删除的媒体文件。

NAS 外部部署名称采用 shika；容器内的 `/media`、`/packs-cos`、目录ID和数据库兼容标识保留。视频与图包的实际目录经fnos-cli检查后绑定，两个授权媒体挂载均可写，普通回收仍只记数据库状态。服务使用UID/GID 1000:1000、只读根文件系统、全部capabilities移除、no-new-privileges、64MiB临时目录，以及768MiB内存、1.5核、128进程限制；只绑定NAS局域网地址的8760端口。

迁移改变了文件身份信息，服务会在后台重新扫描并核对已有文件。原媒体库仍标记就绪；尚未重新核对的图包可能暂时返回 `pack_changed`。不要为了跳过扫描而伪造原文件签名。视频媒体及缩略图的Range读取已返回206，图包原图/封面的最终读取结果以扫描后的核验为准。

## fnos-cli 维护

本次使用现有 `home-fnos` OAuth授权执行文件复制、上传、镜像导入、Compose创建与启动、容器检查；没有使用SSH，也不需要额外登录飞牛管理页。CLI未升级。镜像导入超出CLI等待时间后，NAS仍在后台完成导入，随后通过原镜像引用查询核实，不重复发送导入或创建请求。

镜像导入：

```bash
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.imageLoad --json '{"filePath":"/vol1/1000/docker/shika/image-archives/shika-server-0.2.0-preview.10-linux-amd64.tar.gz"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker image inspect shika-server:0.2.0-preview.10
```

新建项目时先上传实际的compose.yaml，再创建项目、构建启动；不要重复创建已有项目：

```bash
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeCreate --json '{"auto_build":false,"file":"compose.yaml","folder":"/vol1/1000/docker/shika","project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker request appcgi.dockermgr.composeBuild --json '{"project_name":"shika"}' --yes
fnos-cli --profile home-fnos --allow-insecure-http docker container inspect shika-server
```

端点参数根据该NAS实际Docker前端确认。空列表仅返回成功信封时，不据此断言CLI没有管理能力。命令超时后先检查镜像/容器实际状态，避免重复操作。使用其他profile时先验证其目标和授权；凭据由CLI受控存储，不能写入Compose或仓库。

可复用模板在 [deploy/fnos](../deploy/fnos/compose.yaml)，示例环境文件需要改成自己的真实路径。迁移时沿用原mounts.json，不覆盖已有目录ID。只读检查命令 `python3 scripts/nas-status.py` 通过infos选择fnos-cli；旧SSH配置仍可兼容，当前飞牛配置不回退连接旧NAS。

## 构建与检查

服务源码：`9ab895b817353b821bf852d1d0208e47c64b9f88`，包含此前已验证的shika改名，未修改业务逻辑或数据库迁移。新镜像为真正的amd64构建，未将旧ARM镜像改标签使用。

镜像配置摘要：`sha256:7f55c59a70dd18f1b248ffffb89b5dd3292d743a67a83b0eae3154b4a0947419`。
镜像归档SHA256：`c7b920abfead38ae4d97a625b44e1fb84978588c6fd363cfdfbff742aeb3edf1`。

本机x86容器验证了非root启动、健康检查、原API/schema0014及目录删除能力。NAS容器健康、原口令登录、原server_id、两个根目录可用和安全/挂载配置已核实；原型不参与部署，没有对真实媒体执行删除测试。未重新运行未修改的整个客户端/服务端测试集，也未做实体手机验证。临时检查容器及错误日志在核对后移除，正式备份和迁移前副本保留。
