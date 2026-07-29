# Architecture Audit · 2026-07-29 · Iteration 50

## 审计范围

本轮继续执行产品路线图中的“长期规模与恢复”，审计：

- `AutosaveRuntimeParticipant` 的活动时间与失败退避；
- 保存检查点时间线和 F3；
- 多小时运行的漂移、去重与历史淘汰；
- 真实保存失败后的恢复；
- 到期、deferred flush 与 Pause 的同帧竞态；
- 现有 Runtime Soak、完整桌面和 Windows Release 门禁。

## 发现 1：调度数学与 I/O 生命周期耦合

原自动保存 Node 同时拥有 Pause、设置、浮点时间、到期判断、deferred flush、失败退避、手动去重、统计和 UI 事实。

单次功能是正确的，但存在两个长期维护问题：

- 无法脱离场景树和磁盘快速模拟多小时行为；
- 任何时间数学调整都会直接触碰保存 I/O 和生命周期代码。

这不符合“纯策略负责规则、Node 负责组合和副作用”的项目原则。

## 发现 2：每个周期丢弃不足一帧的活动时间

旧实现到期成功后直接执行：

```text
elapsed_active_seconds = 0
```

若某帧从周期前 0.2 秒推进 0.35 秒，则多出的 0.15 秒被丢弃。生产帧已限制为最多 1 秒，因此单次风险很小，但每个周期都可能发生。

在 5 分钟周期的 8 小时会话中共有 96 个窗口。最坏情况下可累计接近 96 秒的调度延后，而且原测试没有证明真实上限。

## 发现 3：浮点累计没有长期确定性证据

现有领域回归覆盖一次到期、Pause、手动去重和三档失败退避，但没有：

- 混合帧 delta；
- 多小时累计；
- 帧边界 overshoot；
- 12 条历史持续淘汰；
- 多次真实保存后连续失败再恢复；
- 恢复期间未保存变化的最终持久化。

“几次测试成功”不能证明长会话调度不会漂移。

## 发现 4：F3 对连续失败的语义不够直接

失败 Toast 会说明多久后重试，但 F3 普通自动保存行只显示倒计时。Toast 消失后，玩家无法从长期诊断面明确判断当前是在正常周期还是连续失败退避。

## 发现 5：deferred 保存暂停竞态

深度并发自审发现：到期后会先 `call_deferred("_flush_autosave")`。若 due 已形成，但 deferred 保存真正执行前刚好进入 Pause，原重构草案会先消费 pending，再通过 `_should_advance()` 发现暂停并返回。

结果不会永久漏存，因为 Resume 后 remaining 已为 0，下一帧会再次形成 due；但会：

- 丢失恢复后的第一帧活动时间；
- 多产生一次无意义的 due 转换；
- 破坏“正常生产帧不丢失活动时间”的新合同；
- 让暂停菜单手动保存与 pending 取消的顺序更难证明。

该窗口很窄且误差最多 1 秒，但既然已经被识别，就不能留在主分支。

## 决策

### 1. 提取纯固定点调度策略

新增 `AutosaveSchedulePolicy`：

- 整数微秒 interval / remaining；
- `[-0.5, 0.5)` 微秒舍入余数；
- 单 pending；
- 成功、失败、手动保存和配置变化的显式转换；
- 无 Node、Timer、FileAccess、DirAccess 或保存调用。

### 2. 保留有界帧越界 carry

生产 `_process()` 仍最多计入 1 秒。跨过周期边界时，只提交一次保存，但把最多 1 秒的 overshoot 带入下一个成功窗口。

因此：

- 不丢失正常生产帧活动时间；
- 不在同一帧追赶多个保存；
- 异常巨型直接调用超出的部分有显式 discarded 诊断。

### 3. 运行时只保留副作用和生命周期

`AutosaveRuntimeParticipant` 继续负责：

- Hub 与 Pause 连接；
- deferred flush；
- 唯一 `save_current()` 调用；
- attempt/success/failure 统计；
- `autosave_completed` 事实。

它不再直接编码 interval、remaining、carry 或 failure window 数学。

### 4. F3 显示连续失败上下文

连续失败期间显示：

```text
自动保存：连续失败 N 次 · X后重试
```

恢复成功后清零，不显示历史失败假象。

### 5. Pause 前不消费 pending

`_flush_autosave()` 必须按以下顺序执行：

```text
确认 pending
→ 确认当前仍可保存
→ 消费 pending
→ 调用唯一 save_current()
```

如果 Pause 已生效，则 pending 保留。`pause_changed(false)` 会重新 deferred 同一个 flush。多个 deferred 回调是幂等的：第一个成功消费 pending，后续回调立即退出。

若暂停菜单中的手动保存先成功，`world_save_completed` 会清除 pending；Resume 后不会补写冗余自动保存。

## 兼容性

- 设置仍为 0/2/5/10/15 分钟；
- 原 `get_snapshot()` 字段继续存在；
- 原 15/60/300 秒退避不变；
- 手动保存、返回菜单和自动保存仍调用同一权威事务；
- FeatureLifecycle 顺序不变；
- `world.json`、catalog、settings 和 trash Schema 不变；
- 旧世界无需迁移。

## 测试设计

### 纯策略

混合 16.67ms、33.33ms、125ms、250ms、500ms、900ms 和 1s 帧，累计 8 小时：

- 恰好 96 次 5 分钟检查点；
- 最终 next = 300 秒；
- carry 最大 1 秒；
- discarded = 0；
- 有硬迭代预算。

### deferred Pause 竞态

独立 Fake Hub/SimulationPauseService 在同一调用栈中：

1. 形成 due；
2. 立即 Pause；
3. 让 deferred flush 执行；
4. 证明 pending 仍在、save count 为 0；
5. Resume 并证明只保存一次；
6. 第二轮 due 后 Pause；
7. 执行手动保存并清除 pending；
8. Resume 证明不会重复自动保存。

### 正式 Headless

在正式 ServiceHub 中：

- 八次真实自动保存；
- 一次手动保存；
- 三次失败到 300 秒退避；
- 恢复真实 SaveService；
- 第 13 个检查点使 12 条历史精确淘汰 1 条；
- 失败期间的背包变化由恢复保存完整提交；
- F3 失败与恢复文本都验证。

### 真实桌面

正式 `game.tscn`：

- 使用真实 Escape 和暂停菜单保存按钮；
- F3 在失败与恢复两个阶段分别截图；
- 验证 1280×720 安全区域；
- JSON 保留运行时计数、时间线、文本、矩形和持久化结果；
- 完整清理临时世界与生成音频资源。

## 不采用的方案

### 每次到期 while 循环追赶

拒绝。应用恢复或测试巨型 delta 可能在一帧内连续写盘，破坏单 pending、帧预算和退出安全。

### 增加第二个 Timer

拒绝。现有 FeatureLifecycle 与 `_process()` 已提供唯一调度入口。

### 把调度游标写入 world.json

拒绝。自动保存调度是会话瞬时状态，持久化会制造无意义迁移和跨会话错误恢复。

### Pause 时消费 pending，Resume 后重新 due

拒绝。虽然只会延后一个恢复帧，但会重新引入可避免的活动时间丢失，并使手动保存去重依赖额外帧。

### 只增加一个更长的场景测试

拒绝。没有纯策略时，测试会慢、脆弱，并且难以覆盖 8 小时精确数学。

## 合入标准

只有以下全部成功才允许合入：

- 静态架构合同；
- Godot 4.7 严格导入；
- 8 小时纯策略；
- deferred Pause 竞态；
- 正式 Headless 保存/失败/恢复；
- 真实桌面双截图；
- 原自动保存、时间线、世界会话、失败返回、运行健康和 Runtime Soak；
- 仓库权威 Runtime；
- 完整桌面矩阵；
- Windows Release 导出、启动和退出资源检查。
