[项目首页](../README.md) · [文档导航](README.md) · **简体中文** · [English](video-tagging.en.md)

# 视频打标 Skill 与 CLI（选装）

普通浏览、播放、阅读和手动标签只需要 App 与 NAS 服务。需要用 AI 批量补充视频标签时，可以另外安装 [video-tagging Skill](../skills/video-tagging/SKILL.md)；需要脚本查询和修改媒体库时，也可以单独使用 [shika CLI](../apps/cli/README.md)。

Skill 在支持 Skills 的助手中运行，负责抽帧、调用用户选择的模型、整理中文标签和按需同步。CLI 连接与 App 相同的 NAS 服务，执行视频查询和标签操作。模型运行在执行 Skill 的电脑或用户选择的服务上，标签写回后可在 App 中使用。

## 一次安装 Skill 和 CLI

准备 Python 3.10+、Git，以及一个支持 Skills 的助手。使用 Skillshare 时，先完成它的安装与目标配置。在本仓库根目录执行：

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
```

安装器先从同一检出的 `apps/cli` 配置隔离 CLI，再通过 Skillshare 安装和同步技能。Windows 可用 `python` 替代 `python3`，选择符合版本要求的 Python。

没有使用 Skillshare 时，指定助手实际使用的技能父目录：

```bash
python3 skills/video-tagging/scripts/install.py --skills-dir ~/.agents/skills
```

上面的目录是示例，按助手配置调整。由 Skillshare 或其他管理器维护的目录应通过对应管理器更新。直接安装遇同名技能会停止；检查旧内容后加 `--update` 可以先备份再更新。备份位于私人运行目录。

Skillshare 更新时运行安装器的 `--skillshare --update`，它调用正式的 `skillshare update video-tagging` 并沿用已登记来源。`--skill-source` 仅用于首次安装。同名技能登记在其他来源时，先通过管理器备份、卸载旧登记，再从本仓库安装；更新不会切换来源，安装器保留其审计检查。

仓库需要访问权限时使用自己已有的 Git 认证。例如 Skillshare 使用 SSH 来源：

```bash
python3 skills/video-tagging/scripts/install.py --skillshare \
  --skill-source git@github.com:ShiJiJS/shika.git//skills/video-tagging
```

安装器不修改 shell PATH、系统 Python、App 或 Docker 配置。CLI 环境、安装日志及手动更新备份位于用户数据目录下的 `shika/video-tagging`；Windows 使用 `%LOCALAPPDATA%/shika/video-tagging`。可通过 `SHIKA_TAGGING_HOME` 改变位置，安装与运行时使用相同值。

## 通过其他安装器取得 Skill

技能包位于本仓库的 `skills/video-tagging`，可交给助手自己的 Skill 安装工具。单纯复制技能文件不会自动安装 Python 工具；在安装或首次使用时，让助手执行包内的配置与检查：

```bash
python3 <技能目录>/scripts/install.py --cli-only
python3 <技能目录>/scripts/install.py --check
python3 <技能目录>/scripts/shika.py --help
```

单独技能包默认从本仓库主分支取得 CLI，安装需要 Git 和依赖下载。已有源码时可追加 `--cli-source <检出目录>/apps/cli`。安装器不读取服务口令，不登录 NAS，也不会下载模型或开始处理视频。

## 使用方式

可以对助手说：

- “使用 video-tagging，给指定目录的视频打标签，只生成标签文件。”
- “把已有标准标签同步到拾刻，保留我手动加的标签。”
- “使用本地模型识别这批视频，完成后同步到拾刻。”

实际流程是：准备清单 → 选择本地或线上识别 → 保存原始回答 → 生成 `standard.json` / `standard.md` → 按要求匹配视频、生成同步计划并写入拾刻。也支持只整理已有结果或只同步，不必重新识别。

新识别需要 FFmpeg/ffprobe、抽帧用的 `video-understanding` 及其 Python 依赖。本地路线还需要 Ollama、ONNX Runtime 和用户选择的模型权重；线上路线需要用户选定的视觉服务。它们不包含在 CLI 安装中，具体依赖见[声明](../skills/video-tagging/assets/dependencies.json)。线上入口目前准备任务和导入回答，服务调用由执行 Skill 的助手接入；长视频自动分段仍需按模型能力处理。

## 连接与数据

通过技能目录中的 CLI 入口登录：

```bash
python3 <技能目录>/scripts/shika.py login --base-url http://NAS_ADDRESS:8760
```

把 `NAS_ADDRESS` 替换为自己的服务地址，端口按实际部署设置。口令交互输入，或通过自己的 `RV_PASSPHRASE` 环境变量提供；CLI 不保存口令。地址、访问令牌和配置位置遵循 [CLI 配置说明](../apps/cli/README.md#配置与凭据)。

抽帧还需要电脑能够读取原视频；配置中明确对应本机媒体根目录与服务端目录。媒体库里的容器路径不能直接当作电脑上的 SMB 路径。

原答、标签文件、进度和同步回执放在私人工作区。发布包仅包含通用代码、说明和空配置，不包含媒体、模型、连接凭据或个人运行结果。原视频只读；同步按差量修改视频标签，并保留无归属证据的已有标签。默认图片与标签文本权限分开管理，按 Skill 中的选择执行。

App 的图包标签与视频标签独立；此 Skill 只同步视频标签。完整管理备份优先走 v2 API，CLI 的 `backup` 仍是旧视频管理备份，不能当作包含图包的完整备份。
