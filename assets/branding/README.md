[项目首页](../../README.md) · [文档导航](../../docs/README.md)

# 拾刻 · shika 图标

- `shika-original.png` 保留用户在2026-11-04确认的深绿底鹿娘方形原图，尺寸1254×1254。暖黄色上衣、紫色领结与视频/图片/漫画媒体板构成原图内容。
- `shika-icon.png` 是2026-11-11基于原图调整的圆角透明背景版本，供 README 与应用图标导出使用。边缘处理参考知予图标：四周透明留白、圆角方形背景，保留拾刻的图案与配色。原图与本次边缘调整均使用内置 imagegen。
- Android 各密度资源由 `scripts/export-brand-icons.sh` 从 `shika-icon.png` 导出，位于 `apps/mobile/android/app/src/main/res/mipmap-*/ic_launcher.png`。

在仓库根目录执行（macOS，自带 `sips`）：

```bash
bash scripts/export-brand-icons.sh
```

原图和圆角图均保存在仓库中，README 和 App 不引用生成会话或临时目录。Android 显示名为「拾刻 · shika」；applicationId、既有存储键和旧备份格式标识继续保持兼容，以支持覆盖安装和读取原数据。
