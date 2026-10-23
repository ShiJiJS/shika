# LF 合成测试素材

运行 `python3 scripts/fixtures/generate-lf0-packs.py --output .dev/fixtures/lf0-packs`。仅接受新建或空目录，不覆盖已有文件；不扫描 NAS。生成物在 `.dev`，不提交 Git。标准库流式写 PNG，不依赖 Pillow，也不在内存一次构造 8K 原图。

四包共 508 张有效图片：自然排序和嵌套 4 张、4K/6K/8K 大图 3 张、坏图场景有效页 1 张、长包 500 张；另有故意损坏 JPEG、空子目录及必须保留的文本附件。`manifest.json` 记录尺寸和 SHA-256。图包发现、格式探测、坏图错误、页排序和删除保护在 LF2/LF6 接入正式测试；LF0 只建立可复现夹具。

视频样本仍使用 `apps/mobile/assets/media`，旧 0004 管理库的身份/轮次/逻辑及历史物理回收/待确认命令继续由现有服务端测试建立。冻结的 0004 SQL 与身份清单在 `services/server/tests/fixtures/`，LF1 在真实迁移后沿用其不变量，不能把空库冒充旧库验证。
