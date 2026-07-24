# 有界瞬时世界目录暂存合同

## 问题

世界目录已经拥有三层同步预算：

```text
主文件原子修复       8
完整 world.json 读取 32
catalog.json 写入    16
```

但读取预算大于写入预算时，已经解析却尚未获得 sidecar 写入槽位的世界，会在下一次刷新中再次解析完整 JSON。

96 个健康世界全部缺失目录时，旧收敛序列需要：

```text
32 + 32 + 32 + 32 + 32 + 16 = 176 次完整读取
```

其中只有 96 次对应不同世界，另外 **80 次是重复读取**。写盘已经有界，但跨刷新读取仍浪费 CPU、分配与 JSON 迁移成本。

## 决策

`SaveService` 增加最多 **64** 项的瞬时目录暂存：

```text
MAX_STAGED_CATALOG_ENTRIES := 64
```

每项只保存经过 `WorldCatalogPolicy.normalize_entry()` 的严格白名单目录，以及验证该目录仍对应当前 primary 所需的固定标量：

```text
entry
world_bytes
modified_unix
```

暂存项不包含玩家、背包、机器、农业、动物、探索、方块覆盖或完整 world Dictionary。

## 读取顺序

每个世界固定按以下顺序处理：

```text
有效 catalog.json
→ 有效瞬时目录暂存
→ 有界完整 world.json 读取
→ 固定大小占位行
```

只有在本轮仍有目录写入槽位，或瞬时暂存仍有容量时，系统才允许执行新的完整读取。这样不会解析一个既无法写入 sidecar、也无法跨刷新保留结果的世界。

## 一致性与失效

暂存条目在使用前比较：

```text
world.json 实际字节数
world.json 修改时间
目录 entry 的 world ID 与 save_bytes
```

任一证据不匹配时，条目立即失效并重新进入有界权威读取。显式 `save_world()` 成功后会用新 sidecar 或新暂存替换旧条目；删除世界会移除对应条目；恢复候选提升为 primary 时也会先清除旧条目。

诊断重置不会清空暂存，因为清零统计不应改变玩家下一次刷新行为。

## 失败语义

- sidecar 写入失败仍然只记录诊断，不会把成功的权威保存伪装成失败；
- 写入失败时，若暂存仍有容量，会保留严格白名单 entry 供下次重试；
- 暂存容量满且写入预算耗尽时，后续世界使用占位行，不继续解析完整 JSON；
- 暂存从不进入 `world.json`、`catalog.json` 或任何其他持久文件。

## 96 世界收敛

新序列为：

```text
扫描 1：读取 32，写入 16，暂存 16，占位 64
扫描 2：暂存命中 16，读取 32，写入 16，暂存 32，占位 32
扫描 3：暂存命中 32，读取 32，写入 16，暂存 48，占位 0
扫描 4：暂存命中 48，读取 0， 写入 16，暂存 32
扫描 5：暂存命中 32，读取 0， 写入 16，暂存 16
扫描 6：暂存命中 16，读取 0， 写入 16，暂存 0
扫描 7：96/96 sidecar 命中
```

完整读取总数从 **176** 降为恰好 **96**，消除 **80** 次重复解析；暂存峰值 48，低于 64 项硬上限。

## 可观测性

`get_catalog_diagnostics()` 提供固定大小证据：

```text
catalog_stage_capacity
staged_catalog_entry_count
staged_catalog_peak_count
stage_hit_count
last_stage_hit_count
stage_invalidation_count
last_stage_invalidation_count
authoritative_read_count
```

存档浏览器显示“目录待写”“暂存目录 N/64”和“暂存命中 N”。F3 继续区分主文件待修复、待读世界、暂存目录与待建 sidecar。

## 永久验收

- 40 世界失效测试：显式保存只移除自己的暂存项，外部修改会让一个旧暂存失效并重新读取；
- 96 世界规模测试：完整读取恰好 96 次，较旧序列减少 80 次；
- 真实 Windows 桌面：40 行始终可见、精确 metadata、F3 暂存证据、最终纯 sidecar 命中；
- 所有权威 `world.json` 在目录收敛前后逐字节不变；
- 总 Runtime、三轮 lifecycle soak、完整桌面矩阵和 Windows Release 实际导出/启动继续作为主分支合入条件。
