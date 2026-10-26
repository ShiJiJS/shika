# LF8 原型目录移除演练证据

本段补用户要求的“原型独立标记，未来可以移除”。固定源码 `7c70e5983f8ed8cc3e71077910bc362434d266cb`，方案见 [实施记录](../../LF8-REFERENCE-ISOLATION.md)。演练将整个 Git 提交导出到新建的 `.dev/lf8-reference-isolation/run-2/workspace`，仅在副本中删除 `design/reference/` 的72份文件，保留其余12,145份跟踪文件。原仓库另有3份未跟踪的本机验证JSON（validation*.json），共75份参考目录文件在演练前后哈希未变；这3份没有进入Git导出，不算移除的72份跟踪文件。原仓库参考目录保留，冻结原型树 `1cbf605af8f03fa067a4ce8e914bb809e3a487ca` 未改。

`run/` 保留完整结果、各命令原始日志及退出码、导出文件 SHA-256、原参考文件 SHA-256、解析后的包配置、两种 APK 资产清单。App 自身包根指向该导出副本；通过 Git discovery 上界阻止副本读取父仓库元数据，只共享本机 SDK 和依赖缓存，不复制私钥、未跟踪配置或生成目录。初次依赖解析离线并强制锁文件，后续两种构建使用标准 Flutter 命令以正确重建模式专用插件注册；不声称所有命令全程断网。构建后全部保留源码字节未变，副本参考目录仍不存在，原参考目录字节未变。

第二轮在同一固定源码完整通过客户端643项测试、Flutter analyze、ARM64 Flutter 引擎的 debug/release 构建，以及副本服务镜像的 Ruff check 和 Linux pytest 447项（665.09秒，1项Starlette依赖弃用警告）。Flutter版本3.47.7、Dart3.13.5见run/checks/flutter-version.log。服务 `ruff format --check` 的27份存量格式文件单列失败；未为此重排生产服务，不能声称完整格式门禁通过。服务测试包含大于32MiB的备份 HTTP 路径、500页和4K/8K扫描等既有用例；它们不证明 Android 渲染、手机/NAS速度或系统选择器。

`diagnostics/run-1/` 保留首轮结果和日志：源码36db1f4的643项客户端及447项服务测试通过，但 debug 后对 release 误用 `--no-pub`，跳过 Flutter 模式专用注册，残留 integration_test 注册并导致 release 编译失败。首轮 `complete:false`。同一副本改为标准 release 命令通过，作为诊断附录，不拼接为首轮整体成功。随后7c70e59修正演练脚本，重新执行完整第二轮；未改SDK、未移除 integration_test 开发依赖。

`checks/unsafe-output-checks.json` 记录输出边界检查：仓库根目录、整个 `.dev` 和已有演练目录全部拒绝，返回2。删除只发生在新建导出副本，原型可移除性没有通过真实删除原仓库来验证。

运行只读复核：

```sh
python3 docs/plans/library-first/evidence/lf8-reference-isolation/verify.py
python3 docs/plans/library-first/evidence/lf8-reference-isolation/verify.py --run-dir .dev/lf8-reference-isolation/run-2
```

默认模式核对清单覆盖与全部证据哈希，重新读取固定 Git 提交的全部blob，独立验证导出完整性、原型72文件与原仓库字节、当前客户端/服务/开发脚本字节和必需步骤。`--run-dir` 额外核对原仓库全部75份文件，并重新读取实际私有导出文件及两份 APK，核对 APK 整包哈希、大小、资产、Flutter 引擎 ABI 和 DEX 测试插件路径。默认模式只验证提交中的结果记录，不能替代第二条命令对私有产物的实际重读。`verification.json` 是后者的本机结果。

APK 未纳入提交或上传，也未安装到手机。release 沿现有开发签名配置、未递增版本，不能作为原签名覆盖安装证明。JNI依赖可能另带 armeabi-v7a/x86_64；引擎实际为 arm64-v8a，完整ABI按结果列明。release DEX额外核对不含 integration_test 插件路径，debug允许存在。

本段不新增UI、不重新认证静态图/手势，也不关闭#24/#33及整体验收。原型对照剩余交互、目标手机/NAS、原签名升级和真实性能验收继续；需用户配合项按授权暂跳过。正式8760/NAS及生产backup_v2开关未改。
