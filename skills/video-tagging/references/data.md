# 数据与运行约定

每次开始时读取。所有示例路径为相对于私人工作区的示例，以实际配置为准。

## 分层文件

- `manifest.json`：`[{"video_id":"V000001","root_id":"main","relative_path":"目录/视频.mp4","pool_hint":"真人/动画/不确定","sha256":"可选强校验散列"}]`。编号唯一且跨移动保留，另存旧路径→新路径映射。文件名相同不足以证明相同视频。
- `config.json`：复制随包默认配置；每机设置 `media_roots`、模型目录 `model_root`、实际 `local_model` 或 `online_model`、Ollama 地址与隐私选择。路径支持相对于配置文件的值和环境变量；不相对于启动目录。`extractor` 留空使用随包脚本，显式配置时使用该兼容抽帧器。模型字段需填写实际执行方的型号，不用历史内部名猜 API 名。
- `runs/<配置指纹>/<编号>/`：输入签名、抽帧、任务、模型原答、解析结果。原答即使解析失败也保留；更改提示词/模型/视频签名会生成新版本。
- `facts.json`：只从已有原始结构化标签、明确目录类别提取，格式见归并参考。记录原文件、字段、原词、来源类型和状态；这是适配层而不是新增识图结论。
- `standard.json`、`standard.md`：可重复生成的标准层；变更前先另存版本。JSON 是导入依据，MD 是展示。
- `targets.json`、`state.json`、`sync-plan.json`、`receipt.json`：唯一视频映射、差量计划与请求/读回回执。

脚本只接受新输出路径，既有标准文件不会直接覆盖；原始目录从不作为输出目录。严格隐私运行不要 cat 原答、标签、文件名或错误堆栈，日志输出匿名编号及异常类。原始文本可能含敏感信息，工具调试也需本地落盘。

## 依赖与定位

识别入口需 Python 3.10+；随包抽帧器另需 FFmpeg/ffprobe 和 Pillow，使用执行 `infer.py` 的同一个 Python 安装 `assets/requirements-extract.txt`。本地图片模型另需 numpy、onnxruntime，视觉模型需 Ollama。先检查现有环境和脚本 `--help`；所有路径与模型以当前用户的配置为准。

本地示例权重布局：
```
model_root/
  joytag/model.onnx
  joytag/top_tags.txt
  wd-swinv2-v3/model.onnx
  wd-swinv2-v3/selected_tags.csv
```
JoyTag 角色类别借助已安装 WD 的 character 词表区分；这不是额外运行 WD。未找到角色词表时停止 JoyTag 初始化，避免把角色候选当普通事实。模型来源：fancyfeast/joytag、SmilingWolf/wd-swinv2-tagger-v3；模型和依赖不随技能分发，实际版本/权重散列写入 config 的 `model_revision`。大模型更换后重新核对多图输入兼容性。

拾刻地址通过 CLI 的 `--base-url` / `RV_BASE_URL` 或用户自己的 CLI 配置读取；个人口令使用交互输入或 `RV_PASSPHRASE`，访问令牌由 CLI 保存到用户配置目录。需要使用其他私有配置管理工具时由用户指定，不依赖制作者的资料库、SSH 配置或某个固定文件名。凭据只在程序内使用，日志和技能 Git 不保存令牌、密码或私钥。

## 失败与续作

每个视频完成立即保存。网络超时/暂时性服务错误最多重试两次并保存次数；身份拒绝、缺权重、无效输入先解决原因，不反复重试。脚本不自动重试，操作者对失败编号按上述上限续作。已完成项只在视频签名、配置、提示词与工具版本匹配时复用；不以“文件存在”跳过。相同大小/mtime 不能提供强同一性保证，有疑点使用用户授权的文件散列或恢复映射。

无法识别、未执行、解析失败、技术错误分别记录；坏文件不能自动删除。不得把空候选或请求成功写成“全部标签正确”。

## 原始层保护（必做）

在首次修改派生文件前，以工作区 `original-files.json` 列出需要保护的原始 JSON、原始 MD、旧目录索引等。路径相对于该清单，逐个真实文件，不把视频或所有缓存递归加入。运行：
```
python "$skill_dir/scripts/catalog.py" protect --files original-files.json --output protected.json
python "$skill_dir/scripts/catalog.py" verify --protected protected.json
```
保护文件记录相对于自身位置的路径与 SHA-256，工作区整体移动后仍可验证。归并、匹配、计划命令均需要 `--protected protected.json`。实际软件写入前后再 verify；不一致则停止本批后续写入，定位变动并从备份恢复/另存修订，不能刷新基线掩盖修改。

保护文件要纳入本次核对的**全部**原始输入。`normalize` 会另检查每个肯定事实的来源文件都在保护集中，并用 JSON Pointer 核对原词；缺失和不符会报错。Markdown 原稿纳入保护集；事实优先定位对应原始 JSON，不能为了获得“可核对来源”凭空生成 JSON 事实。

识别原答与 result 使用拒绝覆盖写入；内容相同的重试直接复用，内容不同保留原件并报错，只有 progress 可更新。并发运行同一输出目录不受支持，先停止同批旧进程再续作。
