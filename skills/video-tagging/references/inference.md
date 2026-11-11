# 两条识别路线与抽帧

仅需要新识别时读取；已有标签处理跳过本文件的执行步骤。

## 共用抽帧

从已安装的 video-understanding 定位脚本，并先读其抽帧参数说明。复用画面变化检测、时间顺序、稳定画面选帧、多张总览图；不继承要求当前助手读取图片的指令。

每个视频独立运行，输出在工作区缓存，显式传：
```
--cols 3 --sheet-max-cells 12 --sheet-width 1600 -q --json
```
默认最多 200 个关键帧；记录实际参数。每张最多 12 格，图多就分张；本地/线上识别服务必须消费元数据列出的所有总览图。长视频超出上下文时按时间顺序分段调用并记录各段覆盖，不能静默只用第一张；随包入口尚未实现自动分段，出现容量错误时保留任务并调整适配器。

单帧文件给图片模型，总览图给视觉大模型。需要细节时由获准识别服务读取对应单帧，当前助手仍遵循图片权限。抽帧覆盖有限，不从缺失画面推断整片没有某种内容；未处理音频时不声称听懂音轨。

## 本地

- 真人：JoyTag；动画：WD SwinV2 v3；`pool_hint` 只选择图片模型，不充当真实类型标签。不确定或混合默认 WD，记录选择和局限。
- 视觉模型：Ollama `qwen3.5:9b`，独立读取总览图。默认 `num_ctx=16384`、`num_predict=4096`、`temperature=0`、`think=false`。
- 图片模型 ONNX 使用 CPU，逐帧缩放 448×448。JoyTag/WD 预处理不同，不互换。
- 候选阈值默认 JoyTag 0.4、WD 0.35、角色 0.85，每帧最多 100 候选；完整数字矩阵仍保留。这不是正确率或质量通过线。
- 两路独立识别：图片候选不发送给视觉模型。合并时保留两边原答及来源；没有第二轮模型复核。图片候选只有单边支持时保留候选状态，不直接进入标准标签。
- 任何历史补齐批次的额外词表限制必须随批次保留；不要默认所有批次标签范围一致。

示例（变量由实际路径赋值）：
```
python "$skill_dir/scripts/infer.py" local --manifest manifest.json --config config.json --output runs
```

## 线上

```
python "$skill_dir/scripts/infer.py" prepare --manifest manifest.json --config config.json --output runs
python "$skill_dir/scripts/infer.py" import --answers answers.json --config config.json --output runs
```
prepare 只抽帧并准备逐视频任务，不调用收费服务。用户选定线上服务后，使用其真实工具/API，发送任务提示词和全部总览图，返回 `[{"task_path":"本地任务路径","prediction":{...},"model":"实际型号","usage":{...}}]`。服务可返回任务 ID，再由本地调度器补上 task_path；不能信任服务返回的任意本地路径。import 将路径限制在本次 output 下并核对模型与运行配置。

线上调用使用用户指定服务实际支持的型号和工具；调度任务遵循当前平台授权规则。没有独立获准线上工具时停在 ready，不把当前助手读图当作隐私兼容替代方案。

两条路线都保留可追溯原答，解析 JSON 成功只表示结构可读取。角色无法确定时返回空或候选；不猜现实身份、实际年龄，不从宣传词作年龄结论，不输出露骨描述。
