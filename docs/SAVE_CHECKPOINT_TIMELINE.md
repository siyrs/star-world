# Save Checkpoint Timeline

## 目标

保存系统继续保持单一权威事务：所有手动保存、自动保存、返回主菜单保存和维护级系统保存都复用 `GameplayServiceHub.save_current()`，检查点时间线只记录结果，不创建第二个 Timer、第二份文件或平行存档域。

本能力解决三个玩家与运维问题：

- F3 过去只能看到最近一次保存成功或失败，无法判断来源；
- 自动保存、手动保存和最终返回保存无法在同一健康历史中关联；
- 成功返回主菜单后，运行健康报告可能继续显示旧世界 ID。

## 状态所有者

`RuntimeHealthReportService` 是会话级检查点证据的唯一状态所有者。

`SaveCheckpointTimelinePolicy` 只负责严格归一化与有界投影，`SaveCheckpointTimelineFormatter` 只负责 F3 文本。二者都是纯 `RefCounted`，不采样、不写盘、不修改玩法领域。

## 来源合同

只允许四类稳定来源：

```text
manual
 autosave
return_to_menu
system
```

未知来源确定性归一化为 `system`。返回主菜单由组合根在调用原有保存流程前设置短生命周期上下文；自动保存不修改原有参与者，而是在权威保存调用期间通过其 `saving=true` 快照确定来源。

## 有界预算

- 最近事件固定最多 12 条；
- 被淘汰事件只增加 `history_dropped_count`，来源累计计数保持精确；
- world ID 最长 128 字符；
- 每个事件只保留 sequence、reason、world ID、结果、字节、耗时和单调时间戳；
- 自动保存投影只保留 enabled、active、paused、pending、saving、周期、下次时间和失败退避标量；
- F3 只显示来源累计、12 条历史预算、最近检查点和下一次自动保存。

## 生命周期

`begin_world()` 设置当前权威世界 ID；保存失败且玩家仍在世界时保持该 ID 和 runtime attachment。只有成功返回主菜单或世界启动失败后，组合根才调用 `end_world()` 清空当前世界 ID。

会话历史不会因切换世界自动清空；显式 `clear_session_counters()` 才会重置历史、sequence、来源计数和淘汰计数。

## 持久化边界

检查点时间线是运行诊断，不进入 `world.json`、catalog sidecar、trash manifest 或 settings。真实测试会对保存后的完整 payload 做字符串和结构检查，禁止 `save_timeline`、`checkpoint_history` 与 `save_checkpoint` 字段出现。

## 真实验收

永久门禁覆盖：

- 20 个事件收敛为最近 12 个，sequence 与淘汰计数确定；
- manual、autosave、return_to_menu、system 累计在淘汰后仍保持精确；
- 未知来源归一化、任意 payload 被严格投影剔除；
- 真实暂停菜单按钮产生 manual 检查点；
- 未暂停活动时间触发真实 autosave，并持久化背包变化；
- F3 同时显示手动与自动来源、最近自动保存成功和下一次倒计时；
- 1280×720 真实桌面截图和 JSON 报告；
- 全量 Godot 桌面矩阵及 Windows Release 继续作为主分支合入条件。
