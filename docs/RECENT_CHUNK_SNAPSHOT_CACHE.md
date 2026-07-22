# Recent Chunk Snapshot Cache

## 玩家目标

玩家离开大型基地、农田或连接建筑区后再返回时，最近卸载的 Chunk 不应重新执行完整的体素生成阶段。

每个 Chunk 包含：

```text
16 × 64 × 16 = 16,384 个体素
```

新的最近 Chunk 快照缓存会保留有限数量的完整数值方块数组。再次加载同一 Chunk 时：

```text
最近卸载的完整方块数组
→ 跳过 GENERATING
→ 直接进入 MESHING
→ 发布最新视觉和碰撞
```

连接玻璃板、木栅栏、双格门和方向梯子仍然在 Mesh 阶段从当前世界邻居重新派生，不缓存连接掩码或几何。

## 生产结构

```text
BatchedStarWorldGame
└─ CachedBatchedVoxelWorld
   ├─ BatchedVoxelWorld
   │  └─ 有界世界修改与 Chunk 重建合并
   ├─ RecentChunkSnapshotCache
   └─ CachedVoxelChunk
```

原有公开入口保持：

```text
GameScene
/VoxelWorld
VoxelWorld 公共方法
BatchedVoxelWorld 批量修改端口
Streaming diagnostics
```

## 硬预算

| 项目 | 上限 |
|---|---:|
| 最近 Chunk 快照 | 64 |
| 每个快照体素 | 16,384 |
| 每体素估算 | 4 bytes |
| 最大数值方块数据 | 4 MiB |
| 诊断坐标样本 | 16 |
| 新 Timer | 0 |
| 新逐帧 Scheduler | 0 |
| 新存档字段 | 0 |

Dictionary、PackedArray 对象和运行时分配会产生少量额外开销；4 MiB 是方块数值数组的明确硬上限。

## LRU 生命周期

### 卸载

完整 READY 或 MESHING Chunk 被卸载时：

```text
capture_block_snapshot()
→ 复制 PackedInt32Array
→ 加入最近顺序
→ 超过 64 时驱逐最旧项
```

生成尚未完成的 Chunk 不会进入缓存。

### 重新加载

```text
请求 Chunk
→ take(coord)
→ 命中：CachedVoxelChunk.begin_initialize_from_snapshot()
→ 未命中：原始 begin_initialize()
```

命中项在 Chunk 重新进入活动世界后从缓存中移除；下一次卸载会保存新的最新数组。

### 构建取消

如果一个快照命中的 Chunk 在 Mesh 完成前又被取消，完整方块数组会重新放回缓存，避免快速往返丢失热数据。

## 卸载期间修改

世界状态仍以：

```text
block_overrides
+
Generator
```

为权威来源。

如果 `set_block()` 修改了一个仍在最近缓存中的卸载 Chunk：

```text
更新权威 block_overrides
→ 计算本地 cell index
→ 同步 patch 缓存 PackedInt32Array
```

因此下一次热加载不会用旧快照覆盖新修改。

## 连接形状正确性

缓存只保存数值方块 ID，不保存：

```text
connection_mask
pane/fence boxes
门碰撞状态副本
梯子接触状态
视觉 Mesh
碰撞 Shape
```

重新加载时，`VoxelChunk` 会继续读取当前世界邻居并重新计算：

- 玻璃板连接臂；
- 木栅栏横杆；
- 透明面消除；
- 门和梯子的方向几何；
- Chunk 边界连接。

## 存档边界

最近 Chunk 快照是纯进程内加速状态，**不进入存档**。

世界保存继续只包含：

```text
world.block_overrides
loaded_chunks 兼容信息
领域状态
```

明确禁止：

```text
recent_chunk_cache
cached_coord_samples
snapshot_hydrated
LRU order
cache counters
PackedInt32Array snapshot
```

返回菜单、世界启动失败、切换世界和场景退出都会清空快照与当前世界计数。

## 诊断

`get_streaming_stats().recent_chunk_cache` 提供：

```text
entry_count / capacity
estimated_bytes
store_count
hit_count / miss_count
eviction_count
patch_count
rejection_count
max_entries
last_coord / last_action
cached_coord_samples
```

这些数据用于 F3/测试/报告，不参与保存。

## 验收

### 领域回归

- 65 次存储只保留 64 项并驱逐最旧项；
- 命中与未命中计数；
- 卸载 Chunk 保存快照；
- 热加载跳过 16,384 个生成格；
- 卸载修改同步 patch；
- Streaming 诊断；
- 世界清理；
- 序列化中不存在缓存状态。

### 真实桌面

- 3,000+ 玻璃板、栅栏、门和梯子混合修改；
- 至少 9 个 Chunk；
- 三轮离开、卸载、返回和热加载；
- 每个目标 Chunk 都由快照恢复；
- 卸载修改保留；
- 跨 Chunk 玻璃板重新派生连接；
- 1024×576 可视化；
- 正式保存、加载、菜单和完整重载；
- 新世界会话没有旧缓存。
