# 结构完整性单 Flush 优化合同

## 背景

最初的结构完整性闭环在玩家批量移除支撑后分成两个独立世界修改事务：

```text
支撑删除批次
→ 立即重建脏 Chunk
→ 门 / 梯子完整性服务清理依赖结构
→ 再次重建同一批脏 Chunk
```

真实 Windows Server 2025、ANGLE / Microsoft Basic Render Driver 验收中，384 个结构、512 个结构方块和 32 个实际 Chunk 的结果为：

```text
世界 Flush             2
实际 Chunk 重建        64
结构规则与事务阶段     约 78 ms
总清理耗时             约 15.95 s
```

规则计算不是瓶颈；同一批 Chunk 被完整重建两次才是主要成本。

## 决策

`BatchedVoxelWorld.apply_block_mutations()` 在最外层批次结束、网格真正重建之前同步发出：

```text
block_mutation_batch_pre_flush(reason, summary)
```

`BatchedBlockStructureIntegrityService` 在该边界消费已经由 `block_changed` 收集的候选，并通过嵌套 `apply_block_mutations()` 提交门和梯子清理。

因为外层 `_rebuild_batch_depth` 仍为 1，嵌套修改只扩展同一个 `_dirty_rebuild_chunks` 集合，不执行独立网格 Flush。最外层事务结束时统一重建一次。

## 有界语义

pre-flush 扩展点必须满足：

- 同步执行，不创建 Timer 或后台线程；
- 每个 `apply_block_mutations()` 最多发出一次摘要；
- 摘要只包含计数、原因、批次深度和脏 Chunk 数，不复制完整修改数组；
- 嵌套结构清理继续受 4,096 项世界修改、1,024 个结构和 2,048 个结构方块预算约束；
- `_applying_cleanup` 阻止嵌套 pre-flush 递归进入第二次结构清理；
- 超出结构预算的剩余候选保留到后续帧，不通过无界递归完成；
- pre-flush 计数、候选和最近结果均为瞬时诊断，不进入存档。

## 真实优化结果

同一 384 结构 Windows 桌面旅程在单 Flush 实现后记录：

```text
世界 Flush             1
实际 Chunk 重建        32
结构规则与事务阶段     约 79 ms
总清理耗时             约 8.41 s
```

与优化前相比：

- Flush 数量减少 50%；
- 实际 Chunk 重建减少 50%；
- 总清理耗时减少约 47%；
- 门、梯子、物品返回、保存和完整重载结果保持一致。

## 永久验收边界

`structural_integrity_single_flush_desktop_acceptance.gd` 复用完整 384 结构桌面旅程，并替换已经失效的旧性能预期。

必须同时满足：

```text
384 个结构
512 个结构方块
一个世界网格 Flush
最多 32 个实际 Chunk 重建
结构规则阶段 <= 1 s
软件渲染总清理时间 <= 12 s
pre-flush 结构清理次数 = 1
候选溢出 = 0
物品损失 = 0
存档重复 = 0
```

12 秒是针对 GitHub Windows 软件渲染 Runner 的硬上限，不是产品目标帧时间。测试同时要求一次 Flush 和最多 32 个 Chunk，因此不能通过恢复双重重建或单纯放宽时间获得绿灯。

## 相邻回归

该合同与以下回归一起执行：

- 双格门状态、放置、开关和成对采集；
- 四方向梯子放置、支撑和攀爬；
- 世界修改批处理和嵌套批次；
- 物理掉落堆叠与共享运行时；
- 最近 Chunk 快照；
- 完整运行稳定性；
- 总 Runtime、桌面输入/UI 和 Windows Release。
