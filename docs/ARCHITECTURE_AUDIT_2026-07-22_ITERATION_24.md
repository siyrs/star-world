# Architecture Audit · 2026-07-22 · Iteration 24

## 范围

本轮从最新 `master` 审计 Machine Runtime、Furnace、Stonecutter、相邻箱子自动化、完成反馈、生产 ServiceHub 组合、存档边界和现有 CI。

上一轮已经证明世界批量修改和 2,048 作物可以使用共享批次。路线图下一项是：

```text
多机器自动供料、加工、收货和离线恢复压测
```

## 结论

Machine Base 已经消除了每机器 Timer，但仍存在三个与实例数量相关的隐藏成本，以及一个真实统计正确性问题。

## 发现 1：共享 Scheduler 下仍然每帧完整扫描

生产 Scheduler 每帧调用：

```text
FurnaceService.advance_machine_runtime(delta)
StonecutterService.advance_machine_runtime(delta)
MachineAutomationService.advance_machine_runtime(delta)
```

Furnace 和 Stonecutter 的 `advance_time()` 都执行：

```gdscript
for machine_id in get_machine_ids():
```

而 `get_machine_ids()` 每次都会重新构造并排序所有 ID。

结果：

- 4096 台持久机器即使只有少数在工作，也会每帧读取全部状态；
- 空机器、无输入机器、无燃料 Furnace、输出阻塞机器重复进入 `_advance_machine()`；
- Machine Base 的单一 Scheduler 避免了 Node/Timer 数量爆炸，却没有让帧成本与活跃任务数量相关。

### 修复

建立事件维护的 `MachineActivityIndex`，并将生产领域推进步长设为 0.1 秒。

```text
机器槽位改变 / 完成 / 移除
→ 更新活跃索引

Scheduler frames
→ 累计到 100 ms
→ 只遍历活跃索引
```

手动或离线推进继续使用完整累计时间，不改变完成时间。

## 发现 2：运行摘要可能复制大量 changed ID

原 `advance_machine_runtime()` 返回：

```text
changed_machine_ids = 所有发生变化的机器
```

数千机器同批推进时，Scheduler 和诊断 Snapshot 会复制一个很大的字符串 Array。

### 修复

分离：

```text
changed_machine_count       精确
changed_machine_ids         最多 64 个样本
dropped_changed_machine_samples
```

领域信号和机器状态不受影响。

## 发现 3：自动化每新增一台机器都排序完整候选目录

旧 `MachineAutomationService._add_candidate()`：

```text
append
→ _candidate_order.sort()
```

世界恢复 2048 台机器时，相同增长中的 Array 会排序 2048 次。

### 修复

```text
候选事件
→ append / remove
→ dirty = true

真实自动化周期开始
→ dirty 时排序一次
```

round-robin 游标和既有 16 台/周期预算保持不变。

## 发现 4：MAX_PENDING_COMPLETIONS 同时截断业务和诊断

旧 Participant：

```gdscript
if _pending_completions.size() >= MAX_PENDING_COMPLETIONS:
    _dropped_completion_events += 1
    return
```

`MAX_PENDING_COMPLETIONS = 128` 本来用于防止消息层保存无限事件，但它也导致：

- `completed_job_count` 少算；
- `completed_item_count` 少算；
- 玩家摘要少算；
- 贡献机器和配方少算；
- 规模验收看不到真实产量。

### 修复

Participant 在事件到达时立即聚合：

```text
完整任务数
完整物品数
每种输出数量
唯一机器
唯一配方
机器类型
```

同时只保留最多 64 条完整事件作为诊断样本。

有效事件不会因为样本预算被标记为 dropped。

## 发现 5：实现选择必须位于正确的生命周期所有者

直接将 base Furnace/Stonecutter 改成复杂索引实现会扩大旧领域测试风险；另建新的机器存档或服务路径又会破坏兼容。

第一版尝试将替换逻辑放到最上层 `ScalableMachineServiceHub`，但真实全仓静态门禁立即暴露问题：公开 `service_hub.tscn → exploration_progression_service_hub.gd` 入口被改变，机器实现选择也反向落入探索继承层。

### 最终修复

公开 Scene 与七层继承入口恢复原样。内部替换下沉到真正的所有者：

```text
GameplayServiceHub
├─ 创建 ScalableFurnaceService
└─ 注册 ScalableMachineRuntimeParticipant

ScalableMachineRuntimeParticipant
├─ 创建 ScalableStonecutterService
├─ 创建 ScalableMachineAutomationService
├─ 创建原 MachineRuntimeScheduler
└─ 创建原 MachineInteractionRouter
```

因此机器实现由 Gameplay 根和 Machine Participant 负责，探索、牧场、畜牧和角色继承层不拥有机器内部类型。

以下全部保持：

```text
service_hub.tscn 的稳定脚本入口
七层公开继承
变量名
节点名
节点路径
UI setup 端口
MachineInteractionRouter
machines.version = 1
machines.furnaces
machines.stonecutters
```

base 类继续作为稳定兼容实现和纯领域测试入口。

## 未采用方案

### 每机器 Timer

拒绝。会重新引入数千 Node、暂停生命周期和离线恢复问题。

### 每帧全量扫描但降低 render FPS

拒绝。成本仍随持久机器数量增长，并会影响所有平台。

### 将所有机器拆成场景 Node

拒绝。当前机器是位置型轻状态，场景化会增加世界加载、存档和 Chunk 生命周期复杂度。

### 把完成事件全部保存在 Array

拒绝。业务计数应精确，但完整事件证据必须有界。

### 立即引入管道或电网

拒绝。先验证现有相邻箱子自动化在 512 台规模下的真实吞吐和延迟。

## 预算

| 项目 | 上限 |
|---|---:|
| 持久机器 | 4096 |
| 活跃索引 | 4096 |
| 运行步长 | 0.1 秒 |
| changed ID 样本 | 64 |
| 完成事件样本 | 64 |
| 完成机器 ID | 4096 |
| 完成配方 ID | 256 |
| 完成输出类型 | 64 |
| 完成机器类型 | 16 |
| 自动化机器/周期 | 16 |
| 自动化物品/周期 | 64 |
| 自动化事务尝试/周期 | 128 |

## 测试要求

### 静态合同

- Production Scene 必须保留原公开入口；
- Gameplay 根和 Machine Participant 必须选择规模化实现；
- 活跃索引上限 4096；
- 运行步长 0.1 秒；
- changed ID 和完成样本各 64；
- Candidate 添加不能直接排序完整目录；
- 运行索引和统计不得进入存档；
- 不允许新 Timer 或第二套 Scheduler。

### 领域回归

- 2048 Furnace 中只有 128 台被评估；
- 2048 Stonecutter 中只有 128 台被评估；
- 小 Delta 不触发领域扫描；
- 完成后活跃索引自动移除；
- 2048 自动化候选只排序一次；
- 512 完成事件精确生成 512 任务、768 件产物、64 个样本；
- Production ServiceHub 的公共端口全部指向规模化实现。

### 真实桌面与可视化

- 512 台机器进入生产世界；
- 256 台真实活跃任务；
- 上方箱子供料、共享 Scheduler 加工、下方箱子收货；
- 真实 Machine UI 显示图标和产出；
- 一条完成消息和一次音效；
- 截图、JSON 报告、stdout/stderr；
- 正式保存、加载、菜单和完整重载；
- Windows Release 实际导出和启动。

## 后续

如果真实报告显示：

- 16 台/周期成为明显延迟来源，优先考虑玩家附近权重或有界可配置预算；
- Container 事务占主导，评估容器内容索引；
- 活跃机器本身超过可接受规模，再评估分帧领域游标；
- 当前报告仍健康，则进入连接结构反复卸载/重载和混合长时 soak，而不是提前增加物流复杂度。
