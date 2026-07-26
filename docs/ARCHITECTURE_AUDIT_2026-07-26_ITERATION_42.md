# Architecture Audit · 2026-07-26 · Iteration 42

## 范围

本轮基于已合并的受保护删除、32 槽回收站管理、轻量目录自愈、统一运行健康和七类长期规模门禁，对长时间单人游玩中的保存可靠性、设置所有权、生命周期失败所有权和退出失败语义进行审计。

扫描范围包括：

- `src/save`、`src/settings`、`src/ui`、`src/core` 与诊断组合层；
- 正式 ServiceHub 继承链和 FeatureLifecycle；
- 设置页、F5、暂停菜单和返回主菜单保存路径；
- 领域、集成、真实桌面、CI 与发行测试；
- 路线图、测试说明和已完成能力记录。

## 发现

### P0 · 长时间游玩没有周期性真实保存

项目已经拥有可靠的原子保存、备份恢复和目录自愈，但玩家只能通过 F5、暂停菜单或返回主菜单触发保存。

长时间游玩时，只要应用、系统或设备异常退出，最近一段机器加工、农业、畜牧、探索、背包和世界修改都可能丢失。

这不是 `SaveService` 可靠性问题，而是缺少单一调度入口。正确方案应复用 `GameplayServiceHub.save_current()`，而不是在每个领域复制 Timer 或各自写文件。

### P1 · 设置默认值存在重复所有权

`GameplayServiceHub` 与 `SettingsPanel` 各自维护一套设置默认值。新增设置时容易出现：

- 运行时认识新字段、UI 不认识；
- UI 提交时丢失其他字段；
- 非法值在不同入口得到不同结果；
- 测试直接发 signal 时绕过 UI 范围。

这种重复设置默认值会随功能扩展持续产生漂移。

### P1 · 自动保存雏形把领域与 UI 耦合

未合并分支中的早期实现直接从自动保存参与者调用 `_publish_character_message()`。

这让保存调度知道具体组合根的私有 UI 方法，违反“领域只发布事实、展示层决定表达”的边界。未来切换 HUD、静默模式或测试 Fake Hub 时都会被迫模拟 UI。

### P1 · 固定 30 秒重试会形成长期噪声

磁盘空间不足、权限错误或持续 I/O 故障通常不会在 30 秒内自动消失。固定周期重试会重复写磁盘并重复提示。

需要分级退避，并保持上限，避免无限指数增长或每帧重试。

### P1 · 无关设置可能重置保存倒计时

早期实现每次收到 `settings_applied` 都重新配置并把 elapsed 清零。玩家只修改音量或视距也会推迟下一次自动保存。

设置事件必须先规范化，并且只有自动保存周期真实变化时才开始新窗口。

### P1 · 返回主菜单前提前解除健康报告

旧 `RuntimeHealthServiceHub.return_to_menu()` 在调用权威返回流程前先 `detach_runtime()`。

但权威流程在最终保存失败时会拒绝离开世界。此时：

- 玩家仍处于原世界；
- `current_world_id` 仍存在；
- F3 却错误显示 world detached。

正确顺序应是先调用 `super.return_to_menu()`，再以世界身份是否清空作为成功事实。

### P1 · 生命周期拒绝路径泄漏候选节点

`ServiceHubFeatureCoordinator.register_participant()` 在 install 失败后会释放候选，但在以下更早失败路径中只返回错误：

- 空 ID；
- coordinator 已 shutdown；
- 重复 ID；
- 合同方法缺失；
- 自依赖循环；
- 依赖尚未安装。

正式组合根始终以 `ParticipantScript.new()` 传入候选，因此调用即意味着所有权转移。若这些候选没有挂到其他父节点，失败时不释放会形成真实 ObjectDB 泄漏，并让配置错误在退出资源门禁中表现为噪声。

### P2 · 生命周期组合需要显式扩展到第七个参与者

机器、农业、畜牧、牧场、探索和奖励已经统一进入 FeatureLifecycle。自动保存若游离在组合层外，就可能在世界清理期间继续运行。

应增加第七个生命周期参与者，并依赖所有持久玩法参与者，使反向清理时自动保存最先停机。

## 决策

### 1. 单一有界自动保存参与者

新增 `AutosaveRuntimeParticipant`：

- `PROCESS_MODE_ALWAYS`，但只统计未暂停活动时间；
- 单帧最多计入 1 秒；
- 最多一个 pending、一个 saving；
- 到期只调用正式 `save_current()`；
- 不读取或写入具体领域 Dictionary；
- 不创建第二个 Timer 和第二个存档域。

### 2. 统一设置策略

新增纯 `GameSettingsPolicy`，统一：

- 默认值；
- 类型和范围；
- 严格白名单；
- 自动保存 0/2/5/10/15 分钟；
- 不支持值到最近允许值的确定性映射。

SettingsPanel 和最终生产 ServiceHub 均使用同一策略。

### 3. 领域事实与展示分离

自动保存只发出：

```text
autosave_completed(success, snapshot)
```

最终 `ExplorationProgressionServiceHub` 将领域事实转换为：

- 成功提示；
- 带准确重试秒数的失败提示。

成功与失败共享 `autosave_status` 去重键，使最新状态替换旧状态，不排队展示已经过期的自动保存结果。

### 4. 分级退避

连续失败按活动时间使用：

```text
15 秒 → 60 秒 → 300 秒 → 300 秒……
```

周期更短时裁剪到周期。成功的自动保存或手动保存清零连续失败。

### 5. 手动保存去重

`world_save_completed` 是共享成功事实：

- 手动保存清零自动保存倒计时；
- 若已有 deferred autosave pending，则取消它；
- 自动保存自己的成功通过 `_saving` 区分，不重复计为 manual reset。

### 6. 第七个生命周期参与者

自动保存显式依赖六个持久玩法参与者，并最后注册。

反向清理顺序固定为：

```text
autosave_runtime
→ exploration_journal_rewards
→ exploration_runtime
→ ranch_runtime
→ husbandry_runtime
→ agriculture_runtime
→ machine_runtime
```

### 7. 退出健康语义修复

Runtime Health 只在权威返回流程实际清空 `current_world_id` 后解除世界引用。最终保存失败时继续观察原世界，并保留失败证据。

### 8. 生命周期失败所有权一致化

调用 `register_participant()` 传入的新建未挂树节点由协调器接管。

- 所有 pre-install 拒绝路径立即 `free()` 未挂树候选；
- install 失败在移出协调器后立即释放；
- 已有父节点的候选保持调用方所有权，不由协调器删除；
- 失败结果暴露 `participant_disposed`，便于测试和诊断。

这与原 install 失败的所有权语义保持一致，并把配置错误从资源泄漏转化为可观察、可恢复的注册失败。

## 测试设计

### 领域

- 设置白名单、非法值、最近允许周期；
- 59 秒不保存、60 秒恰好保存；
- Pause 不推进；
- 手动保存取消 pending；
- 无关设置不重置；
- 15/60/300 分级退避；
- 成功后失败压力归零；
- `save_into()` 不修改 payload。

### 生产集成

- 正式场景注册七个参与者；
- 自动保存依赖完整；
- 正式背包变化经真实保存事务写入并重新加载；
- world payload 不包含 autosave；
- 成功与失败领域事实转为玩家提示；
- 返回菜单和世界启动失败都先停自动保存；
- 缺失依赖、循环、重复和合同失败候选全部立即释放；
- 生产与测试退出均无 ObjectDB 泄漏。

### 相邻失败语义

- 将正式 ServiceHub 的保存端口替换为明确失败 Fixture；
- 调用真实 return-to-menu；
- 验证世界身份仍在、Runtime Health 仍 attached、失败证据可见；
- 恢复权威保存并成功返回后才 detach。

### 真实桌面

- 真实设置页与五个选项；
- 真实 Pause/Resume；
- 未保存背包变化；
- 一次真实自动保存；
- 重新读取 `world.json`；
- HUD 成功提示；
- 两张 1280×720 截图、JSON 与日志。

### CI 可诊断性

生命周期工作流为每个领域脚本独立保留 stdout/stderr，并在失败时仍上传 Artifact。脚本断言通过但日志包含 Parse Error、SCRIPT ERROR 或 ObjectDB 泄漏时，门禁仍然失败且可以直接定位具体脚本。

## 结论

本轮把已经可靠的“手动保存事务”推进为长期游玩可用的“周期性真实保存”闭环，同时消除重复设置默认值、领域/UI 耦合、固定重试噪声、最终保存失败后的健康报告失真以及生命周期拒绝候选泄漏。

自动保存没有复制任何玩法状态或文件写入逻辑，而是作为第七个生命周期参与者复用现有权威事务，并通过真实领域、生产集成、失败路径、资源释放和桌面可视化验收形成永久门禁。
