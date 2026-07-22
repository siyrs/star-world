# Agriculture Scale Batching

## 目标

农业运行时必须在保持逐作物状态、逐阶段信号、暂停语义和旧存档兼容的前提下，支持大农田恢复、离线推进和同批成熟，而不能把每个作物阶段变化放大为一次完整 Chunk 网格重建。

本合同建立三条共享边界：

```text
作物/土壤权威状态
        ↓
共享 VoxelWorld rebuild batch
        ↓
每个脏 Chunk 最多重建一次
```

```text
相邻耕地环境采样
        ↓
单次 refresh 内共享有界缓存
        ↓
重复水源位置只读取一次
```

```text
全部成熟事件
        ↓
精确按 crop_id 聚合
        ↓
最多保存 64 个位置样本
        ↓
一条消息 + 一次音效
```

## 生产组合

生产 `CharacterProgressionServiceHub` 安装：

```text
ScalableAgricultureRuntimeParticipant
├─ ScalableAgricultureService
│  └─ CachedSoilMoistureService
├─ AgricultureInteractionAdapter
└─ AgricultureNotificationPolicy
```

公共入口保持不变：

```text
hub.agriculture_service
hub.agriculture_interaction
hub.agriculture_runtime_participant
/AgricultureService
/AgricultureInteraction
```

## 世界修改批次

`ScalableAgricultureService` 在以下高数量路径打开共享世界批次：

- 世界绑定后的作物状态恢复；
- 土壤环境刷新；
- 离线成长；
- 正常 `advance_time()`；
- 手动湿润到期造成的耕地视觉变化。

每个作物仍然调用原有 `set_block()`，因此：

- 世界覆盖状态仍逐格更新；
- `block_changed` / `crop_stage_changed` 信号仍完整；
- 门、梯子、玻璃板和栅栏的邻接规则仍由世界层处理；
- 只有网格/碰撞重建被合并。

没有批次能力的测试世界或兼容世界继续使用即时更新，不阻断农业逻辑。

## 土壤采样缓存

水源检查的默认半径为：

```text
水平 4
垂直 1
单块土壤最多 242 个候选格
```

密集农田中的相邻土壤会反复读取大量相同体素。`CachedSoilMoistureService` 在一次 `refresh_all()` 或 `refresh_budgeted()` 内，用 `Vector3i → is_water` 缓存复用重叠读取。

硬预算：

| 项目 | 上限 |
|---|---:|
| 单次刷新缓存格数 | 65,536 |
| 持久土壤记录 | 4,096 |
| 每 Tick 环境刷新记录 | 既有策略上限 8 |
| 新增 Timer | 0 |
| 新增逐帧调度器 | 0 |

缓存达到 65,536 后继续直接读取世界，保证正确性，只降低缓存收益。缓存、命中率和最近刷新统计全部为瞬时诊断。

## 精确成熟汇总

旧实现最多保留 64 条成熟事件，超过部分被标记为 dropped，导致 2,048 块作物同批成熟时，玩家消息和 `matured_crop_total` 只能看到前 64 块。

新实现将“业务计数”和“位置样本”分离：

| 数据 | 规则 |
|---|---|
| 成熟总数 | 每条事件都计数，不丢失 |
| 每作物类型数量 | 最多显式跟踪 16 种 |
| 位置样本 | 最多 64 个 |
| 超出类型预算 | 合并到“其他作物”计数 |
| 玩家消息 | 每帧最多一条 |
| 音效 | 每帧最多一次 |

因此 2,048 块作物同批成熟时：

```text
matured_count = 2,048
sampled_position_count = 64
dropped_position_samples = 1,984
dropped_event_count = 0
```

## 存档边界

继续保存：

```text
agriculture.version
agriculture.crops
agriculture.soil_moisture
saved_at_unix
```

明确不保存：

```text
world_mutation_batch
soil_refresh_cache
sample_cache
pending_maturity_counts
maturity_position_samples
rebuild diagnostics
```

完整重载只恢复作物和土壤真实状态；不会重放成熟提示、缓存命中或批次计数。

## 真实规模证据

永久桌面验收建立 64×32 农田：

```text
2,048 块耕地
2,048 株小麦/胡萝卜/马铃薯
4,096 个初始世界修改
6,144 个真实阶段变化
```

验收记录：

- 作物恢复与环境刷新耗时；
- 土壤实际读取、缓存命中和缓存格数；
- 原始 Chunk 重建请求、实际执行和合并数量；
- 2,048 精确成熟汇总；
- 1024×576 可视化截图；
- 存档大小、保存和加载时间；
- 返回菜单后的完整 first-playable 重载时间。

## 不在本轮范围

- 不把作物成长改为全局异步任务；
- 不引入每农田 Node 或 Timer；
- 不保存环境查询缓存；
- 不改变现有成长时间、湿润倍率或收获产物；
- 不把位置样本限制误用为业务事件限制；
- 不引入远程农业自动化或全世界农田扫描。
