总任务：#24

## 目标

原型每包一张卡片，但正式服务目前只识别视频。需要把 NAS 目录转换成稳定、可分页、有尺寸元数据的图包与页清单。

本任务属于 LF-2026-10-23 媒体库/图包改造；已完成服务端实现与隔离验证，等待依赖 PR 合并。原生媒体库/阅读器及真实 NAS/手机验收继续由 LF4/LF5/LF8 完成。

## 依赖

LF1 (#26)

## 实施范围

- 根直属文件夹为包，包内递归；按相对路径各段自然排序，数字 2 在 10 前；包/页稳定 ID，页清单含内容版本。
- 先支持 JPEG/PNG/WebP 静态图片；无压缩包直读、单张标签或 AI 识别。坏图/空包/不支持格式明确反馈。
- 按目录身份/唯一内容证据识别外部变更，歧义保留旧缺失，不按名字继承标签；完整成功扫描才判缺失，停用/离线不清理。
- 实现图包查询、页清单、封面/缩略图/原图鉴权读取；范围校验、符号链接与替换保护、取消和受限并发。
- 按类型提供准备/扫描状态，新图包首扫不锁已有视频；缩略图失败不阻塞整包；避免反复全量解码/哈希。

## 主要代码

- `services/server/video_viewer/scanner.py`
- `services/server/video_viewer/paths.py`
- `services/server/video_viewer/packs.py（新增）`
- `services/server/video_viewer/pack_scanner.py（新增）`
- `services/server/video_viewer/images.py（新增）`

## 完成标准

- [x] 自然排序、嵌套、增删页、唯一改名、重复副本、离线与坏图夹具通过。
- [x] 分页真实总数，未授权/路径越界拒绝，原图/缩略图版本可核对。
- [x] 500页和大图样本可逐页访问，后台扫描有进度；记录资源基线，不宣称未经实测性能。

实现提交：`9aff732`；[PR #36](https://github.com/ShiJiJS/shika/pull/36)；[交付说明与证据](../LF2.md)。标准 LF0 四包夹具通过真实 HTTP 核对全部 508 张有效原图哈希及缩略图，源文件不变；现有视频的 Android I1 连接/重开回归通过。原型仍独立保存于 `design/reference/`，没有改动。

验收 ID：LIB-02/03、PKG-01–03、SET-04

本地方案：`docs/plans/library-first/PLAN.md`；验收表：`docs/plans/library-first/ACCEPTANCE.md`。方案与独立原型已随 LF0 纳入版本控制，提交与证据见 `docs/plans/library-first/LF0.md`。当前原型：`design/reference/library-first/`，设置差异：`SETTINGS-AUDIT.md`。禁止只接 Demo 就关闭真实服务任务；不改真实 NAS 文件来做故障测试。
