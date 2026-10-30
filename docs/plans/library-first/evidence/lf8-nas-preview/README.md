# NAS体验部署与过程文件清理

详见[安装/部署/回退说明](../../../../nas-preview-2026-10-30.md)，跟踪[#135](https://github.com/ShiJiJS/video_viewer/issues/135)。

- [迁移核对](migration-result.json)：0004→0014，启动前15张旧业务表原有列全部相同，先创建停用pack根。
- [部署状态](deployment-summary.json)：14:51健康、视频扫描598未变/0失败、687图包首次扫描进行中；原9组稳定表再次相同，临时探测凭据已撤销。
- [图包读取](pack-read-smoke.json)：首包40页、封面200和原图Range206/1024字节；不是手机解码或完整性能测量。
- [镜像来源](image-identity.json)及[73运行文件](runtime73-check.json)：实际层一致，明确本机manifest/image ID与NAS旧Docker config image ID区别。
- [累计清理结果](cleanup-summary.json)（[首批](cleanup-result.json)、[Flutter编译缓存](cleanup-flutter-cache-result.json)）：逐路径删除47处可再生成文件，保留开发环境、发布文件、固定记录和绑定数据。实际空闲空间增加约90.43GiB。

全部源文件/旧安装包/固定历史manifest保持。首次扫描未完成，不把已读首包算成全687包通过。真实手机/NAS完整性能、有声/云文件、三个偶发问题及原45项终验保持开放。

停机快照、真实配置、口令、数据库、临时登录及私人连接资料不纳入Git。NAS仍在承担首次扫描；不能为本机清理而停止该服务。
