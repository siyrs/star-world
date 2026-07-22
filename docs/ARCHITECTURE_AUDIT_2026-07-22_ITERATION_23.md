# Architecture Audit · Iteration 23 · Agriculture Scale

日期：2026-07-22

## 背景

Iteration 22 已经通过 3,328 次真实世界修改证明，显式 `BatchedVoxelWorld` 可以把 2,660 个原始重建请求合并为 7 次实际 Chunk 重建。

下一步审计高数量真实调用方后，农业成为最明显的未接入路径。

## 发现一：成长循环仍逐作物即时重建

`AgricultureService.advance_time()` 遍历全部作物；每次阶段变化在 `_advance_crop()` 中调用：

```text
world.set_block(position, next_stage_block)
```

正常玩家的一块作物变化必须立即生效，但大 Delta、离线恢复或 2,048 块农田同批成长时，会在同一个 Chunk 内重复执行完整网格重建。

四阶段作物从播种到成熟会写入三次世界方块。2,048 株作物对应 6,144 次真实阶段写入。

## 发现二：世界绑定重复执行 refresh_all

旧绑定顺序：

```text
AgricultureService.attach_world
→ SoilMoistureService.attach_world
   → refresh_all
→ _sync_world_from_state
→ refresh_all
→ offline advance_time
```

同一批土壤在一次世界绑定中被完整环境刷新两次。大农田中，这既重复水源读取，也可能重复耕地视觉更新。

## 发现三：相邻土壤重复读取相同环境格

默认水源范围为水平 4、垂直 1。单块土壤最多检查 242 个候选体素。

密集农田中，相邻两块土壤的大部分候选格重叠。旧 `refresh_all()` 对每块土壤单独调用 `_has_nearby_water()`，没有单次刷新缓存。

理论最坏值：

```text
4,096 土壤 × 242 候选格
≈ 991,232 次世界读取
```

即使真实唯一格只有几万，也会被反复读取。

## 发现四：64 条成熟缓存错误限制了业务计数

`AgricultureRuntimeParticipant` 原有：

```text
MAX_PENDING_MATURITY_EVENTS = 64
```

超过 64 条后直接增加 `dropped_maturity_events` 并返回。

这不仅限制诊断位置，还丢失业务统计。2,048 株作物同批成熟时：

```text
真实成熟：2,048
玩家消息：64
matured_crop_total：64
```

位置样本可以有界，但成熟总数不能被样本预算截断。

## 发现五：跨世界成熟统计未明确归零

原 Participant 的 pending 队列会清空，但累计 maturity batch、成熟数量和音效计数没有在每次新世界绑定时统一归零。

这些统计不进入存档，但如果运行节点复用，会让新世界诊断继承上一世界计数。

## 决策

### 1. 新增可扩展生产服务

```text
ScalableAgricultureService
└─ CachedSoilMoistureService
```

保留原 Fertilizable Agriculture 的全部公共入口、收获事务、暂停和存档格式。

### 2. 绑定与成长接入共享世界批次

高数量路径使用：

```text
begin_chunk_rebuild_batch
→ 既有 set_block / signal
→ end_chunk_rebuild_batch
```

单次玩家交互仍走原即时路径。

### 3. attach 只做一次权威 refresh_all

新增 `attach_world_without_refresh()`，由 Agriculture Owner 统一执行：

```text
attach soil without refresh
→ sync crops
→ one refresh_all
→ offline advance
→ one outer world flush
```

### 4. 单次刷新使用有界重叠缓存

`CachedSoilMoistureService` 在 `refresh_all()` / `refresh_budgeted()` 内共享一个缓存：

```text
Vector3i candidate → is_water
```

上限 65,536 格。达到上限后继续直接读取，保证结果正确。

### 5. 成熟计数与位置样本分离

```text
每条成熟事件 → 精确 crop_id 数量
前 64 条 → 保存位置样本
超过 64 条 → 只增加 dropped_position_samples
```

最多显式跟踪 16 个作物类型，更多类型归入“其他作物”，总数仍准确。

### 6. 世界边界重置全部成熟诊断

新 Participant 在 `begin_world()` 与 `clear()` 中重置：

- pending counts；
- batch count；
- matured total；
- maturity audio；
- dropped samples；
- last summary。

## 保持不变

- 作物成长时间；
- 湿润和干燥倍率；
- 自动补种；
- 原子成熟收获；
- Agriculture Schema 2；
- 4,096 作物和 4,096 土壤上限；
- 六小时离线推进上限；
- Pause / Death 冻结语义；
- 现有公共节点路径与 Hub 字段。

## 验收要求

### 领域

- 128 株作物三阶段变化只重建一个已加载 Chunk 一次；
- 所有 384 个阶段信号保留；
- attach 只执行一次 refresh_all；
- overlapping soil samples 出现真实 cache hit；
- 2,048 条成熟事件全部计数；
- 仅保留 64 个位置样本；
- 一条消息和一次音效；
- 所有批次和缓存诊断不进入存档。

### 真实桌面

- 64×32、2,048 株混合作物；
- 4,096 个初始世界修改；
- 6,144 个成长阶段写入；
- 实际 Chunk 重建不超过唯一脏 Chunk；
- 1024×576 成熟农田截图；
- JSON 性能报告；
- 正式保存、加载、返回菜单和完整重载；
- 成熟提示不重放。

### 最终门禁

- Agriculture scale 专项；
- 原 Agriculture lifecycle；
- World mutation batching；
- 全量 Runtime；
- 真实桌面矩阵；
- Windows Release 实际导出与启动；
- 全部既有 GitHub Actions 成功后合并 `master`。

## 下一阶段

完成农业规模基线后继续：

1. 多机器供料、加工和收货规模报告；
2. 密集连接结构反复跨 Chunk 卸载/重载；
3. 多敌对、掉落和世界修改混合长时 soak；
4. 将重复专项步骤提取为 reusable workflow；
5. 只有真实报告显示单 Chunk 网格构建仍占主导时，再评估局部 Mesh Section。
