# Architecture Audit · 2026-07-23 · Iteration 32

## 范围

本轮继续审计已经合入的统一运行与保存健康报告，重点不是新增显示内容，而是验证每 0.5 秒采样路径是否真正符合“只读、固定大小、轻量”的目标。

## 发现

### 1. 白名单输出不等于轻量输入

健康策略最终只输出 12 行，但原聚合器先调用：

```text
MachineRuntimeScheduler.get_snapshot()
ScalableAgricultureService.get_runtime_snapshot()
```

然后再由策略丢弃 `domains`、`last_batch`、`crop_counts` 等字段。这属于“构造完整快照后丢弃”的实现，输出有界但输入成本仍随机器和作物数量增长。

### 2. 机器快照重复构造领域字典

Machine scheduler 的完整快照会：

- 遍历最多 16 个领域；
- 调用每个领域的完整 runtime snapshot；
- 炉子和石材切割机进一步遍历机器状态；
- 复制 `domains` 与 `last_batch`。

F3 只需要机器总数和领域数，因此这条路径不合理。

### 3. 农业快照重复构造 crop_counts

农业本身已经每 0.5 秒推进成长。健康采样随后再次遍历作物，构造按作物类型分组的 `crop_counts`，同时复制原子收获和土壤缓存诊断。F3 只需要作物、成熟作物和土壤总数。

### 4. fallback 必须可见

直接删除旧 `get_snapshot()` / `get_runtime_snapshot()` 会破坏扩展兼容；静默回退又会让性能退化不可观测。正确合同是：

```text
优先轻量端口
→ 旧端口兼容 fallback
→ 每次 fallback 固定计数
→ 生产真实桌面要求 0 fallback
```

## 决策

### 机器 O(1) 端口

Scalable furnace、stonecutter 和 automation 从已有索引与容器大小读取标量，不解析配方、不复制机器 ID、不返回批次详情。

Scheduler 最多汇总 16 个标量来源。即使达到 4,096 台持久机器，健康采样成本仍与领域数相关，而不是与机器数相关。

### 农业成熟缓存

Scalable agriculture 维护单一成熟数量缓存。缓存不成为新的玩法状态所有者；权威作物状态仍是 `_crops`，缓存可在反序列化、世界绑定或异常删除后重建。

正常成长和收获通过既有领域信号增量更新，因此健康读取为 O(1)。

### 聚合器公开来源合同

RuntimeHealthReportService 记录 11 个固定来源实际使用的方法，并公开 preferred、fallback 和 unavailable 计数。该字典大小不会随世界内容增长。

## 永久验收

新增 headless 回归将重型方法实现为带调用计数的陷阱：只要聚合器或调度器调用重型端口，测试立即失败。测试还覆盖 4,096 机器汇总、legacy fallback 和农业缓存生命周期。

真实桌面旅程在正式 GameScene 中执行保存、目录自愈和 F3，并要求：

```text
machines source = get_health_snapshot
agriculture source = get_health_snapshot
fallback = 0
unavailable = 0
```

最终仍需通过总 Runtime、三轮 soak、完整桌面输入/UI 矩阵与 Windows Release。
