# Machine Base · 共享机器运行合同

## 目标

Machine Base 为当前和未来的世界机器提供统一运行、进度、状态、保存、诊断和玩家反馈合同。

它不是一个包含所有机器规则的万能 `MachineManager`。具体机器继续拥有自己的：

- 槽位语义；
- 配方规则；
- 燃料或能源规则；
- 完成事务；
- UI 只读 Snapshot。

共享层只负责：

```text
领域注册
→ 统一 Tick
→ 有界时间推进
→ 生命周期
→ 保存 Payload
→ 诊断
→ 批量完成反馈
```

## 生产结构

```text
GameplayServiceHub
└─ ServiceHubFeatureCoordinator
   ├─ machine_runtime
   │  ├─ MachineRuntimeScheduler
   │  └─ FurnaceService（furnace domain）
   ├─ husbandry_runtime
   ├─ ranch_runtime
   ├─ exploration_runtime
   └─ exploration_journal_rewards
```

`machine_runtime` 是根参与者，没有上游领域依赖。其他参与者仍保持原有依赖：

```text
ranch_runtime → husbandry_runtime
exploration_journal_rewards → exploration_runtime
```

正常阶段按注册/依赖顺序运行；`clear` 和 `shutdown` 逆序运行。

## MachineRuntimeScheduler

### 领域合同

机器领域必须实现：

```gdscript
func set_external_scheduler(value: bool) -> void
func advance_machine_runtime(seconds: float, emit_events: bool = true) -> Dictionary
func get_runtime_snapshot() -> Dictionary
```

注册结果显式返回成功或失败：

```text
invalid_domain_id
duplicate_domain
domain_capacity
invalid_domain
domain_contract
domain_already_registered
scheduler_shutdown
```

### 预算

```text
最大机器领域数          16
实时单帧最大推进        5 秒
手动/离线单次最大推进   4 小时
```

一个 Scheduler Tick 对每个已注册领域最多调用一次。Machine Base 不为每台机器创建 `Timer`。

### 暂停

Scheduler 使用：

```gdscript
Node.PROCESS_MODE_PAUSABLE
```

因此生产世界暂停时，所有注册机器同步停止；恢复后继续推进。

## Furnace 适配

`FurnaceService` 保留其生产 API、信号、节点路径和存档字段，新增 Machine Base 端口：

```gdscript
set_external_scheduler()
advance_machine_runtime()
get_runtime_snapshot()
shutdown()
```

### 兼容运行模式

直接实例化 Furnace 时：

```text
FurnaceService._process
→ 自己推进全部 Furnace 实例
```

位于生产 ServiceHub 时：

```text
MachineRuntimeScheduler
→ FurnaceService.advance_machine_runtime
```

生产 Furnace 会关闭自己的 `_process`，避免双重推进。旧领域测试仍可直接实例化 Furnace，不需要搭建完整 ServiceHub。

## 进度策略

`MachineProgressPolicy` 是纯策略，提供：

- 非有限时间拒绝；
- 进度比例；
- 下一份剩余时间；
- 可完成任务数；
- 待产出数量；
- 整批预计完成时间。

Furnace Snapshot 新增：

```text
queued_jobs
queued_output_count
remaining_seconds
estimated_total_seconds
runtime_managed
```

玩家在熔炉面板看到：

```text
当前配方：烧炼铁锭 · 队列 2 · 下一份 6.0 秒 · 全部 12.0 秒
```

## 完成反馈

领域层继续逐项发出：

```text
item_smelted(machine_id, recipe_id, output)
```

表现层在同一帧合并：

```text
多台机器完成
→ MachineCompletionPolicy
→ 一条“机器加工完成”消息
→ 一次 craft 音效
```

预算：

```text
待处理完成事件     128
消息可见产出类型     3
```

完整机器数、任务数、产物总数和类型数保留在结构化 Summary 中；只有玩家可见文本受到三类限制。

## 状态与迁移

生产世界继续使用：

```json
{
  "machines": {
    "version": 1,
    "saved_at_unix": 0,
    "furnaces": {}
  }
}
```

本轮不修改 Schema，不改 Furnace ID，也不移动任何方块 numeric ID。

`MachineStateMigration` 在领域反序列化前执行严格白名单：

```text
最大机器数          4096
机器 ID 最大长度      128
配方 ID 最大长度      128
槽位原始数量上限     4096
计时器上限           4 小时
```

迁移会拒绝：

- 空白、换行或过长 ID；
- 非 Dictionary 状态；
- 非有限计时；
- 非法槽位；
- 未知根字段和机器字段。

随后 Furnace 使用 ItemRegistry 再次规范化物品 ID 和实际堆叠上限。

## 保存所有权

机器领域不得调用：

```text
SaveService.save_world
FileAccess.open
```

MachineRuntimeParticipant 只执行：

```gdscript
payload["machines"] = furnace_service.serialize()
```

最终由现有 `SaveService` 将所有领域写入同一个原子世界事务。

## 清理合同

### 返回菜单 / 启动失败

```text
Scheduler deactivate
→ 取消待提交完成反馈
→ 清空 Furnace 运行状态
→ 保留服务节点供下一世界复用
```

### SceneTree 退出

```text
FeatureCoordinator.shutdown
→ MachineRuntimeParticipant.shutdown
→ FurnaceService.shutdown
→ MachineRuntimeScheduler.shutdown
```

`ToolProgressionServiceHub` 和 `CharacterProgressionServiceHub` 都必须继续调用 `super._exit_tree()`，确保退出链最终到达 Gameplay 根层。

## 诊断

Scheduler Snapshot：

```text
active
shutdown
domain_count
registered_domains
machine_count
tick_count
total_domain_advances
total_changed_machines
max_domains_per_tick
last_batch
domains
```

Furnace Runtime Snapshot：

```text
machine_count
processing_count
blocked_count
ready_count
runtime_tick_count
total_changed_machine_count
simulation_iteration_limit_hits
```

Participant Snapshot：

```text
pending_completion_count
dropped_completion_events
completion_batch_count
completed_job_count
completed_item_count
completion_audio_count
max_completions_in_batch
last_completion_summary
```

所有诊断均为瞬时状态，不进入世界存档。

## 扩展新机器

新增机器领域时必须：

1. 实现 MachineRuntimeScheduler 领域合同；
2. 使用纯策略计算进度与状态；
3. 不创建每机器 Timer；
4. 不自行写文件；
5. 定义严格状态迁移；
6. 提供只读 Snapshot；
7. 业务完成使用原子背包/槽位事务；
8. 声明离线推进硬上限；
9. 提供领域回归和真实桌面验收；
10. 通过完整 Windows Release。

不得直接把新机器规则继续加入 `FurnaceService`，也不得把 Scheduler 扩大为知道所有机器槽位和配方的万能服务。

## 测试门禁

### 静态合同

```text
tests/developer_b/validate_machine_base.ps1
```

验证架构、预算、Schema、UI ETA、无独立 Timer、无独立文件写入和 CI 接线。

### 领域回归

```text
tests/qa/machine_base_regression.gd
```

覆盖纯策略、恶意状态、双领域 Scheduler、双 Furnace、批量完成、保存和五参与者逆序清理。

### 真实桌面

```text
tests/qa/machine_base_desktop_acceptance.gd
```

使用生产 GameScene、真实 Furnace Overlay、两台 Furnace、共享 Scheduler、保存、菜单与完整重载。

### 专项工作流

```text
Machine Base quality gates
```

合并前还必须通过全量 Runtime、全部真实桌面矩阵和 Windows Release 实际导出启动。
