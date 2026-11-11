# 跨设备配置

换电脑、工作区移动或缺依赖时读取。技能包不依赖制作者电脑、当前项目仓库、某个用户名、NAS 挂载名称或已有虚拟环境。

## 需要随身与需要重新绑定的部分

可搬移：原始结果、保护清单、事实与规则、标准标签、稳定编号、原目录索引、旧→新移动清单、成功导入回执。保持私人工作区内的相对结构。技能文件可由 Skillshare 或随包安装器分发；这些私人记录不放进技能仓库。

每机绑定：媒体根目录、模型权重目录、抽帧器、Python/FFmpeg/Ollama、认证配置。绑定写到私人 config.json；值可为相对配置文件路径、`${变量名}` 或本机绝对路径，绝不把某台机器的配置当作跨设备默认值。

示例（目录仅为示例）：
```
{
  "media_roots": {"main": "${VIDEO_MEDIA_ROOT}"},
  "model_root": "models/image-tagging",
  "extractor": "tools/extract_keyframes.py"
}
```
以上是需要合并进随包默认配置的路径部分。环境变量在当前设备设置。`extractor` 也可留空，由安装位置寻找相邻 video-understanding；否则明确指定本机安装的抽帧脚本。该外部技能是依赖，不是对原项目目录的依赖。不会复制或改写它的设备配置。

manifest 使用 `root_id + relative_path`；它与软件中的根编号建立明确映射，但本机根路径和服务端根路径可以不同。兼容旧 source_path：相对值以 manifest 所在目录为基准，绝对值必须在本机有效。模型与 extractor 相对值以 config.json 为基准；线上回答 task_path 相对值以 answers.json 为基准；事实 source_ref 相对于 facts.json；保护文件内部路径相对于保护文件。CLI 输出位置由本次命令指定。

## 迁移检查

1. 核对技能包完整及 Python 版本；通过当前 PATH 或明确本机路径查找 ffmpeg/ffprobe。确认模型文件及记录的版本，不假设技能同步包含权重。
2. 绑定本机路径并 stat 元数据，不打开视频。Windows 使用实际盘符/UNC；跨系统清单内部的 relative_path 统一 `/`，使用 Python Path 处理本机路径，不靠字符串拼接盘符。
3. 原始记录和目录索引先验证散列。输入原目录信息是内容分类的依据，新的“真人/动漫”归档分区不替代原内容目录。
4. 老缓存和原答包含当时绝对路径是审计信息。已有标签整理直接读取原始 JSON，不因换电脑/失去旧帧路径重新识图。新识别按当前选择建立新运行目录；旧线上任务需要本地调度器重新绑定路径并核对输入签名，不能把旧地址无条件替换后提交。
5. 接入软件重新核对实际库实例、根挂载和新扫描结果，按同步参考执行。连接使用当前用户的 CLI 配置或指定私有配置；不能退回制作者路径或要求复制制作者密钥。

本包已做“移动临时工作区、改变启动目录、中文路径、Windows 路径格式拒绝错误绑定”的离线测试；Windows/Linux 的真实抽帧、模型和软件联调仍未实机验证。部署文件可移植不等于运行依赖已安装。

## 选装安装入口

先准备 Python 3.10+。在拾刻源码仓库根目录执行：
```
python skills/video-tagging/scripts/install.py --skillshare
```
这会从同一检出的 `apps/cli` 安装 CLI 到独立环境，再通过已配置的 Skillshare 安装并同步本技能。普通 App / Docker 部署无需运行。Skillshare 来源默认 `ShiJiJS/shika/skills/video-tagging`；私有仓库使用现有 Git 认证，可显式传 `--skill-source git@github.com:ShiJiJS/shika.git//skills/video-tagging`，凭据不写入 URL。

未使用 Skillshare 时，显式选择 Agent 的技能父目录：
```
python skills/video-tagging/scripts/install.py --skills-dir /path/to/agent/skills
```
已经由其他管理器维护的目录使用其管理器；直接安装器遇同名内容会停止，明确更新时加 `--update`，旧手动副本会备份到私人运行目录。

通过 Agent 自带安装器或 Skillshare 单独取得技能文件后，执行包内安装器补齐 CLI：
```
python "$skill_dir/scripts/install.py" --cli-only
python "$skill_dir/scripts/install.py" --check
python "$skill_dir/scripts/shika.py" --help
```
CLI 源码在完整检出中读取本地 `apps/cli`；单独技能包默认从拾刻 GitHub 主分支取得，可用 `--cli-source` 指定已检出的 `apps/cli` 或用户授权的 Git 来源。安装器需要联网取得 CLI 的 Python 依赖；不安装模型、不运行识别、不连接媒体库、不修改 shell 配置。

独立运行目录默认 macOS/Linux 的用户数据目录下 `shika/video-tagging`，Windows 为 `%LOCALAPPDATA%/shika/video-tagging`。用 `SHIKA_TAGGING_HOME` 可指定本机位置，安装和运行时保持相同值；此目录包含 CLI 环境、安装日志和手动更新备份，不随技能同步。CLI 的服务地址和令牌仍由其用户配置管理。
