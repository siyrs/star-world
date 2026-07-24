# 有界权威世界读取合同

## 目标

世界列表拥有三层同步边界：

```text
主文件原子修复：每次最多 8
完整 world.json 读取：每次最多 32
catalog sidecar 重建：每次最多 16
```

这些预算分别限制昂贵恢复、完整 JSON 解析和派生文件写入。读取预算不能隐藏世界，写入预算也不能迫使系统重新解析已经读取的世界。

## 三层预算

```text
主文件修复预算       8
完整存档读取预算    32
目录 sidecar 写入   16
```

三者不能共用计数器：

- primary 修复可能写 `.recover`、位移损坏主文件并原子提升；
- 权威读取会解析和迁移完整世界 Dictionary；
- sidecar 重建只写严格白名单目录；
- 健康世界的完整读取不得消耗 primary 修复槽位；
- 读取预算耗尽时，不得继续解析完整世界；
- 写入预算耗尽时，准确目录 entry 可以进入有界瞬时暂存，而不是在下一次刷新中重复读取完整世界。

## 世界始终可见

读取预算不能隐藏第 33 个及后续世界。只要世界目录中存在 `world.json`、`.tmp` 或 `.bak` 候选，列表返回一个固定大小占位行：

```text
id                 = 世界目录名
name               = 世界目录名
map_id             = metadata_pending
save_bytes         = 当前可用候选字节数
authoritative_read_deferred = true
catalog_rebuild_deferred     = true
```

存档浏览器显示“世界信息待读取”。玩家仍可选择并点击继续；`load_world()` 是明确的单世界操作，不受列表读取预算限制，会走完整加载、恢复和迁移合同。

## 瞬时目录暂存

读取预算 32 大于写入预算 16。若不保留读取结果，96 个世界需要 176 次完整读取，其中 80 次重复解析已经读取过的世界。

生产路径增加最多 64 项的严格白名单暂存：

```text
catalog sidecar
→ 瞬时目录暂存
→ 有界完整读取
→ 占位行
```

暂存只包含规范化 catalog entry、权威文件字节数和修改时间，不包含完整 payload，也不进入存档。primary 字节数或修改时间变化时，旧暂存立即失效并重新进入有界读取。

详细合同见 [TRANSIENT_CATALOG_STAGING.md](TRANSIENT_CATALOG_STAGING.md)。

## 确定性收敛

世界 ID 按字符串升序扫描。96 个健康世界全部缺失 sidecar 时：

```text
第 1 次：命中 0， 读取 32，暂存 16，占位 64，写目录 16
第 2 次：命中 16，读取 32，暂存 32，占位 32，写目录 16
第 3 次：命中 32，读取 32，暂存 48，占位 0， 写目录 16
第 4 次：命中 48，读取 0， 暂存 32，写目录 16
第 5 次：命中 64，读取 0， 暂存 16，写目录 16
第 6 次：命中 80，读取 0， 暂存 0， 写目录 16
第 7 次：96/96 纯 sidecar 命中
```

完整读取总数恰好为 96，较旧序列减少 80 次。读取、暂存和写入各自按固定预算收敛，不会随机饥饿。

## 权威存档不变

列表读取、暂存和占位收敛期间：

- 不修改健康 `world.json`；
- 不覆盖 `.bak`；
- 不将占位 metadata 写入 sidecar；
- 不进入 backup recovery；
- 不把预算、占位行、暂存条目或诊断写入世界存档。

只有完整读取成功且 primary 已健康时，才允许使用真实白名单 entry 构建 `catalog.json`。

## 固定大小诊断

`SaveService.get_catalog_diagnostics()` 提供：

```text
authoritative_read_budget
authoritative_read_count
last_authoritative_read_budget_used
last_deferred_authoritative_read_count
deferred_authoritative_read_count
catalog_stage_capacity
staged_catalog_entry_count
staged_catalog_peak_count
stage_hit_count
last_stage_hit_count
stage_invalidation_count
last_stage_invalidation_count
```

存档浏览器显示：

```text
待读世界 N（每次最多 32）
暂存目录 N/64
暂存命中 N
```

F3 世界目录行同时显示主文件待修复、待读世界、暂存目录、待建目录，以及 8 / 32 / 16 三套预算。

## 永久验收

- Headless：96 个健康 primary、96 个缺失 sidecar；
- 每次所有 96 个世界始终可见；
- 完整读取使用量严格为 32、32、32、0、0、0、0；
- 占位行严格为 64、32、0、0、0、0、0；
- sidecar 写入严格为 16、16、16、16、16、16、0；
- 暂存峰值为 48，低于 64 项上限；
- 完整读取累计恰好 96，消除旧序列的 80 次重复读取；
- 显式保存、外部 primary 变化和删除世界都会正确更新或失效暂存；
- primary 修复和 backup recovery 始终为 0；
- 每个 `world.json` 在收敛前后逐字节一致；
- 真实桌面：正式 GameScene、SaveBrowserPanel、40 个世界、8 个占位行、目录待写提示和 F3；
- 相邻目录重建、多世界恢复、Save Recovery、World Catalog、Runtime Health、Integration 与 Runtime Stability；
- 权威总 Runtime、三轮 lifecycle soak、完整桌面矩阵与 Windows Release。
