# Architecture Audit · 2026-07-23 · Iteration 30

## 范围

本轮审计双格木门、方向梯子、跨 Chunk 世界修改、结构物品返回和生产生命周期。目标不是再增加一种结构方块，而是补齐现有结构在支撑变化后的真实完整性闭环，并证明大规模清理不会退化为全世界扫描或逐格重建。

## 审计发现

### 1. 放置验证不是长期完整性

木门放置时会检查下方实体支撑，梯子放置时会检查背墙；但成功放置后没有任何服务继续拥有支撑关系。

当玩家、农业、测试或批量世界修改随后移除支撑时：

- 门的下半和上半仍保留；
- 梯子仍是可瞄准方块，但攀爬策略因为没有支撑而拒绝接触；
- 旧世界可永久保存这些残片；
- 玩家只能逐个手动寻找并拆除。

这让视觉、碰撞、攀爬与世界状态产生不一致。

### 2. 直接在 `set_block()` 中递归检查会放大成本

最直接的实现是在每次世界写入后立即递归检查邻居，但它会产生：

```text
一次支撑修改
→ 多次邻居检查
→ 多次结构删除
→ 每格一次 Chunk 重建
→ 删除事件再次递归检查
```

对跨 Chunk 边界的门和梯子，这会把成本绑定到结构数量，而不是脏 Chunk 数量，也容易产生递归和重复掉落。

### 3. 门与梯子不能各自建立运行时

门和梯子读取不同纯策略，但支撑变化、候选去重、批量删除、物品返回、Pause、诊断和生命周期边界相同。分别创建 Timer 或 `_process` 会复制调度、存档边界和失败语义。

### 4. 自动清理必须无损

结构失效不是玩家主动采集，不能假设背包有空间。只调用 `InventoryService.add_item()` 而忽略剩余数量会静默吞掉物品；每个结构创建一个物理节点又会绕开已经建立的 128 掉落节点预算。

### 5. 旧世界需要按需修复

此前创建的世界可能已经包含孤立上半门、浮空门或无背墙梯子。只监听未来事件无法修复已有稀疏覆盖，但一次性扫描完整生成世界同样不可接受。

### 6. 规模测试本身也需要结构合同

第一版单元场地把梯子背墙放在门下半格上，导致测试自己覆盖目标结构；第一版桌面旅程又采用未被 Headless 提前加载的基类/子类组合，解析错误直到昂贵的 Windows Job 才出现。

这两次失败都不是通过放宽断言解决，而是沉淀为新的测试架构约束：

- 单元 fixture 必须断言门支撑、门上下半、梯子支撑和梯子坐标互不重叠；
- 大规模跨 Chunk 场地必须由纯策略生成并报告坐标冲突数；
- 桌面脚本必须在领域层通过 Headless 显式加载；
- 正式桌面旅程只保留一个独立入口，不依赖未执行基类的隐式解析。

## 决策

### 纯策略组合

新增 `BlockStructureIntegrityPolicy`，只组合现有合同：

```text
BlockDoorPolicy.is_valid_pair
BlockDoorPolicy.lower_position
BlockLadderPolicy.support_offset
BlockLadderPolicy.is_valid_support
```

每个变化格只产生自身和六个正交邻居，共七个候选。策略返回稳定结构键、需要清理的已有方块、规范掉落和支撑证据，不拥有节点、文件或计时器。

### 单一共享、可暂停运行时

新增 `BlockStructureIntegrityService`：

```text
block_changed
→ 候选坐标去重
→ 纯策略验证
→ 结构键与方块坐标去重
→ 一个 apply_block_mutations 批次
→ 背包 / 聚合物理掉落
```

硬预算：

```text
候选队列           65,536
每次候选检查        4,096
每次逻辑结构        1,024
每次方块修改        2,048
旧覆盖单次扫描      8,192
待交付物品类型          16
```

服务使用 `PROCESS_MODE_PAUSABLE`，队列为空时关闭 Process。内部删除事件由 `_applying_cleanup` 抑制，避免递归。

### 批处理世界修改

所有失效门和梯子先汇总到一个修改数组，再调用生产 `BatchedVoxelWorld.apply_block_mutations()`。因此跨 Chunk 清理只重建实际脏 Chunk，并继续提供 request、execution、coalesced、max dirty 和耗时证据。

### 规范、无损物品返回

逻辑结构只返回一次规范物品：

```text
一扇门   → oak_door ×1
一个梯子 → ladder ×1
```

先尝试背包；剩余数量按物品类型聚合为 `ItemPickup`，挂入现有 `CreatureSpawner`，由 `PickupStackCoordinator` 继续管理节点上限、合并、Pause 和寿命。即使 384 个结构同时失效，也不会创建 384 个新掉落节点。

### 生命周期

`ToolProgressionServiceHub` 新增稳定兼容端口和节点：

```text
structural_integrity_service
StructuralIntegrity
```

服务在 `attach_game` 绑定生产世界，在 `_begin_world` 清空并检查持久覆盖，在菜单和退出路径清理。角色/F3 Snapshot 只接收有界聚合诊断。

### 可验证的规模 fixture

`StructuralIntegrityScaleFixture` 是纯 `RefCounted` 测试策略：

- 生成 128 扇门、256 个方向梯子和 384 个唯一支撑；
- 以奇偶 Chunk 错位布局防止跨边界支撑覆盖相邻梯子；
- 返回目标坐标总数和冲突计数；
- 不拥有 SceneTree、文件、Timer 或产品状态。

`structural_integrity_desktop_import_regression.gd` 在领域层显式加载 fixture 与正式桌面脚本。只有解析和资源路径均通过后，才启动真实桌面 Job。

## 真实规模设计

真实 Windows 桌面旅程创建：

```text
128 扇门
256 个方向梯子
384 个独立支撑
512 个结构方块
```

结构分布在 4×4 Chunk 区域，门位于 Chunk 边界；梯子使用东、西、南、北四种朝向，并包含跨 Chunk 支撑。另有四扇门和四个梯子作为受支持控制组。

验收顺序：

1. 一个生产批次创建完整结构场地；
2. 等待事件队列验证所有结构仍有效；
3. 清空结构诊断并重置世界重建统计；
4. 一个生产批次移除 384 个支撑；
5. 共享运行时在一个 Flush 中清理 384 个结构和 512 个结构方块；
6. 验证物品、候选、重建和耗时；
7. 原子保存、菜单清理、完整重载；
8. 背包填满后再清理 6 扇门和 10 个梯子；
9. 验证 16 件物品聚合为至多两个物理掉落节点；
10. 输出 1024×576 截图、JSON、stdout/stderr。

真实门禁要求：

- 支撑移除和结构清理总共只有两个世界重建 Flush；
- 结构清理在 5 秒内完成；
- 不留下浮空半门或不可攀爬梯子；
- 控制结构保持完整；
- 返回物品总数精确且重载不重复；
- 候选队列不溢出；
- 世界重建数按 Chunk 数增长，不能接近 896 次方块变化；
- 瞬时状态不进入存档。

## 实现结果

新增：

```text
src/interaction/block_structure_integrity_policy.gd
src/interaction/block_structure_integrity_service.gd
tests/qa/structural_integrity_regression.gd
tests/qa/structural_integrity_batched_regression.gd
tests/qa/support/structural_integrity_scale_fixture.gd
tests/qa/structural_integrity_desktop_import_regression.gd
tests/qa/structural_integrity_scale_desktop_acceptance.gd
tests/developer_b/validate_structural_integrity.ps1
.github/workflows/structural-integrity-tests.yml
docs/BOUNDED_STRUCTURAL_INTEGRITY.md
```

升级：

```text
src/ui/tool_progression_service_hub.gd
tests/run_all.ps1
docs/PRODUCT_ROADMAP.md
```

## 后续建议

完成结构完整性后，下一阶段不应立刻增加更多结构变体。优先把机器、农业、畜牧、牧场、危险、Chunk、掉落、目录和结构完整性诊断聚合到统一 F3 运行与保存健康报告，再基于真实瓶颈决定内容或自动化扩展。
