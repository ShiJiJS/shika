# 正常入口预览包、原签名覆盖升级与旧服务兼容

固定源码 **cf9920257f7bc88af534ea6fb3177cef69c0a161**，前阶段 **38dc07dfe964517175418578310f231c4b92809c**。本目录只保留可复核记录；安装包和服务镜像位于本机 `tmp/releases/`，不提交二进制、签名私钥或私人媒体。用户入口见[预览版说明](../../../../library-first-preview.md)。

## 构建与检查

27 个旧 Python 文件仅格式化；全部受跟踪服务 Python 文件前后 AST 相同，原始哈希／AST 摘要见 `ast-equivalence.json`。`format-before.log` 为旧失败，`format-applied.log` 和 `format-final.log` 为修正记录。格式检查现在为必须成功的检查，不能再将失败记为完整通过。

复用 `scripts/check-reference-isolation.py`，只在完整跟踪源码的导出副本内移除 72 个参考文件，保留 15792 个其余文件。原仓库 `design/reference/library-first` 树 **1cbf605af8f03fa067a4ce8e914bb809e3a487ca** 未改。`reference-free/result.json` 的十步全部成功：版本、离线锁文件依赖、analyze、完整客户端、debug/release 构建、服务测试镜像、Ruff、格式、完整服务测试。客户端 **672** 项、服务端 **447** 项（一个既有 Starlette 弃用警告）通过。

`reference-free/export-files.json` 及原参考哈希记录导出输入，`checks/` 保留每步完整日志；原型确实不在导出副本、所有保留源码前后字节未改。原参考哈希还保护了3个忽略的本机原型校验报告，所以其75项与导出移除的72个跟踪文件分别统计。release APK 不含 integration_test DEX 插件，Flutter 引擎为 arm64；debug APK 含开发用插件路径，未作为预览交付。某些依赖的其它 ABI 原生库不等于其它 ABI 的 Flutter 引擎。

`preview-apk.json`、签名／badging／manifest 与 `runtime-image.json`／`runtime-archive.json` 固定产物身份。配套镜像使用 Dockerfile **runtime** 目标和正常生产入口，不使用测试镜像部署，不挂载服务源码；`upgrade/runtime-ready.json` 和两个服务的筛选运行元数据记录实际镜像、端口与挂载。旧服务镜像直接取原 8760 的不可变镜像 ID，独立端口运行，没有修改 `/info` 返回值来模拟旧服务。

## 真实覆盖安装步骤

全新、独立 AVD `video_viewer_upgrade_36`，端口 5556，与原开发 AVD 分离。独立新服务在 8771，旧服务在 8772；不改正式 8760 或 NAS。

1. 安装原 Windows `0.1.4` APK（versionCode 5），正常 UI 登录 8771，读到两个演示视频、`UPGRADE_KEEP` 视频标签。设置深色开、相邻准备关。
2. 强停旧 App，记录稳定的数据库投影；执行 **install -r** 安装正常预览 APK（versionCode 6），没有卸载或清数据。
3. 正常主入口启动，新 PID 与旧 PID 不同。`old/new-package.txt` 显示首次安装时间、数据目录相同；`upgrade-before-sql.json` 与 `upgrade-after-startup-sql.json` 的七表选定投影和 access_tokens 整表摘要相同。不是整个 SQLite 文件字节相同或所有表都已核验的声明。
4. `upgrade-startup-requests.json` 中 26 次请求全为 GET，没有 login、stream 或 opened；进入媒体库 2 视频／1 图包，没有自动播放。
5. 实际设置语义开关和地址保留，连接表单口令为空；视频标签 `UPGRADE_KEEP` 与图包标签 `PACK_ONLY` 分离。
6. 实际打开三图图包并翻到第 2 张，切换纵向后仍为 2/3，返回原图包库。`release-smoke.json` 与对应原生 XML/PNG 记录明确状态。
7. 显式切换到实际旧服务 8772。其数据库版本为 0004，新 App 使用既有旧视频 UI，能列出两个视频和 `LEGACY_ONLY`；不再显示原新服务标签。`legacy-compatibility.json` 保留切换窗口的所有路径/状态，均 200，没有图包调用。旧服务模式可能自动播放，不套用第 4 步的新服务行为。

请求观察器只通过 uvicorn 日志格式记录时间、方法、不含查询串的路径和状态，源码 `path_log.py`／`logging.json`；没有中间件或响应改写。没有保留请求体、口令、token 或认证头。登录数据只保存数量和聚合 SHA，不保存原 token 或数据库文件。

## 截图

| 阶段 | 记录 |
| --- | --- |
| 旧 APK 已连接／偏好设置 | `old-connected-corrected`、`old-final-preferences` |
| 覆盖安装后默认媒体库 | `new-first-library` |
| 保留设置／免口令连接表单 | `new-settings-preserved`、`new-legacy-connection-empty-password` |
| 分离标签 | `new-video-tags-confirmed`、`new-pack-tags` |
| 图包与第二页／纵向／返回 | `new-pack-library`、`new-reader-page-two`、`new-reader-settings-vertical`、`new-reader-vertical`、`new-pack-library-return` |
| 实际旧服务兼容 | `preview-on-legacy-service`、`legacy-tags`、`legacy-video-library` |

每项在 `screens/` 有 PNG、UIAutomator XML 和实际前台窗口记录。人工查看已确认首屏媒体库、第二页纵向画面和旧服务双视频列表；本轮不是所有页面独立视觉评审或完整三轮验收。

## 复核与范围

在仓库根目录运行 `python3 docs/plans/library-first/evidence/lf8-preview-package/verify.py`，检查 manifest、固定 Git 源码、日志与产物元数据、覆盖安装投影、实际 UI 文本、清理及原型身份。加 `--artifacts tmp/releases` 可重算本机两份二进制哈希；加 `--recompute-ast` 使用同一生产镜像里的 Python 3.13 重新比较固定两版服务 AST。复核只读，不再执行安装或业务写入。

`cleanup.json` 确认本轮独立 AVD 进程消失、两容器已删除；原四服务 ID 与运行状态前后相同。独立 AVD 的已关闭资料留在 `.dev/` 供复跑，未修改原 AVD 的显示参数／默认凭据。输入脚本和初次清理归属断言诊断见 `diagnostics.md`。

本轮补 UP-01/02 的本机明确组合；没有验证真实手机/NAS、实际旧数据目录迁移回退、App 回退、云文档提供器、500 页 4K/8K或其它完整功能组合。**#89 原始故障未复现，#78 未关闭**。预览版本和模拟器成功不代表整体完成，#24/#33继续开放。
