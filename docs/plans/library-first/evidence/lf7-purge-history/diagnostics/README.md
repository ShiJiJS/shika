# 开发与非最终证据

本目录保留本阶段真实观察，不计入最终固定源码的三轮验收。

- `lf7-history-purge-server-development-*`、`client-development-*`、`fixture-setup*` 和原生开发目录：测试/夹具编写过程中的失败与成功。服务端两次恢复的测试后来补等实际后台 future 退出，避免任务终态先于维护锁释放；夹具修正启动时机、原失败剩余范围与注入503代次头。
- `large-text-first-wait`：等待惰性行数不足以说明下一页可操作；改为等待实际按钮启用。
- `large-text-fixed-wait-old-scroll`：127图跨页时，固定拖动次数过早反转；改为先走到实际滚动边界。
- `pre-visual-round-*`：`9199f31` 三轮已通过，但小屏目录截图仍在加载，且根目录显示 `.`。初次 [视觉报告](visual-review-initial.md) 明确了边界；最终源码修正两点，另有全新三轮。
- `root-label-first-round`：`619033c` 小屏双字号通过；同源码普通字号 `root-label-route-transition` 在返回任务页转场中同时匹配到两个同名按钮，定位歧义失败。脚本随后只点击唯一可交互目标，最终三轮使用新固定源码。
- `pre-visual-client-full.log` / `pre-visual-analyze.log`：改根目录展示文字前的全量检查，最新同类结果在父目录。
- `lf7-history-purge-server-full-final.log`：首次完整服务端401项通过/1失败，Docker 默认 `/dev/shm` 约6GiB，与 ENOSPC 用例要求小于256MiB不符。按仓库要求补 `--shm-size=64m` 后同服务端源码402项通过；保留两份日志，不删除失败记录。
- 格式日志对照基线 `c6fda22`：继承的23份未格式化文件列表相同，无新增。Ruff lint 通过不代表全仓 format 通过。

原始 stdout、截图、窗口与轨迹不改写。开发成功、修复前成功和最终成功使用各自源码身份，不能合并成同一固定版本的重复通过。
