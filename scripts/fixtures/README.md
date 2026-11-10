# 图包扫描测试素材

运行 `python3 scripts/fixtures/generate-lf0-packs.py --output .dev/fixtures/lf0-packs`。仅接受新建或空目录，不覆盖已有文件；不扫描 NAS。生成物在 `.dev`，不提交 Git。标准库流式写 PNG，不依赖 Pillow，也不在内存一次构造 8K 原图。

四包共 508 张有效图片：自然排序和嵌套 4 张、4K/6K/8K 大图 3 张、坏图场景有效页 1 张、长包 500 张；另有故意损坏 JPEG、空子目录及必须保留的文本附件。`manifest.json` 记录尺寸和 SHA-256。用于检查图包发现、格式探测、坏图错误、页排序和删除保护。

视频样本仍使用 `apps/mobile/assets/media`，旧 0004 管理库的身份/轮次/逻辑及历史物理回收/待确认命令继续由现有服务端测试建立。冻结的 0004 SQL 与身份清单在 `services/server/tests/fixtures/`，迁移测试检查原有身份和关联，不能用空库代替。

`validate-lf2-catalog.py`：只在自己的临时目录生成上述四包，启动隔离服务并通过公开 HTTP 验证全部原图哈希/缩略图、500 页排序、坏图错误、冷/热扫描与源文件不变。它不接受外部媒体路径。先构建测试镜像，再执行：

```sh
docker build --target test -t shika-server:catalog-fixture services/server
docker run --rm --read-only --network none --shm-size=64m --tmpfs /tmp:mode=1777 \
  -v "$PWD/scripts/fixtures:/fixture-tools:ro" \
  shika-server:catalog-fixture python /fixture-tools/validate-lf2-catalog.py
```

测试镜像包含冻结的服务源码，不挂载正在编辑的源码目录。可用 `VV_EVIDENCE_REVISION` / `VV_EVIDENCE_IMAGE` 环境变量标记提交和镜像 ID；结果输出 JSON，素材和管理数据随容器结束清除。样本测量不是实际手机/NAS 性能验收。
