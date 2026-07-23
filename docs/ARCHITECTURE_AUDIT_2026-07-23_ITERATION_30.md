# Architecture Audit · 2026-07-23 · Iteration 30

## 范围

本轮审计双格木门、方向梯子、跨 Chunk 世界修改、结构物品返回和生产生命周期。目标不是再增加一种结构方块，而是补齐现有结构在支撑变化后的真实完整性闭环，并证明大规模清理不会退化为全世界扫描、逐格重建或同一脏 Chunk 的重复重建。

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
- 完整基础旅程和优化验收入口都必须能独立解析。

### 7. 规则批处理不等于网格重建已经最优

第一版共享服务已把 384 个结构和 512 个依赖方块合并为一个结构修改批次，但真实 Windows 软件渲染证据仍显示：

```text
删除 384 个支撑       → 重建 32 个 Chunk
清理 512 个结构方块   → 再重建同一 32 个 Chunk
总 Flush               2
实际 Chunk 重建        64
总清理时间             约 15.95 秒
结构规则阶段           约 78 毫秒
```

真正瓶颈不是结构规则，而是外层支撑删除在依赖结构清理前过早关闭了世界重建事务。同一脏 Chunk 集合被完整重建两遍。

### 8. Soak 测试不能把异步清理等同于固定帧数

总 Runtime 首次执行出现一次 soak 波动，同一 SHA 重跑成功。审计发现测试在返回菜单后固定等待三个帧就立即检查节点数量；`queue_free()`、Chunk 释放和资源回收在不同 Runner 负载下不保证恰好三帧完成。

测试应保持原有节点、Chunk、引用、输入和 Pause 边界，但使用最多 60 帧的有界收敛等待。超时仍失败，不能通过无限等待隐藏泄漏。

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

### 世界 pre-flush 扩展点

`BatchedVoxelWorld.apply_block_mutations()` 在最外层修改完成、真正执行网格重建前同步发出：

```text
block_mutation_batch_pre_flush(reason, summary)
```

摘要只有请求、接受、改变、拒绝、截断、批次深度和脏 Chunk 数，不发布完整修改数组。

生产 `BatchedBlockStructureIntegrityService` 在这一边界消费候选并提交嵌套结构修改。由于外层批次仍然开启，嵌套修改只扩展同一个脏 Chunk 集合；最外层结束时统一执行一次网格 Flush。嵌套 pre-flush 会留下诊断，但 `_applying_cleanup` 阻止递归进入第二轮清理。

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

服务在 `attach_game` 绑定生产世界和可选 pre-flush 信号，在 `_begin_world` 清空并检查持久覆盖，在菜单和退出路径清理。角色/F3 Snapshot 只接收有界聚合诊断。

### 可验证的规模 fixture

`StructuralIntegrityScaleFixture` 是纯 `RefCounted` 测试策略：

- 生成 128 扇门、256 个方向梯子和 384 个唯一支撑；
- 以奇偶 Chunk 错位布局防止跨边界支撑覆盖相邻梯子；
- 返回目标坐标总数和冲突计数；
- 不拥有 SceneTree、文件、Timer 或产品状态。

`structural_integrity_desktop_import_regression.gd` 在领域层显式加载 fixture、完整基础旅程和单 Flush 验收入口。只有解析和资源路径均通过后，才启动真实桌面 Job。

### 有界生命周期收敛测试

`runtime_soak_regression.gd` 不再假设所有菜单清理恰好三帧结束。每轮返回菜单后最多等待 60 帧，直到以下条件同时成立：

- 世界停止且已加载 Chunk 为零；
- 自适应流式引用已释放；
- 输入恢复菜单上下文；
- SceneTree 与模拟服务均未暂停；
- 生物和瞬时掉落容器为空；
- 总节点数回到基线加 40 的既有预算。

任何条件超出窗口仍立即失败。

## 真实规模设计与结果

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
5. pre-flush 中清理 384 个结构和 512 个结构方块；
6. 最外层事务统一重建脏 Chunk；
7. 验证物品、候选、重建和耗时；
8. 原子保存、菜单清理、完整重载；
9. 背包填满后再清理 6 扇门和 10 个梯子；
10. 验证 16 件物品聚合为至多两个物理掉落节点；
11. 输出 1024×576 截图、JSON、stdout/stderr。

最终固定候选的真实 Windows Server 2025 / ANGLE 软件渲染证据：

```text
结构清理结果            384 / 384
结构方块删除            512 / 512
候选溢出                0
规则与事务耗时          66.449 ms
网格 Flush              1
实际 Chunk 重建         32
脏 Chunk 峰值           32
总清理时间              7.177 s
保存                    9.987 ms / 14,584 bytes
加载                    2.070 ms
满背包物理回退          16 items / 2 nodes
```

真实门禁要求：

- 支撑移除和结构清理共享一个世界网格 Flush；
- 结构规则阶段不超过 1 秒；
- Windows 软件渲染总清理时间不超过 12 秒；
- 实际重建、最后 Flush 和脏 Chunk 峰值均不超过 32；
- 不留下浮空半门或不可攀爬梯子；
- 控制结构保持完整；
- 返回物品总数精确且重载不重复；
- 候选队列不溢出；
- 瞬时状态不进入存档。

与第一版真实实现相比，网格 Flush 和实际 Chunk 重建均减少 50%，总耗时从约 15.95 秒降低到 7.177 秒，降低约 55%。

## 实现结果

新增：

```text
src/interaction/block_structure_integrity_policy.gd
src/interaction/block_structure_integrity_service.gd
src/interaction/batched_block_structure_integrity_service.gd
tests/qa/structural_integrity_regression.gd
tests/qa/structural_integrity_batched_regression.gd
tests/qa/world_mutation_pre_flush_regression.gd
tests/qa/support/structural_integrity_scale_fixture.gd
tests/qa/structural_integrity_desktop_import_regression.gd
tests/qa/structural_integrity_scale_desktop_acceptance.gd
tests/qa/structural_integrity_single_flush_desktop_acceptance.gd
tests/developer_b/validate_structural_integrity.ps1
tests/developer_b/validate_structural_single_flush.ps1
.github/workflows/structural-integrity-tests.yml
docs/BOUNDED_STRUCTURAL_INTEGRITY.md
docs/STRUCTURAL_SINGLE_FLUSH_OPTIMIZATION.md
```

升级：

```text
src/world/batched_voxel_world.gd
src/ui/tool_progression_service_hub.gd
tests/qa/runtime_soak_regression.gd
tests/run_all.ps1
docs/PRODUCT_ROADMAP.md
```

## 后续建议

完成结构完整性后，下一阶段不应立刻增加更多结构变体。优先把机器、农业、畜牧、牧场、危险、Chunk、掉落、目录和结构完整性诊断聚合到统一 F3 运行与保存健康报告，再基于真实瓶颈决定内容或自动化扩展。
