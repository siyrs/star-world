# Architecture Audit · 2026-07-29 · Iteration 49

## 审计范围

本轮从 `master` 的下一阶段“长期规模与恢复”继续审计保存检查点时间线、运行健康服务、F3 格式化、跨世界生命周期和现有真实桌面门禁。

## 发现 1：world ID 不是进入会话

原 `SaveCheckpointTimelinePolicy` 已提供 `current_world_history`，但过滤条件只有 `event.world_id == current_world_id`。

这在 A → B 时可以隔离世界，却无法处理：

```text
A 第一次进入并保存
→ 退出
→ 再次进入 A
```

持久 world ID 相同，但玩家已经进入新的运行会话。旧 A 事件会重新出现在当前世界历史中。

### 风险

- F3 会把上一轮进入的保存误认为本次进入已保存；
- 自动保存尚未触发时，玩家得到错误安全感；
- 故障排查无法区分同一世界的不同运行阶段；
- 长时间 A → B → A 压测缺少可验证边界。

## 发现 2：活动世界无记录时错误回退

`SaveCheckpointTimelineFormatter` 在 `last_current_world_event` 为空时回退到全局 `last_event`。

进入 B 但尚未保存时，F3 可能显示 A 的“最近检查点成功”；重新进入 A 时也可能显示 A 上一次进入的结果。这是玩家可见的事实错误，而不是纯展示偏差。

## 发现 3：不应把会话边界塞进存档

世界进入会话只是运行诊断。把 session ID 写进 `world.json` 会制造无意义迁移和第二状态来源；给每个世界创建独立时间线也会破坏当前全局 12 条预算与来源累计。

## 决策

采用**全局 sequence 进入边界**：

- 保留原 `RuntimeHealthReportService` 作为保存历史和健康证据所有者；
- 生产组合根挂载其窄子类 `SessionScopedRuntimeHealthReportService`；
- 每次 `begin_world()` 记录当时的 `_save_event_sequence`；
- 当前事件要求 world ID 匹配且 sequence 大于进入边界；
- 纯 `WorldScopedSaveCheckpointTimelinePolicy` 复用原白名单和预算后再做作用域投影；
- F3 在活动世界无当前记录时明确显示“当前世界本次进入尚无保存记录”，禁止回退。

## 为什么没有创建第二套时间线

- 全局 `_save_event_history` 仍只有一份；
- 全局来源累计和 dropped 计数仍精确；
- `save_current()`、自动保存和返回保存路径完全不变；
- 没有 Timer、文件、序列化或领域扫描；
- 作用域字段全部是瞬时标量。

## 兼容策略

`WorldScopedSaveCheckpointTimelinePolicy` 对没有会话边界字段的旧内存快照保留原 world-ID 投影。生产 `SessionScopedRuntimeHealthReportService` 始终提供新边界，因此正式 F3 使用严格会话语义。

现有键名 `current_world_history` 与 `last_current_world_event` 保留，但语义升级为当前世界的**本次进入**；同时新增更明确的：

- `current_session_history`；
- `current_session_history_count`；
- `last_current_session_event`。

## 测试发现与加固

本轮永久测试覆盖：

1. 纯策略 A → B → A；
2. 同 world ID 旧事件排除；
3. 全局历史和来源累计保留；
4. 活动世界无保存时禁止 formatter 回退；
5. 显式 `clear_session_counters()` 在活动世界中重新基准；
6. 两个真实存档的生产桌面切换；
7. B 首次进入和 A 再次进入的 F3 双截图；
8. 第二次进入 A 后真实暂停保存；
9. `world.json` 持久化边界由原时间线门禁继续保护；
10. 权威 Runtime、完整桌面矩阵和 Windows Release。

## 结果标准

只有以下证据全部成功才允许合入主分支：

- 新静态合同；
- 新 Headless 回归；
- 原保存时间线、自动保存、运行健康相邻回归；
- 新真实 A → B → A 桌面旅程；
- 原保存时间线真实桌面；
- Godot 4.7 严格导入；
- Windows Release 实际导出与启动。
