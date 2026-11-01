# 可移除的设计参考

**这里只是 LF-2026-10-23 设计与验收原型，不是正式 App，也不部署到 NAS。**

当前基线为 [library-first](library-first/README.md)，实现计划在 [PLAN](../../docs/plans/library-first/PLAN.md)。App、服务端和构建脚本均不依赖此目录。LF8 验收完成后，可删除整个 `design/reference/`，同时清理规划文档中的预览链接；正式功能应通过 App 自身测试验证。

本地运行 `python3 design/reference/serve.py`，打开 http://127.0.0.1:8767/library-first/ 。只在本机监听。

早期 `prototypes/p1`、`prototypes/p2` 是历史探索，不能覆盖本轮验收基线；本机尚保留的其他探索目录不作为实现依赖或发布产物。
