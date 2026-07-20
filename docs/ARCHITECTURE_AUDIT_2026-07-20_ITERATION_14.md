# 全仓架构审计 · 2026-07-20 · Iteration 14

## 审计范围

本轮基于：

```text
master@e6bcf7abf14ebc8f2f3197ebb7541df3487b7523
```

继续审查：

- Gameplay、Tool、Character、Repair、Husbandry、Ranch、Exploration 七层 ServiceHub；
- FurnaceService、Furnace UI、配方、燃料、世界交互和拆除保护；
- 新世界 Schema、旧世界加载、离线推进和保存所有权；
- ServiceHub FeatureCoordinator 的安装位置、依赖图和退出链；
- 全量 Runtime、领域、桌面与 Windows Release 门禁；
- 下一种机器加入前的扩展风险。

审计原则：

```text
先保护旧熔炉、旧存档和发行可靠性
→ 再抽共享合同
→ 最后增加新机器内容
```

## 总体结论

Furnace 已经不是简单 Demo：它具备输入、燃料、产出、持续进度、暂停、离线恢复、位置型 ID、拆除保护、UI、保存和真实桌面验收。

但这些能力都集中在 `FurnaceService`。若直接复制为 Crusher、Generator 或 AutoFarm，会出现多个独立：

```text
_process
Timer
离线推进
保存 Schema
完成音效
UI Snapshot
异常状态规范化
```

本轮因此不急于新增第二个机器方块，而是建立 Machine Base，把已成熟的能力抽成可验证基础，并让 Furnace 成为第一个兼容适配领域。

## 发现与处置

### P0 · 保持生产兼容

#### 1. 机器存档不能在基础重构中升级

当前稳定合同：

```json
{
  "machines": {
    "version": 1,
    "saved_at_unix": 0,
    "furnaces": {}
  }
}
```

风险：为了“通用化”直接改成新的统一数组或移动 Furnace 字段，会让已有世界迁移复杂化，并扩大本轮验证面。

处置：

- 保持 `machines.version = 1`；
- 保持 `machines.furnaces`；
- 保持 Furnace ID；
- 保持 `/Services/FurnaceService`；
- Machine Base 仅改变内部运行和生命周期；
- 新增严格迁移层，但不修改外部 Schema。

#### 2. 直接实例化 Furnace 的测试和生产 Hub 必须同时工作

风险：若 Furnace 完全依赖 Scheduler，已有领域测试和小型工具无法单独使用；若 Furnace 和 Scheduler 同时推进，则生产会双倍加工。

处置：

```text
standalone Furnace
→ FurnaceService._process

production ServiceHub
→ MachineRuntimeScheduler
→ FurnaceService.advance_machine_runtime
```

注册到 Scheduler 后，Furnace 显式关闭自己的 Process。

### P1 · 已完成架构优化

#### 3. FeatureCoordinator 位于 Husbandry 层

原结构：

```text
Gameplay
→ Tool
→ Character
→ Repair
→ Husbandry（创建 FeatureCoordinator）
→ Ranch
→ Exploration
```

风险：机器是 Gameplay 级能力，却只能在 Husbandry 之后注册，形成“机器依赖畜牧”的错误架构。

处置：Coordinator 下移到 Gameplay 根层，并注册：

```text
machine_runtime
→ husbandry_runtime
→ ranch_runtime
→ exploration_runtime
→ exploration_journal_rewards
```

现有领域依赖保持：

```text
ranch_runtime → husbandry_runtime
exploration_journal_rewards → exploration_runtime
```

清理顺序自动反转，Machine Runtime 最后清理。

#### 4. Furnace 没有可注册机器领域端口

旧 Furnace 只有自己的 `_process` 和业务 API。

处置：新增：

```gdscript
set_external_scheduler()
advance_machine_runtime()
get_runtime_snapshot()
shutdown()
```

Scheduler 不知道 Furnace 槽位和配方，只消费通用领域端口。

#### 5. 机器状态缺少独立前置白名单

旧 `deserialize()` 会规范化槽位，但根字段、ID、非有限时间、机器数量和原始槽位数量没有独立统一边界。

处置：新增 `MachineStateMigration`：

```text
最大机器数          4096
机器 ID 最大长度      128
配方 ID 最大长度      128
原始槽位数量上限     4096
运行计时上限          4 小时
```

迁移只保留版本、保存时间、Furnace Dictionary 和已知 Furnace 字段；随后 Furnace 再使用 ItemRegistry 做物品级规范化。

#### 6. 未来机器可能创建每实例 Timer

风险：大量机器产生大量 Timer、独立回调和不同暂停行为。

处置：新增单一 `MachineRuntimeScheduler`：

```text
一个 PAUSABLE Process
→ 最多 16 个机器领域
→ 每 Tick 每领域一次推进
→ 每领域内部批量推进实例
```

静态门禁拒绝 Machine Base 代码出现 `Timer.new()`。

#### 7. 每个烧制完成都会单独播放音效

多台 Furnace 同帧完成时，旧 ServiceHub `_on_item_smelted` 会逐项播放 craft 音效。

处置：

```text
N 条 item_smelted
→ 帧尾 MachineCompletionPolicy
→ 一条完成摘要
→ 一次 craft 音效
```

预算：

```text
待处理事件 128
可见产出类型 3
```

领域信号仍逐项保留，只有表现层合并。

#### 8. 玩家看不到队列和 ETA

旧面板只有进度条和燃料条，无法判断两份原料还要多久完成。

处置：Furnace Snapshot 和面板新增：

```text
queued_jobs
queued_output_count
remaining_seconds
estimated_total_seconds
```

玩家可见：

```text
当前配方：烧炼铁锭 · 队列 2 · 下一份 6.0 秒 · 全部 12.0 秒
```

### P1 · 测试架构问题

#### 9. 测试把参与者数量写死为四

新增根参与者后，畜牧、牧场和多敌对桌面流程虽然生产行为全部正确，但会因为：

```gdscript
participant_count == 4
```

失败。

处置：用例升级为：

- 参与者数量 5；
- `machine_runtime` 必须存在；
- `MachineRuntime` 节点路径稳定；
- 返回菜单必须停止 Scheduler；
- 完整重载必须重新激活 Scheduler；
- 启动失败必须停止 Scheduler；
- Character Snapshot 必须包含机器诊断。

这不是简单改数字，而是把测试从旧架构事实升级为新依赖合同。

#### 10. Furnace 测试中的配方数量已落后

生产数据包含九条 Furnace 配方，旧回归仍写七条。

处置：回归改为九条，并继续真实验证铁、金、输出阻塞、离线恢复、世界交互、UI、拆除保护和保存。

### P2 · 后续建议

#### 11. 下一种机器不应立刻引入复杂能源网络

Machine Base 稳定后，下一种机器应选择小型、可测试、能复用当前能力的闭环，例如：

```text
石材切割机
→ 单输入 / 单输出
→ 无燃料或简单能源端口
→ 明确配方
→ 世界位置保存
→ 共享 Scheduler
```

不建议下一步直接增加：

- 复杂管线；
- 大型电网；
- 多级物流；
- 万能自动化 Manager；
- 每台机器独立线程或 Timer。

#### 12. Agriculture 仍在继承层

Husbandry、Ranch、Exploration 和 Machine 已迁移为参与者，但 Agriculture、Equipment、Rest 和 Repair 仍通过继承覆盖世界生命周期。

建议按风险继续迁移：

```text
Agriculture runtime participant
→ Equipment / attribute participant
→ Repair participant
```

迁移前必须保持公共字段、节点路径、保存字段和真实桌面流程。

#### 13. CI 工作流重复安装 Godot

新增 Machine Base 后专项工作流继续增加。建议下一轮或后续提取 reusable workflow：

```text
strict import
→ static validators
→ domain scripts
→ optional desktop script
→ artifact upload
```

Windows Release 仍保持单一权威流程。

## 本轮交付

- `MachineRuntimeScheduler`；
- `MachineProgressPolicy`；
- `MachineStateMigration`；
- `MachineCompletionPolicy`；
- `MachineRuntimeParticipant`；
- Furnace 共享调度适配；
- Gameplay 根生命周期；
- 多 Furnace 批量完成反馈；
- Furnace 队列和 ETA；
- Machine Base 静态合同；
- Machine Base 领域回归；
- 真实双 Furnace 桌面验收；
- Machine Base 独立 CI；
- Machine Base 架构文档；
- 本轮全仓审计。

## 合并验收标准

只有以下全部成立才允许合并：

1. Godot 严格导入成功；
2. Machine Base 静态合同成功；
3. 共享 Scheduler、恶意状态和 Furnace Adapter 回归成功；
4. 旧 Furnace 回归成功；
5. 五参与者生命周期回归成功；
6. 真实双 Furnace Overlay、批量完成、保存和重载成功；
7. Husbandry、Ranch、Exploration 和 Multi-hostile 真实桌面无回归；
8. 全量 Runtime 成功；
9. 完整真实桌面矩阵成功；
10. Windows Release 实际导出、启动和证据上传成功；
11. 分支基于最新 `master` 且 `behind = 0`。
