# 有界自动保存运行时合同

## 目标

《星的世界》原有保存入口包括 F5、暂停菜单中的“保存世界”和“保存并返回主菜单”。这些入口使用同一个原子 `SaveService.save_world()` 事务，但长时间游玩期间没有周期性检查点。一旦应用、系统或设备异常退出，玩家可能丢失自上次手动保存以来的较长进度。

本合同增加一个**有界自动保存运行时**，并保持以下原则：

- 只复用现有权威保存事务；
- 只统计未暂停的活动时间；
- 不为机器、农业或其他领域创建独立 Timer；
- 手动保存与自动保存共享同一倒计时；
- 失败重试有硬上限和可观察证据；
- 多小时运行不因帧边界累计漂移；
- 调度游标、计数与失败状态不进入世界存档；
- 玩家可以在设置中关闭自动保存。

## 所有权

```text
GameSettingsPolicy
  └─ autosave_minutes = 0 / 2 / 5 / 10 / 15
       └─ AutosaveRuntimeParticipant
            ├─ 观察 SimulationPauseService
            ├─ 观察 world_save_completed / settings_applied
            ├─ 到期后调用 GameplayServiceHub.save_current()
            ├─ 发出 autosave_completed 领域事实
            └─ 委托 AutosaveSchedulePolicy
                 ├─ 固定点活动时间
                 ├─ 单 pending
                 ├─ 有界帧越界 carry
                 └─ 失败重试剩余时间
```

`AutosaveRuntimeParticipant` 只拥有运行时组合、保存副作用和统计；真正的世界状态仍由背包、容器、机器、农业、畜牧、探索、世界和玩家等领域持有，最终通过 `GameplayServiceHub.save_current()` 汇总到同一原子事务。

`AutosaveSchedulePolicy` 是纯 `RefCounted`。它不创建 Node、Timer、线程、文件或第二份保存历史。

## 设置合同

`GameSettingsPolicy` 是设置默认值、白名单和范围校验的唯一来源。

```text
autosave_minutes:
  0   关闭
  2   每 2 分钟
  5   每 5 分钟（默认）
  10  每 10 分钟
  15  每 15 分钟
```

不支持的数值会映射到最近的允许值；距离相同时选择更低值。非有限数字、错误类型和未知字段不会进入持久设置。

设置页不得维护第二套默认值，也不得直接操作自动保存运行时。它只提交规范化的设置意图。

## 活动时间

自动保存按**活动时间**计时，而不是墙上时钟：

- 世界尚未进入 gameplay：不推进；
- 暂停菜单或死亡导致 `SceneTree.paused`：不推进；
- 世界开始失败、返回菜单或清理：停止并清空当前世界引用；
- 恢复游戏：从暂停前的值继续；
- 单帧可计入的 `delta` 最多 1 秒，长卡顿不会直接跨过完整保存周期。

普通背包、合成、机器、容器和探索日志覆盖层不会暂停世界模拟，因此仍属于活动世界时间。

## 固定点调度与长期无漂移

活动时间在纯策略中转换为整数微秒：

```text
interval_microseconds
remaining_microseconds
fractional_microseconds
```

`fractional_microseconds` 保留 `[-0.5, 0.5)` 微秒的有符号舍入余数。累计结果等价于对总活动时间统一舍入，而不是逐帧截断。

当一个正常生产帧越过周期边界时：

- 本帧仍只产生一个 due；
- 超出边界的活动时间最多保留 1 秒；
- 自动保存成功后，下一个窗口从 `interval - carry` 开始；
- 不执行 while 追赶，不在一帧内连续写盘；
- 巨型测试 delta 超出 1 秒的部分进入 `discarded_overshoot_seconds` 诊断。

因此 5 分钟周期的 8 小时混合帧模拟会产生恰好 96 次检查点，最终下次倒计时回到完整 300 秒。

详细合同见 [AUTOSAVE_LONG_SESSION_SCHEDULING.md](AUTOSAVE_LONG_SESSION_SCHEDULING.md)。

## 保存去重

到期时运行时只设置一个 `pending` 标记，并通过一次 deferred flush 调用：

```text
GameplayServiceHub.save_current()
```

在 deferred flush 执行前发生手动保存时，`world_save_completed` 会：

- 清除 pending；
- 建立一个新的完整自动保存周期；
- 清除连续失败压力；
- 取消该次冗余自动保存。

自动保存自己成功时也会收到同一 signal，但 `_saving` 标记避免把它误计为手动保存，并允许纯策略消费帧越界 carry。

任何时刻都不允许并发保存或排队多个自动保存任务。

## 失败与分级退避

自动保存失败不会清理世界、不会假装成功，也不会立即每帧重试。

连续失败使用活动时间退避：

```text
第 1 次失败：15 秒
第 2 次失败：60 秒
第 3 次及以后：300 秒
```

即 **15 / 60 / 300** 秒。若用户配置的自动保存周期更短，则重试时间裁剪到该周期。

失败从保存完成点建立新的 retry window，并清除旧的帧越界 carry。成功保存或成功手动保存会清零连续失败次数。

失败事实由组合层转换为 Toast；F3 同时持续显示：

```text
自动保存：连续失败 N 次 · X后重试
```

恢复成功后立即回到正常倒计时。

## 生命周期依赖

自动保存是第七个显式 `FeatureLifecycle` 参与者，并依赖：

```text
machine_runtime
agriculture_runtime
husbandry_runtime
ranch_runtime
exploration_runtime
exploration_journal_rewards
```

它最后注册，因此：

- 正向 `begin / attach / activate / save` 时，所有玩法域已就绪；
- 反向 `clear / shutdown` 时，自动保存第一个停机；
- 世界清理过程中不会再启动检查点。

## 持久化边界

自动保存的以下信息只用于会话诊断：

- interval / elapsed / next / remaining；
- pending / saving / paused / active；
- due / attempt / success / failure / retry；
- consecutive failure 和最近退避；
- carry 次数、总量、最大值与 discarded；
- schedule window / transition；
- 最近世界、耗时和完成时间。

它们通过 `snapshot["autosave"]` 暴露，但**不进入世界存档**。`save_into()` 是显式 no-op，`world.json` 仍只保存实际玩法状态。

## 玩家反馈

运行时只发出：

```text
autosave_completed(success, snapshot)
```

组合层负责展示：

- 成功：`世界已自动保存`；
- 失败：`自动存档失败，将在活动时间 N 秒后重试`。

因此领域服务不依赖 HUD、Toast、GameUI 或具体字体样式。

## 相邻修复：最终保存失败

返回主菜单必须先保存。若最终保存失败，玩家仍处于当前世界。

`RuntimeHealthServiceHub` 只能在 `super.return_to_menu()` 确认 `current_world_id` 已清空后解除世界引用；否则 F3 必须继续观察玩家仍在使用的世界，并显示保存失败证据。

## 永久测试

### 基础领域与集成

`tests/qa/bounded_autosave_runtime_regression.gd` 覆盖：

- 设置白名单、范围和最近允许值；
- 活动时间到期；
- Pause 不推进；
- 手动保存取消 pending；
- 无关设置不重置倒计时；
- 周期变化重新开始窗口；
- 15 / 60 / 300 秒退避；
- 成功恢复清零失败压力；
- 自动保存不写入 payload；
- 正式 ServiceHub 的第七参与者、真实保存和玩家反馈。

`tests/qa/runtime_health_failed_return_regression.gd` 覆盖：

- 最终保存失败后世界身份不清空；
- Runtime Health 仍保持 world attached；
- 保存失败进入健康证据；
- 后续成功返回后才解除世界引用。

### 长会话领域与生产集成

`tests/qa/autosave_long_session_endurance_regression.gd` 覆盖：

- 严格状态投影与 15 分钟硬上限；
- 帧越界 carry；
- 巨型 delta 不触发追赶风暴；
- 8 小时混合帧、5 分钟周期、精确 96 次检查点；
- 八次真实自动保存与一次真实手动保存；
- 三次真实失败、15/60/300 秒退避和真实恢复；
- 13 条事件收敛为 12 条、dropped = 1；
- 失败期间积累的背包变化在恢复后完整持久化；
- F3 从失败退避切换为恢复成功；
- 所有调度字段保持瞬时。

### 真实桌面

`tests/qa/bounded_autosave_desktop_acceptance.gd` 验证设置、Pause、一次真实自动保存、持久化和成功提示。

`tests/qa/autosave_long_session_desktop_acceptance.gd` 使用正式 `game.tscn`：

1. 连续执行八次生产自动保存；
2. 通过真实 Escape 和暂停菜单按钮执行一次手动保存；
3. 注入三次生产保存失败；
4. 验证 300 秒退避 F3；
5. 保存失败截图；
6. 恢复权威 SaveService；
7. 验证第 13 个事件精确淘汰一条历史；
8. 验证延迟变化持久化；
9. 保存恢复截图、JSON、stdout 和 stderr；
10. 返回菜单、清理临时世界并通过资源泄漏检查。

### CI 与发行

`.github/workflows/bounded-autosave-tests.yml` 保留基础自动保存门禁。

`.github/workflows/autosave-long-session-tests.yml` 额外执行：

- 固定点策略静态合同；
- 8 小时纯策略回归；
- 生产多次保存、失败和恢复；
- 原自动保存、时间线、世界会话、失败返回、运行健康和 Runtime Soak；
- 真实桌面双截图和 JSON Artifact。

最终合入还必须通过仓库权威总 Runtime、完整桌面矩阵和 **Windows Release** 实际导出、启动与退出资源门禁。
