# 有界世界目录重建合同

## 目标

`catalog.json` 是可丢弃的轻量 sidecar。主文件恢复已经限制为每次目录扫描最多修复 8 个 primary，但健康 `world.json` 在 sidecar 全部缺失时，旧路径仍会同步重建任意数量的目录文件。

这会让主菜单写盘成本重新随世界数量线性增长：

```text
48 个健康世界全部缺失 catalog.json
→ 读取 48 个权威 payload
→ 同步执行 48 次目录原子写入
→ 列表刷新等待全部写盘完成
```

本合同为 sidecar 增加与 primary 修复相互独立的写入预算。

## 双预算

```text
主文件原子修复：每次最多 8
目录 sidecar 重建：每次最多 16
```

两种预算不能复用同一个计数器：

- primary 修复包含 `.recover` 写入、损坏主文件位移和原子提升；
- catalog 重建只写入小型派生文件；
- 健康 primary 缺目录时不得消耗主文件修复预算；
- repaired primary 只有在目录写入预算仍有余额时才立即生成 sidecar。

## 世界始终可见

目录写入预算只限制 `_write_catalog_entry()`。即使本轮预算耗尽，系统仍会：

```text
读取健康 world.json
→ 派生严格白名单 metadata
→ 返回世界条目
→ 标记 catalog_rebuild_deferred=true
```

因此第十七个及后续世界不会从存档浏览器消失。没有 sidecar 的世界下一次刷新继续进入稳定排序后的重建队列。

## 确定性收敛

世界 ID 继续按字符串升序扫描。48 个健康世界全部缺失目录时：

```text
第 1 次：重建 16，待建 32
第 2 次：命中 16，重建 16，待建 16
第 3 次：命中 32，重建 16，待建 0
第 4 次：48/48 纯 sidecar 命中
```

即 **16 → 16 → 16**。单次绝不超过 16 次目录写入。

## 权威数据不变

目录收敛期间：

- 不调用 primary repair；
- 不修改 `world.json`；
- 不覆盖 `.bak`；
- 不创建新存档领域；
- 不将预算、队列或诊断写入世界存档。

保存世界时仍会立即尝试写入自己的 sidecar，因为这是一次明确的单世界保存事务，而不是大目录批量恢复。

## 固定大小诊断

`SaveService.get_catalog_diagnostics()` 增加：

```text
catalog_rebuild_budget
last_catalog_rebuild_budget_used
last_deferred_catalog_rebuild_count
deferred_catalog_rebuild_count
```

存档浏览器显示：

```text
待建目录 N（每次最多 16）
```

F3 世界目录行同时显示：

```text
主文件待修复
目录待重建
主文件预算
目录写入预算
```

待建目录属于 warning。目录写入失败继续由 `write_failure_count` 记录，不会把已经成功提交的世界保存误报为失败。

## 永久验收

- Headless：48 个健康 primary、48 个缺失 sidecar；
- 四次扫描验证 16 → 16 → 16 → 纯命中；
- 每次所有 48 个世界始终可见；
- 主文件修复使用量和恢复次数始终为 0；
- 每个 `world.json` 文本在目录收敛前后完全一致；
- 真实桌面：正式 GameScene、SaveBrowserPanel、24 个世界、待建目录提示和 F3；
- 相邻多世界恢复、Save Recovery、World Catalog、Runtime Health、Integration 与 Runtime Stability；
- 权威总 Runtime、三轮 lifecycle soak、完整桌面矩阵与 Windows Release。
