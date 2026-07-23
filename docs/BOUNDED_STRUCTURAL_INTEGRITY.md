# 有界结构完整性合同

## 目标

双格木门和贴墙梯子已经拥有方向、几何、碰撞、放置与交互合同，但原实现只在放置时验证支撑：

- 木门只检查下半格下面是否是实体方块；
- 梯子只检查背后的完整方块；
- 支撑之后被拆除时，世界不会主动修复结构。

结果可能留下浮空半门、仍可被瞄准但无法攀爬的梯子残片，或者需要玩家逐个寻找并手动清理。结构完整性运行时负责在不扫描全世界、不复制平行存档领域的前提下，自动清理这些失效结构并无损返回规范物品。

## 唯一状态来源

结构状态仍由现有方块 ID 与实时邻居唯一决定：

```text
BlockDoorPolicy
├─ 上下半
├─ 朝向
├─ 开关状态
└─ 成对合法性

BlockLadderPolicy
├─ 朝向
├─ 支撑偏移
└─ 支撑方块合法性
```

`BlockStructureIntegrityPolicy` 只组合上述纯策略，不保存门、梯子或支撑的第二份状态。

## 事件驱动候选

生产世界的 `block_changed` 是唯一增量入口。每个变化只检查：

```text
变化格
+ 上 / 下
+ 东 / 西 / 南 / 北
= 7 个候选格
```

这足以覆盖：

- 门地面支撑被移除；
- 门任意半部被外部修改；
- 梯子背墙被移除或替换；
- 结构本身被放置、恢复或删除。

候选按世界坐标去重，常规空闲状态不运行 `_process`，也没有 Timer。

## 有界共享运行时

`BlockStructureIntegrityService` 使用 `PROCESS_MODE_PAUSABLE`，仅在有待处理候选或待交付物品时启用共享循环。生产组合使用 `BatchedBlockStructureIntegrityService`，在保留同一公共合同的同时接入世界批次 pre-flush 边界。

硬边界：

| 边界 | 数量 |
|---|---:|
| 待处理候选总上限 | 65,536 |
| 每次 Flush 最多检查候选 | 4,096 |
| 每次 Flush 最多清理结构 | 1,024 |
| 每次 Flush 最多提交方块修改 | 2,048 |
| 世界启动单次旧覆盖扫描预算 | 8,192 |
| 待交付物品类型 | 16 |

门由两个方块组成，因此 1,024 个结构和 2,048 个修改是独立预算。达到任一预算后，剩余候选重新排队到后续帧，不会把大批清理退化为无限同步工作。

## 清理事务与单次网格 Flush

结构失效后，所有目标方块先汇总，再调用生产世界：

```text
apply_block_mutations(changes, "structural_integrity_cleanup")
```

当外层生产批次正在删除门地面或梯子背墙时，`BatchedVoxelWorld` 会在真正重建网格前同步发出：

```text
block_mutation_batch_pre_flush(reason, summary)
```

`BatchedBlockStructureIntegrityService` 在该边界消费已经由 `block_changed` 收集的候选，并通过一个嵌套 `apply_block_mutations()` 提交依赖结构清理。此时外层批次深度仍为 1，所以嵌套修改只扩展同一个脏 Chunk 集合，不独立重建网格；最外层事务结束时统一执行一次 Flush。

内部清理产生的 `block_changed` 和嵌套 pre-flush 事件由 `_applying_cleanup` 显式抑制，防止递归排队。世界不提供 pre-flush 信号时，基础服务仍可在后续有界帧中完成相同规则清理。

### 木门

- 支撑有效且上下半状态一致：保留；
- 支撑丢失：原子清理上下两半；
- 只有一半或上下状态不一致：清理现有残片；
- 每个逻辑门只返回 `oak_door ×1`。

### 梯子

- 编码方向对应完整实体支撑：保留；
- 背墙丢失或变成不支持梯子的部分形状：清理该梯子；
- 每个梯子返回 `ladder ×1`。

结构键和已声明方块坐标都会去重，因此同一个门被上下半和支撑事件同时命中时仍只返回一件物品。

## 无损物品交付

清理后的规范物品先尝试进入玩家背包：

```text
InventoryService.add_item
```

背包无法完全接收时，剩余数量按物品类型聚合为物理掉落：

```text
oak_door → 至多一个 ItemPickup
ladder   → 至多一个 ItemPickup
```

物理节点挂在现有 `CreatureSpawner` 下，自动进入共享 `PickupStackCoordinator`，继续受到 128 节点上限、合并、寿命、Pause 和资源复用合同保护。结构运行时不会建立第二套掉落调度器。

## 世界启动兼容修复

旧世界可能已经保存：

- 浮空门；
- 孤立上半门；
- 状态不一致的门对；
- 失去背墙的梯子。

世界开始后，运行时读取现有稀疏 `block_overrides`，只将其中的门和梯子加入候选队列。检查和清理仍通过同一有界运行时完成；正常支持结构保持不变。

## 生命周期与持久化

`ToolProgressionServiceHub` 拥有稳定节点：

```text
StructuralIntegrity
```

生命周期：

```text
_ready       → 创建服务
attach_game → 绑定 block_changed 与可选 pre-flush
_begin_world→ 清空瞬时状态并检查旧覆盖
return/menu → 断开世界、清空候选和诊断
_exit_tree  → 断开信号并 shutdown
```

候选队列、掉落积压、pre-flush 摘要、计数器、结构键、扫描游标和最近 Flush 均不进入存档。世界仍只持久化稀疏方块修改；结构完整性运行时不进入存档。

## 有界诊断

`get_snapshot()` 只返回聚合数据：

- 当前候选和待交付数量；
- 观察到的变化、去重、溢出和内部抑制计数；
- Flush、清理批次、门、梯子和删除方块总数；
- pre-flush 支持、信号次数、实际清理次数和最近摘要；
- 背包交付、物理掉落、掉落节点和积压溢出；
- 初始覆盖扫描与截断；
- 所有硬预算；
- 最近一次 Flush 的候选、结构、修改、耗时与世界重建结果。

诊断不复制完整世界、完整修改数组、方块覆盖或背包 Dictionary。

## 永久验收

领域回归覆盖：

- 七格候选唯一性；
- 开门状态和四向梯子支持；
- 门与梯子共享一个世界修改批次；
- 真实外层/嵌套世界批次只执行一次网格 Flush；
- 重复事件去重和嵌套 pre-flush 防递归；
- 孤立门上半安全清理且只返回一件门；
- 背包满时规范物品进入物理掉落；
- 旧覆盖扫描修复孤立梯子且保留有效门；
- 无平行存档和空闲 Process。

规模场地由纯 `StructuralIntegrityScaleFixture` 生成。它显式统计支撑与结构坐标冲突，并用奇偶 Chunk 错位布局防止跨边界支撑覆盖相邻梯子。该 fixture 不拥有 SceneTree、文件或计时器，可独立接受静态合同验证。

在启动昂贵的 Windows 桌面 Job 前，`structural_integrity_desktop_import_regression.gd` 会在 Headless 阶段显式加载规模 fixture、完整基础旅程和单 Flush 验收入口。测试脚本解析、类型或资源路径错误会在领域层提前失败，而不是到桌面 Runner 才暴露。

真实桌面验收使用正式 `GameScene`：

```text
128 扇门
+ 256 个梯子
= 384 个结构
= 512 个结构方块
```

结构分布在多个 16×16 Chunk，并包含跨 Chunk 支撑。用一个生产批次移除 384 个支撑后，必须满足：

- 没有浮空半门或梯子残片；
- 精确返回 128 扇门和 256 个梯子；
- 结构规则和事务阶段不超过 1 秒；
- GitHub Windows 软件渲染总清理时间不超过 12 秒；
- 世界网格 Flush 恰好 1 次；
- 实际 Chunk 重建、最后 Flush Chunk 数和脏 Chunk 峰值均不超过 32；
- pre-flush 信号 2 次、结构清理 1 次且没有递归；
- 保存、返回菜单和完整重载不重复物品；
- 满背包场景中 6 扇门和 10 个梯子聚合成至多两个物理掉落节点。

优化前后真实证据和性能边界见 [STRUCTURAL_SINGLE_FLUSH_OPTIMIZATION.md](STRUCTURAL_SINGLE_FLUSH_OPTIMIZATION.md)。最终还必须通过总 Runtime、长期 soak、完整桌面矩阵和 Windows Release 实际导出与启动。
