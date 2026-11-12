[项目首页](../README.md) · [文档导航](README.md) · **简体中文** · [English](video-tagging.en.md)

# 视频打标 Skill 与 CLI（选装）

普通浏览、播放、阅读和手动标签只需要 App 与 NAS 服务。CLI 的代码在本仓库 `apps/cli`，可按 [CLI 说明](../apps/cli/README.md#安装)独立安装；它用于登录、扫描、视频查询和视频标签操作，不需要 Skill 或 AI 模型，也不会随 App/Docker 自动安装。

Skill 在本仓库 `skills/video-tagging`，交给支持 Skills 的助手使用：抽帧、调用用户选定的模型、整理中文标签，并按要求通过 CLI 同步到同一个服务。**Skillshare 不是前置依赖**。

## 安装 Skill 和隔离 CLI

准备 Python 3.10+，在仓库根目录指定助手实际使用的技能父目录：

```bash
python3 skills/video-tagging/scripts/install.py --skills-dir /path/to/agent/skills
```

将示例路径换成自己的目录。安装器从同一检出的 `apps/cli` 创建独立 Python 环境，再复制 Skill。Windows 可以使用符合版本要求的 `python`。遇到同名技能时会停止，检查后可加 `--update`，先备份旧手动副本再更新；由其他管理器维护的目录通过其管理器更新。

安装器不修改 shell PATH、系统 Python、App 或 Docker 设置。CLI 环境、安装日志和手动更新备份保存在用户数据目录的 `shika/video-tagging` 下，Windows 为 `%LOCALAPPDATA%/shika/video-tagging`。可通过 `SHIKA_TAGGING_HOME` 指定位置，安装与运行时保持一致。

## 使用助手自己的 Skill 安装方式

将本仓库的 `skills/video-tagging` 交给助手安装，也可以复制完整目录。只取得技能文件后，再补齐 CLI：

```bash
python3 <技能目录>/scripts/install.py --cli-only
python3 <技能目录>/scripts/install.py --check
python3 <技能目录>/scripts/shika.py --help
```

单独取得的 Skill 默认从本仓库的 HTTPS Git 地址下载 CLI，需 Git 和依赖下载；已有源码时可加 `--cli-source <检出目录>/apps/cli`。仓库受限时使用自己的 GitHub 授权，凭据不写入 URL。安装不读取口令、不登录 NAS、不下载模型、不处理视频。

## 已有 Skillshare 用户的可选方式

只有已经使用并配置了 Skillshare 的用户才需要这一入口，与普通目录安装二选一：

```bash
python3 skills/video-tagging/scripts/install.py --skillshare
python3 skills/video-tagging/scripts/install.py --skillshare --update
```

此方式使用管理器的安装、审计和同步。`--skill-source` 只用于首次指定来源，更新沿用已登记来源；同名旧来源通过管理器处理。

## 使用方式

可以对助手说：

- “使用 video-tagging，给指定目录的视频打标签，只生成标签文件。”
- “把已有标准标签同步到拾刻，保留我手动加的标签。”
- “使用本地模型识别这批视频，完成后同步到拾刻。”

实际流程是：准备清单 → 选择本地或线上识别 → 保存原始回答 → 生成 `standard.json` / `standard.md` → 按要求匹配视频、生成同步计划并写入拾刻。也支持只整理已有结果或只同步，不必重新识别。

新识别使用随包抽帧器，需要 FFmpeg/ffprobe 和 Pillow，不依赖其他 Skill。本地路线还需要 Ollama、ONNX Runtime 和用户选择的模型权重；线上路线需要用户选定的视觉服务。它们不包含在 CLI 安装中，具体依赖见[声明](../skills/video-tagging/assets/dependencies.json)。线上入口目前准备任务和导入回答，服务调用由执行 Skill 的助手接入；长视频自动分段仍需按模型能力处理。

### 抽帧环境

只整理已有标签或同步时可跳过。新识别先安装系统 FFmpeg（同时提供 ffprobe），再在仓库根目录准备自己的 Python 环境：

```bash
python3 -m venv .venv-tagging
.venv-tagging/bin/python -m pip install -r skills/video-tagging/assets/requirements-extract.txt
.venv-tagging/bin/python skills/video-tagging/scripts/extract_keyframes.py --help
```

Windows 将 `.venv-tagging/bin/python` 换为 `.venv-tagging\Scripts\python.exe`，后续用同一环境执行 `infer.py`。默认约每 2 秒采样一帧，最多 200 帧，均匀覆盖整段视频并生成多张总览图；不是逐帧分析或镜头检测。私人配置的 `extractor` 可以显式指定兼容脚本。原视频只读，输出放在独立的空目录。本地路线还需在该环境安装 numpy/onnxruntime，并配置自己的 Ollama 与模型权重；线上模型由用户选择。

## 连接与数据

通过技能目录中的 CLI 入口登录：

```bash
python3 <技能目录>/scripts/shika.py login --base-url http://NAS_ADDRESS:8760
```

把 `NAS_ADDRESS` 替换为自己的服务地址，端口按实际部署设置。口令交互输入，或通过自己的 `RV_PASSPHRASE` 环境变量提供；CLI 不保存口令。地址、访问令牌和配置位置遵循 [CLI 配置说明](../apps/cli/README.md#配置与凭据)。

抽帧还需要电脑能够读取原视频；配置中明确对应本机媒体根目录与服务端目录。媒体库里的容器路径不能直接当作电脑上的 SMB 路径。

原答、标签文件、进度和同步回执放在私人工作区。发布包仅包含通用代码、说明和空配置，不包含媒体、模型、连接凭据或个人运行结果。原视频只读；同步按差量修改视频标签，并保留无归属证据的已有标签。默认图片与标签文本权限分开管理，按 Skill 中的选择执行。

App 的图包标签与视频标签独立；此 Skill 只同步视频标签。完整管理备份优先走 v2 API，CLI 的 `backup` 仍是旧视频管理备份，不能当作包含图包的完整备份。
