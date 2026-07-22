# Machine Scale Runtime

## 目标

机器系统继续保留玩家可理解的共享调度、位置型实例、原子输入输出与相邻箱子自动化，同时让大量持久机器不会把每个渲染帧都变成完整机器目录扫描。

本合同覆盖：

- Furnace 与 Stonecutter 运行索引；
- 100 ms 机器领域步长；
- 自动化候选目录排序；
- 大批完成反馈；
- 512 台真实机器的供料、加工、收货、保存和重载证据。

## 原问题

原 Machine Runtime 已经只有一个共享 Scheduler，但每个 Scheduler 帧仍会调用：

```text
FurnaceService.advance_time()
→ get_machine_ids()
→ 对全部实例排序
→ 对全部实例执行 _advance_machine()

StonecutterService.advance_time()
→ 同样完整排序与扫描
```

因此“没有每机器 Timer”并不等于“机器数量与帧成本解耦”。

另一个问题是完成反馈：

```text
MAX_PENDING_COMPLETIONS = 128
```

旧实现把前 128 条事件同时作为业务数据和诊断样本。若同一帧 512 个任务完成，后 384 项不会进入玩家摘要和累计统计。

自动化候选目录也在每次 `machine_changed` 时执行完整排序。世界重载或批量创建数千机器时，会重复排序同一个不断增长的 Array。

## 生产结构

公开 Scene 与七层继承入口保持原样：

```text
service_hub.tscn
└─ ExplorationProgressionServiceHub
   └─ ...
      └─ GameplayServiceHub
```

机器实现选择位于真正的领域所有者，而不是探索继承层：

```text
GameplayServiceHub
├─ ScalableFurnaceService
└─ ScalableMachineRuntimeParticipant
   ├─ ScalableStonecutterService
   ├─ ScalableMachineAutomationService
   ├─ MachineInteractionRouter
   ├─ MachineRuntimeScheduler
   └─ ScalableMachineCompletionPolicy

ScalableFurnaceService
└─ MachineActivityIndex

ScalableStonecutterService
└─ MachineActivityIndex
```

稳定入口继续为：

```text
hub.furnace_service
hub.stonecutter_service
hub.machine_runtime
hub.machine_interaction_router
hub.machine_automation_service
hub.machine_runtime_participant

/FurnaceService
/StonecutterService
/MachineRuntime
/MachineInteractionRouter
/MachineAutomationService
```

UI、交互、存档和旧测试不需要识别新的内部实现类。

## 活跃机器索引

每个生产加工领域维护一个 `MachineActivityIndex`。

Furnace 只有在以下条件成立时进入索引：

- 输入可解析为真实配方；
- 输出槽仍可接收产物；
- 已有燃烧时间，或燃料槽存在有效燃料。

Stonecutter 只有在以下条件成立时进入索引：

- 输入可解析为真实配方；
- 输出槽仍可接收产物。

索引由以下事件维护：

```text
机器创建
玩家或自动化插入/提取
机器完成任务
机器移除
世界反序列化
```

运行周期只遍历索引，不遍历全部持久机器。

硬预算：

| 项目 | 上限 |
|---|---:|
| 持久机器实例 | 4096 |
| 活跃索引 ID | 4096 |
| 单 ID 长度 | 128 |
| 单批 changed-machine ID 样本 | 64 |

完整 `changed_machine_count` 仍然精确；超过 64 的只是诊断 ID 样本。

## 100 ms 领域步长

共享 Scheduler 仍在 Godot Process 中运行，但 Furnace 和 Stonecutter 将帧 Delta 合并到：

```text
RUNTIME_STEP_SECONDS = 0.1
```

行为：

- 未累计到 0.1 秒时不扫描活跃索引；
- 达到步长时使用累计时间推进一次；
- 队列 ETA、燃料、产物和信号继续使用真实累计秒数；
- 手动/离线大步长仍可直接推进；
- 不创建 Timer；
- 不增加第二个 Scheduler。

该节流目标是减少解释器和 Dictionary 遍历开销，不改变配方完成时间。

## 自动化候选顺序

自动化继续由机器事件维护候选目录，并保持：

```text
每周期最多 16 台机器
每周期最多 64 件物品
单事务最多 8 件
每周期最多 256 个容器槽
每周期最多 128 次事务探测
```

新规则：

```text
machine_changed / machine_removed
→ O(1) 添加或移除候选
→ 标记顺序 dirty

下一次真实自动化周期
→ 最多排序一次
→ round-robin 继续运行
```

不会为每个批量恢复的机器重新排序完整目录。

## 精确完成聚合

生产 Participant 分离业务总量与诊断样本：

| 数据 | 规则 |
|---|---|
| 完成任务数 | 每条有效事件精确计数 |
| 产出物品总量 | 精确计数 |
| 贡献机器 | 最多跟踪 4096 个唯一 ID |
| 配方 | 最多跟踪 256 个唯一 ID |
| 产出类型 | 最多跟踪 64 种 |
| 机器类型 | 最多跟踪 16 种 |
| 完整事件样本 | 最多 64 条 |
| 玩家消息 | 每帧一条 |
| 完成音效 | 每帧一次 |
| 玩家消息可见产出类型 | 最多 3 种 |

超过 64 条事件时：

```text
completed_jobs        继续精确
item_total             继续精确
output_counts          继续聚合
sampled_event_count    固定最多 64
dropped_event_samples  增加
dropped_event_count    不增加
```

只有结构无效的领域事件才计入真正的 `dropped_event_count`。

## 存档边界

继续保存：

```text
machines.version = 1
machines.furnaces
machines.stonecutters
containers.version = 1
containers.containers
```

明确不保存：

```text
activity_index
runtime_step_accumulator
scheduler_call_count
evaluated_machine_count
candidate_order_dirty
candidate_sort_count
completion_event_samples
dropped_event_samples
```

完整重载会从持久机器槽位重建活跃索引和候选目录，不重放历史完成或自动化搬运。

## 真实规模验收

永久桌面场景包含：

```text
256 Furnace
256 Stonecutter
256 active jobs
512 top/bottom automation chests
```

验证：

1. 所有机器进入生产世界和稳定位置 ID；
2. 自动化候选事件不会每次排序；
3. 32 个有界周期覆盖 512 个候选；
4. 128 Furnace 和 128 Stonecutter 得到完整供料；
5. 256 个任务同批完成；
6. 完成摘要精确记录 256 个任务和 384 件产物；
7. 只保留 64 条完整事件样本；
8. 真实 Machine UI 显示产出图标和数量；
9. 后续有界周期将全部产物送入下方箱子；
10. 世界正式保存、JSON 加载、返回菜单和完整重载；
11. 机器、箱子和产物均只恢复一次；
12. 运行索引和统计不进入存档；
13. 输出 1024×576 截图和机器可读 JSON 报告。

## 何时继续扩大自动化

本轮不会引入管道、电网或跨 Chunk 物流。只有真实规模报告证明以下条件至少一项成立时才重新评估：

- 16 台/周期导致玩家可感知供料延迟；
- 相邻箱子布局无法表达高频生产链；
- 候选目录或容器事务成为明确主导成本；
- 具备 Chunk 生命周期、拓扑迁移和故障恢复方案。
