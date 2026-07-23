# 运行健康轻量数据源合同

## 目标

统一 F3 健康报告每 0.5 秒随既有 Runtime Telemetry 采样一次。显示层只需要容量、队列、错误计数和保存证据，不应先构造完整领域快照，再丢弃绝大多数字段。

本合同要求高数量领域提供**专用轻量端口**：

```gdscript
func get_health_snapshot() -> Dictionary
```

该端口只返回固定标量或固定大小的小字典，不遍历 UI、不修改领域状态、不进入存档。

## 机器领域

`MachineRuntimeScheduler.get_health_snapshot()` 最多读取 16 个机器领域。生产领域为：

- ScalableFurnaceService；
- ScalableStonecutterService；
- ScalableMachineAutomationService。

三个领域都必须提供 O(1) 标量快照。调度器汇总：

```text
domain_count / domain_limit
machine_count
active_machine_count
tracked_machine_count
tick_count
fallback_domain_count
```

健康采样禁止复制：

- `domains`；
- `registered_domains`；
- `last_batch`；
- `domain_summaries`；
- 逐机器状态或 ID 数组。

生产组合必须保持 **0 fallback**。旧扩展若只有 `get_runtime_snapshot()`，调度器仍允许兼容 fallback，但每次使用都必须被计数，不能静默退化。

## 农业领域

`ScalableAgricultureService` 维护成熟作物缓存：

- 反序列化和世界绑定时精确重建；
- 作物进入最终阶段时递增；
- 成熟收获时递减；
- 非法覆盖被移除时重新校准；
- clear/shutdown 时归零。

`get_health_snapshot()` 只返回：

```text
crop_count
mature_crop_count
soil_count
atomic_harvest_rejection_count
world_mutation_batch.rejection_count
world_mutation_batch.unsupported_count
```

健康采样不构造 `crop_counts`、`last_atomic_harvest`、`soil_refresh_cache` 或逐位置状态。

## 聚合选择

`RuntimeHealthReportService` 对机器和农业按顺序选择：

```text
机器：get_health_snapshot → get_snapshot
农业：get_health_snapshot → get_runtime_snapshot
```

其余来源继续使用各自既有有界端口。每份报告额外记录固定大小的：

```text
source_methods
preferred_source_count
fallback_source_count
unavailable_source_count
```

生产桌面验收必须证明：

```text
machines = get_health_snapshot
agriculture = get_health_snapshot
fallback_source_count = 0
unavailable_source_count = 0
```

## 测试合同

永久回归使用调用计数验证：

- 聚合器调用轻量方法各一次；
- 机器 `get_snapshot()` 和农业 `get_runtime_snapshot()` 为零次；
- 4,096 台机器只通过标量计数汇总；
- legacy fallback 精确出现一次并进入诊断；
- 农业缓存经过反序列化、成熟信号、收获信号和 clear 后保持一致；
- JSON 中不出现重型 payload 标记。

真实 Windows 旅程继续执行正式保存、目录 sidecar 删除与自愈、F3 输入、截图和 JSON，并验证生产端口与 0 fallback。Windows Release 仍由权威总门禁导出并启动。
