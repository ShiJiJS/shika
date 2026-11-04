# LF8：原型可移除构建演练

对应 #24／#33，补 LF0 已声明但尚未实测的隔离边界。原型保留在 `design/reference/`，标记与冻结树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 保持不变；本段只删除一次性源码副本中的参考目录。

`scripts/check-reference-isolation.py --output .dev/<新目录>` 导出指定提交的全部已跟踪文件，在导出副本中移除 `design/reference/`。副本不含 Git 元数据、未跟踪凭据或生成配置，并通过 Git discovery 上界防止借用父目录的原仓库。只共享本机 SDK、Gradle 与包缓存，App 的 package root 必须实际指向副本；初次使用离线、锁文件约束解析依赖，构建保留 Flutter 标准插件注册过程。原型已移除的源码也支持运行，参考元数据记为 null／0，不新增运行时依赖。

在该副本里执行 Flutter analyze、完整客户端测试、ARM64 debug 与 release APK 构建，检查 APK 的 Flutter 资产列表没有参考目录；在副本的 server 构建上下文中生成 Linux 测试镜像，执行 Ruff 与完整 pytest。服务格式检查单独记结果，原有格式问题不伪装成原型依赖，也不为通过本段而批量重排生产服务代码。

每步日志、退出状态、源码提交、脚本哈希、导出文件哈希、APK 哈希与资产清单放在 `.dev/`。结束时核对副本全部保留文件未被构建改写，原仓库参考文件字节未变。APK 只作本机构建证明，不上传、不安装、不递增发布版本；现有 release 构建使用开发签名，不能据此认证原签名手机覆盖升级。

本段不证明全部业务与原型视觉一致，也不替代手势、故障、目标手机／NAS与性能验收。完整回归若发现当前整合代码问题，修正后按新冻结提交重跑；失败记录保留。

## 当前状态

[Draft PR #75](https://github.com/ShiJiJS/shika/pull/75)基于#74。修正后按固定7c70e59完整运行第二轮：移除副本72份参考文件，保留12,145份跟踪文件；Flutter analyze、643项完整客户端测试、debug/release APK构建、服务镜像Ruff check及447项Linux pytest通过（1项Starlette依赖弃用警告）。构建后保留文件、原参考文件字节未变；原型仍在原仓库独立保留。服务格式检查27份存量文件未过，另行记录，未批量重排服务。完整结果、APK资产清单及首轮诊断见[证据与只读复核](https://github.com/ShiJiJS/shika/blob/c9c6363ab1ca3bb7d72c96499432a289de33f187/docs/plans/library-first/evidence/lf8-reference-isolation/README.md)。

首轮在 debug 后复用 `--no-pub` 构建 release，当前 Flutter 因跳过模式专用注册而残留 integration_test 插件，release 失败；同一副本改用标准 release 命令已通过。修正演练脚本后重新完整执行，保留首轮失败，不删除测试依赖或修改 SDK。release 额外检查 Flutter 引擎为 ARM64、DEX 无 integration_test 插件路径；各 JNI 依赖 ABI 另行列明。
