# Architecture Audit · 2026-07-22 · Iteration 25

## 范围

本轮从最新 `master` 审计：

- Chunk Streaming；
- `VoxelWorld` 加载、构建、卸载和取消流程；
- `BatchedVoxelWorld` 世界修改合并；
- `VoxelChunk` 生成与 Mesh 阶段；
- 玻璃板、栅栏、双格门和方向梯子的跨 Chunk 派生形状；
- 世界存档和运行诊断；
- 现有世界规模、农业规模、机器规模与 Windows Release 门禁。

前几轮已经证明：

```text
3,000+ 世界修改
2,048 作物
512 台机器
```

可以保持有界运行。下一项未闭环场景是：玩家在大型连接建筑区之间反复往返，造成同一批 Chunk 多次卸载和重新加载。

## 结论

当前世界卸载会完全释放 Chunk 的数值方块数组。玩家短时间返回刚离开的区域时，系统需要再次：

```text
生成 16,384 个方块
→ 应用稀疏覆盖
→ 生成完整视觉 Mesh
→ 生成完整碰撞 Mesh
```

Mesh 必须重建，因为连接形状和邻居可能已经变化；但数值方块生成在同一世界会话内通常是重复工作。

## 发现 1：最近 Chunk 重访重复生成完整体素数组

每个 Chunk：

```text
16 × 64 × 16 = 16,384 cells
```

`_unload_chunk()` 当前直接：

```text
remove_child
queue_free
chunks.erase
```

Chunk 的 `PackedInt32Array blocks` 随节点释放。

短时间返回同一区域时，`_load_chunk_synchronously()` 或 Streaming Builder 会重新执行 `GENERATING` 阶段，即使：

- 世界 Seed 没有变化；
- Profile 没有变化；
- 稀疏覆盖仍在内存；
- 该 Chunk 几秒前才完整生成过。

### 修复

为最近卸载 Chunk 保存有界的完整数值方块快照：

```text
卸载 READY/MESHING Chunk
→ capture PackedInt32Array
→ LRU 64 项

重新加载
→ 命中快照
→ 跳过 GENERATING
→ 直接 MESHING
```

## 发现 2：直接缓存 Mesh 会形成错误的事实来源

连接玻璃板和木栅栏的形状依赖当前东、西、南、北邻居。门和梯子的几何依赖持久方向方块 ID。Chunk 边界邻居可能在卸载期间变化。

如果缓存最终 Mesh：

```text
旧邻接 Mesh
+
新世界方块状态
```

可能不一致。

### 决策

只缓存数值方块数组，不缓存：

- Mesh RID；
- Collision Shape；
- connection mask；
- 组合盒；
- 透明面结果。

热加载继续完整执行 Mesh 阶段，连接形状从当前世界重新派生。

## 发现 3：缓存若无硬上限会变成第二个世界副本

所有卸载 Chunk 都永久保留，会让内存随探索范围增长。

### 修复

明确 LRU：

| 项目 | 上限 |
|---|---:|
| 快照数量 | 64 |
| 单快照体素 | 16,384 |
| 数值数组估算 | 4 MiB |
| 诊断坐标样本 | 16 |

第 65 项会驱逐最旧快照。缓存命中后该项离开缓存并重新成为活动 Chunk。

## 发现 4：卸载期间的方块修改会让快照陈旧

世界 API 允许对未加载 Chunk 调用 `set_block()`，权威状态会写入 `block_overrides`。

若缓存仍保留旧数组，下一次热加载可能把旧 cell 带入活动 Chunk。

### 修复

`CachedBatchedVoxelWorld.set_block()` 在权威写入成功后检查最近缓存：

```text
chunk coord
→ local cell index
→ numeric block ID
→ patch cached PackedInt32Array
```

缓存只是权威状态的镜像加速，不会覆盖 `block_overrides`。

## 发现 5：快速移动取消热构建时可能丢失快照收益

缓存命中后快照会从 LRU 中取出并进入 `CachedVoxelChunk`。如果玩家在 Mesh 完成前再次远离，Base Streaming 会取消该构建并释放节点。

### 修复

取消路径在释放前尝试重新捕获完整方块数组。只有数值数组已经完整的 MESHING/READY Chunk 才可重新进入缓存；仍在 GENERATING 的冷 Chunk 不缓存半成品。

## 发现 6：缓存不能成为平行存档领域

缓存内容可从：

```text
Generator + block_overrides
```

完全恢复。

保存它会增加：

- JSON 体积；
- 版本迁移；
- 数值 ID 兼容风险；
- 两个事实来源；
- 更新版本后的无效缓存问题。

### 决策

缓存、LRU 顺序和统计全部为当前世界会话瞬时状态。`clear_world()` 在继承清理前统一清空。

## 生产结构

```text
BatchedStarWorldGame
└─ CachedBatchedVoxelWorld
   ├─ BatchedVoxelWorld
   ├─ RecentChunkSnapshotCache
   └─ CachedVoxelChunk
```

没有修改公开 Scene、世界节点名、保存 Schema 或方块 numeric ID。

## 未采用方案

### 将 Chunk 快照写入磁盘

拒绝。世界存档已经保存 Seed 与稀疏覆盖；完整 Chunk 数组会显著放大磁盘和迁移成本。

### 缓存最终视觉和碰撞 Mesh

拒绝。跨 Chunk 邻接可能变化，GPU/Physics 资源生命周期也更复杂。

### 无限保留已访问 Chunk

拒绝。会让内存随探索距离增长。

### 每个 Chunk 启动独立后台任务

拒绝。会重新引入无界任务、退出清理和并发状态问题。

### 跳过热加载 Mesh 重建

拒绝。玻璃板、栅栏、门、梯子和透明面必须使用当前邻居重新计算。

## 验收要求

### 静态合同

- LRU 固定 64；
- 每项固定 16,384 cell；
- 数值数组总预算 4 MiB；
- Cached Chunk 直接进入 Mesh；
- 卸载、取消、修改和清理路径完整；
- Streaming Snapshot 暴露缓存统计；
- 无 Timer、无第二 Scheduler、无 serialize。

### 领域回归

- 第 65 项驱逐最旧项；
- 命中、未命中和 patch；
- 热加载跳过 16,384 个生成格；
- 缓存 block array 精确恢复；
- 世界清理归零；
- 存档无缓存字段。

### 真实桌面与可视化

- 3,000+ 混合连接结构修改；
- 至少 9 个 Chunk；
- 三轮真实 Streaming 卸载与返回；
- 所有目标 Chunk 命中快照；
- 卸载修改保留；
- 跨 Chunk 连接重新派生；
- 1024×576 截图和 JSON 报告；
- 正式保存、菜单和完整重载；
- Windows Release 实际导出和启动。

## 后续

完成后继续：

```text
连接结构 + 农业 + 机器 + 敌对 + 掉落混合长时 soak
→ 跨世界多轮内存/节点/缓存报告
→ 提取 GitHub Actions reusable workflow
```

只有真实报告表明 Mesh 阶段仍占主要成本时，再评估局部 Mesh Section；当前不提前引入更复杂的几何缓存。
