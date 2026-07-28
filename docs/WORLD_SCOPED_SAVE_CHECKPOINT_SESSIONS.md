# World-scoped Save Checkpoint Sessions

## 目标

检查点时间线继续保留最近 12 条**全局运行会话证据**，但玩家进入某个世界后，F3 的“本次”记录只能来自这一次进入。退出世界 A、进入世界 B，或再次进入相同的世界 A，都不能把之前的保存结果误显示为当前进入的最近检查点。

本能力不创建第二个保存事务、第二个 Timer 或第二份持久化文件。`world.json` 仍是唯一权威存档，`SessionScopedRuntimeHealthReportService` 仍是原 `RuntimeHealthReportService` 的同一生产实例，只增加瞬时会话边界。

## 已修复的不合理语义

旧实现只按 `world_id` 过滤最近 12 条历史：

```text
进入 A → 保存 A → 退出
进入 B → 尚未保存
```

此时 F3 会回退显示 A 的最近保存。再次进入 A 时，A 上一次进入产生的事件也会重新成为“当前世界历史”。这会让玩家误以为当前进入已经完成保存，并让自动保存故障排查使用错误证据。

## 状态所有者

```text
RuntimeHealthReportService
└─ SessionScopedRuntimeHealthReportService
   ├─ current_world_session_sequence
   └─ current_world_session_started_after_sequence
```

生产组合根只创建一个 `SessionScopedRuntimeHealthReportService`。它继承原有保存计数、历史、恢复统计和来源聚合，不复制任何领域状态。

`WorldScopedSaveCheckpointTimelinePolicy` 是纯投影：

1. 先复用 `SaveCheckpointTimelinePolicy` 的白名单、12 条预算和来源归一化；
2. 再以当前 `world_id` 和进入时的全局 save sequence 边界过滤本次记录；
3. 保留全局 `history`、`reason_counts` 和 `history_dropped_count`；
4. 输出 `current_session_history` 与兼容别名 `current_world_history`。

## 会话边界

每次有效 `begin_world()` 都建立新的瞬时会话序号，并记录进入前最后一个全局保存 sequence：

```text
A 第一次进入：session 1，started_after 0
A 保存：sequence 1
退出 A，进入 B：session 2，started_after 1
B 保存：sequence 2
退出 B，再进入 A：session 3，started_after 2
```

当前会话事件必须同时满足：

```text
event.world_id == current_world_id
event.sequence > current_world_session_started_after_sequence
```

因此同一 world ID 的旧事件不会回流。

## F3 展示

- “保存来源”继续显示整个运行会话的精确累计；
- “检查点历史”同时显示本次进入数量与全局 12 条预算；
- 当前世界本次进入尚未保存时，固定显示“当前世界本次进入尚无保存记录”；
- 只要当前世界处于活动状态，就禁止回退显示其他世界或上一次进入的事件；
- 返回主菜单后没有活动世界时，允许显示整个运行会话的最近事件。

## 显式重置

`clear_session_counters()` 仍清空全局历史、来源累计、sequence 和淘汰计数。若重置发生在活动世界中，该世界会被重新基准为 session 1，之后的新保存从 sequence 1 收敛，不丢失当前世界身份。

## 持久化边界

以下字段全部是瞬时诊断，不进入：

- `world.json`；
- `catalog.json`；
- Trash manifest；
- settings；
- FeatureLifecycle 状态。

瞬时字段包括：

- `current_world_session_sequence`；
- `current_world_session_started_after_sequence`；
- `current_session_history`；
- `last_current_session_event`。

## 永久验收

Headless 回归固定覆盖：

- 全局历史保留、本次进入过滤；
- A → B → A；
- 相同 world ID 重新进入；
- 活动世界无保存时禁止回退旧事件；
- 旧无作用域快照兼容；
- 活动世界中的显式会话重置。

真实桌面旅程固定创建两个生产存档，执行：

```text
A 真实暂停保存
→ 返回主菜单
→ 进入 B 并打开 F3
→ 返回主菜单
→ 重新进入 A 并打开 F3
→ A 第二次进入真实暂停保存
```

门禁输出两张 1280×720 F3 截图、JSON、stdout 和 stderr，并继续要求权威 Runtime、完整桌面矩阵与 Windows Release 全绿。
