# 长会话自动保存调度合同

## 目标

自动保存已经复用唯一的 `GameplayServiceHub.save_current()` 权威事务，并具备暂停感知、手动保存去重和 15 / 60 / 300 秒失败退避。本轮补齐长期运行合同：

- 多小时运行不能因浮点累计或逐周期丢弃帧越界时间而持续向后漂移；
- 失败重试必须从失败完成点重新计时，而不是制造追赶式保存风暴；
- 调度数学必须可以脱离场景树、磁盘和 UI 进行确定性验证；
- 生产运行时仍只能有一个 pending、一个 saving 和一个保存事务；
- 所有新增状态继续保持瞬时，不进入 `world.json`。

## 审计前的问题

旧 `AutosaveRuntimeParticipant` 同时承担：

1. 生命周期与 Pause 观察；
2. 浮点活动时间累计；
3. 到期判断；
4. deferred flush；
5. 失败退避数学；
6. 手动保存去重；
7. 统计与领域事实。

每次活动时间越过保存周期时，保存成功会把 elapsed 直接清零。真实帧的越界通常不足 1 秒，但该时间会在每个周期被丢弃。长会话中，自动保存时间点会逐步向后漂移，而且无法用纯策略测试证明上限。

## 状态所有权

```text
AutosaveRuntimeParticipant
├─ 生命周期、Pause、Hub 信号与唯一 deferred flush
├─ 保存尝试/成功/失败统计
└─ AutosaveSchedulePolicy
   ├─ 固定点活动时间
   ├─ 单 pending 状态
   ├─ 有界帧越界 carry
   ├─ 失败重试剩余时间
   └─ 纯快照与严格投影
```

`AutosaveRuntimeParticipant` 仍是唯一运行时状态所有者。`AutosaveSchedulePolicy` 是纯 `RefCounted` 策略，不创建 Node、Timer、文件、线程或第二份保存历史。

## 固定点时间

调度状态使用整数微秒：

```text
interval_microseconds
remaining_microseconds
fractional_microseconds
```

输入仍是 Godot 的浮点 `delta`，但每次转换时保留 `[-0.5, 0.5)` 微秒的有符号舍入余数。这样累计值等价于对总活动时间做一次微秒级舍入，而不是在每帧独立截断。

生产 `_process()` 仍把单帧 `delta` 限制为最多 1 秒，系统休眠、调试停顿或长卡顿不会直接跨越多个自动保存周期。

## 有界帧越界 carry

当一个生产帧跨过周期边界：

```text
remaining_before = 0.20 s
frame_delta       = 0.35 s
overshoot         = 0.15 s
```

本次只产生一个 due。成功保存后，下一个周期从：

```text
interval - 0.15 s
```

开始，而不是完整 interval，因此不会丢失这 0.15 秒活动时间。

约束：

- 单次 carry 最多 1 秒，与生产帧 delta 上限一致；
- 不在同一帧追赶多个检查点；
- 超出 1 秒的异常直接调用会被记录为 `discarded_overshoot_seconds`；
- 失败重试从失败完成点开始，清除旧 carry；
- 手动保存建立新的完整周期，清除旧 carry；
- 暂停发生在 pending 与 flush 之间时保留 carry，恢复后重新提交同一个到期事实。

### deferred 保存暂停边界

到期事实通过 deferred 保存执行，使同帧手动保存能够取消冗余写入。若到期后、deferred flush 前刚好进入 Pause：

- pending 必须保持为 true；
- 暂停期间不执行磁盘写入；
- 恢复时由 `pause_changed(false)` 重新安排同一个 flush；
- 多个 deferred 回调仍只允许第一个消费 pending；
- 若暂停菜单中的手动保存先成功，则 pending 被权威 `world_save_completed` 清除，恢复后不得补写第二次自动保存；
- 不允许通过“先消费 pending、再判断 Pause”丢失恢复后的第一帧活动时间。

## 状态转换

### 配置变化

周期改变时：

- 设置新的 interval；
- remaining 重置为完整周期；
- 清除 pending、carry 和失败压力；
- `configuration_count` 只在周期真实变化时增加。

### 自动保存成功

- 消费当前 carry；
- remaining = interval - carry；
- 清零连续失败与最近退避；
- 增加 schedule window sequence；
- 不影响全局保存来源计数和 12 条检查点历史。

### 自动保存失败

- 由原运行时选择 15 / 60 / 300 秒退避层级；
- 纯策略把 remaining 设置为本次 retry delay；
- 清除 carry，连续失败加一；
- 不清理世界，不发起立即重试。

### 手动保存成功

- 取消尚未 flush 的 pending；
- remaining 重置为完整周期；
- 清零失败压力；
- 不增加自动保存 attempt。

## 诊断

`get_snapshot()` 继续保留原字段，并新增有界标量：

- `schedule_schema_version`；
- `precision_unit_microseconds`；
- `current_carried_overshoot_seconds`；
- `carried_overshoot_count`；
- `carried_overshoot_total_seconds`；
- `max_carried_overshoot_seconds`；
- `discarded_overshoot_seconds`；
- `window_sequence`；
- `transition_count`。

F3 在连续失败时显示：

```text
自动保存：连续失败 3 次 · 5分00秒后重试
```

成功恢复后立即回到普通倒计时，不继续展示旧失败压力。

## 持久化边界

以下内容全部禁止进入 `world.json`：

```text
interval / remaining / fractional
pending / carry / overshoot
failure count / retry delay
window sequence / transition count
```

它们只存在于运行时 Snapshot、F3 投影和测试 JSON 中。世界、背包、机器、农业、探索等数据仍通过原权威保存事务写入。

## 长会话验收

### 纯策略

`autosave_long_session_endurance_regression.gd` 使用混合帧 delta 模拟 8 小时活动时间：

- 周期 5 分钟；
- 预期恰好 96 个检查点；
- 最终剩余时间回到完整 300 秒；
- carry 至少发生一次且最大不超过 1 秒；
- 生产大小 delta 不丢弃活动时间；
- 迭代次数具有硬上限。

### deferred Pause 竞态

`autosave_deferred_pause_race_regression.gd` 在同一调用栈中先形成 due、再切换 Pause：

- deferred flush 必须在暂停期间保持 pending；
- Resume 只执行一次保存并开始完整新周期；
- 第二轮 pending 可由暂停菜单手动保存取消；
- Resume 不得产生重复自动保存；
- attempt、success、manual reset 和未来倒计时必须精确。

### 生产 Headless

同一正式世界执行：

1. 八次真实自动保存；
2. 一次真实手动保存；
3. 三次真实保存失败；
4. 15 / 60 / 300 秒活动时间退避；
5. 恢复权威 SaveService；
6. 一次真实恢复保存；
7. 13 条检查点收敛为最近 12 条，dropped = 1；
8. 延迟期间的背包变化在恢复后完整持久化；
9. F3 从连续失败切换为恢复成功。

### 真实桌面

真实 `game.tscn` 重复同一旅程，并输出：

```text
autosave-long-session-backoff.png
autosave-long-session-recovered.png
autosave-long-session-report.json
stdout / stderr
```

截图分别证明三次失败后的 300 秒退避，以及成功恢复后的 12 条历史预算和最新自动保存事实。

## 合入条件

- 新静态合同；
- Godot 4.7 严格导入；
- 8 小时纯调度回归；
- deferred Pause 竞态与手动取消回归；
- 生产保存、失败与恢复回归；
- 原 bounded autosave、checkpoint timeline、world session、failed return、runtime health 和 runtime soak 相邻回归；
- 真实桌面双截图与 JSON；
- 权威全量 Runtime、完整桌面矩阵；
- Windows Release 实际导出、启动与退出资源检查。
