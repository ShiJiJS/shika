# 设计参考：媒体库与图包

**REFERENCE ONLY / LF-2026-10-23 / 可移除，不随 App 发布。**

用户已确认的产品结构、比例与交互基线，从本机完整原型隔离而来。主页有明确设计参考标记，App 预览画面保持原有排布。移除约定见 [上层说明](../README.md)。

## 素材与依赖

- 24 张 SVG 为本仓库生成的抽象植物示意图；标题、标签、横竖尺寸沿用验收场景，作者与目录改成示例数据。未复制私人图片、NAS 路径或访问凭据。
- 预览服务通过 `/_shared/` 只读提供仓库既有公开演示视频/字体，兼容 Windows 无符号链接检出，来源与许可证见 `apps/mobile/assets/SOURCES.md` 和 `fonts/OFL.txt`。未再复制字体文件。
- `runtime/` 和 `source/reader-template.html` 是原型自身依赖的隔离副本；不再跨目录引用旧探索。`vendor/` 只用于此原型。
- 连接、扫描、删除和恢复为浏览器本机模型，不发起 NAS 写请求。HTML 的备份不是正式 App 管理备份。

## 运行、检查与重新生成

在仓库根目录运行 `python3 design/reference/serve.py`。打开 http://127.0.0.1:8767/library-first/ ，实际交互页是 `app.html`。可用 `?state=settings/packs/reader/pack-quick/roots/trash/backup`，详见设置对照和验收表。

页面生成使用 `python3 design/reference/library-first/build_app.py`（Python 3.10+）。验证脚本只依赖此原型：

```sh
cd design/reference/library-first
npm install
npx playwright install chromium
npm test
npm run capture
```

也可设置 `VIDEO_VIEWER_PLAYWRIGHT` 为已有 Playwright 模块绝对路径，`VIDEO_VIEWER_BROWSER` 为 Chrome 路径，`REFERENCE_URL` 覆盖 app.html 地址。本机复用已有运行时，不修改项目正式依赖。

`baseline-sha256.json` 锁定隔离后的源码与合成素材；原素材版哈希保留在 `docs/plans/library-first/baseline.json` 作为历史映射，不上传私人原图截图。`shots/` 为使用合成素材重新生成的参考截图。原型修改需同时说明验收影响并更新基线，不能为贴合实现而静默改稿。
