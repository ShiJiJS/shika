# 第33版：图包文件夹直接后台删除

App：`0.2.0-preview.27` / code33。服务：`0.2.0-preview.9`。对应[#186](https://github.com/ShiJiJS/video_viewer/issues/186)，取代第32版针对图片核对等待的交互。

在图包回收站选择后点击“永久删除”，App保存请求并异步提交，服务器删除对应图包文件夹和其中全部内容，包括附件与子目录。无需准备或阅读图片清单，不逐张散列，不等待实际删除完成。提交后可继续浏览，在设置任务页查看结果和重试未完成项。普通“移入回收站”仍保留原文件。

[实现及范围](plans/library-first/DIRECTORY-DELETION.md)。旧版已排队的只读图片准备不再继续重启散列；历史记录保留，既有旧执行协议兼容。此次没有替用户删除任何真实图包，私人回收站记录继续保留。

正常APK：`video-viewer-0.2.0-preview.27-arm64.apk`；原签名同号旧视频界面回退APK：`video-viewer-0.1.4-rollback.27-arm64.apk`。服务镜像包：`video-viewer-server-0.2.0-preview.9-linux-arm64.tar.gz`。安装仍为覆盖安装，不卸载、不清数据；本地`tmp/releases/`和NAS原`packages/`保存最新文件与校验说明。

NAS升级前完整停机备份data/config/secrets/Compose并保留旧镜像。只将图包挂载`/packs-cos`改为可写，保持其余配置，部署后仅做健康与管理数据只读检查；未用真实收藏执行删除测试。原型仍独立隔离。检查结果与部署摘要在交付完成后补记；没有把既往检查或实体手机试用算作本次通过。
