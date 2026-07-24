# 有界权威世界读取合同

## 目标

世界列表已经拥有两层写盘边界：

```text
主文件原子修复：每次最多 8
catalog sidecar 重建：每次最多 16
```

但当大量健康世界同时缺失 `catalog.json` 时，旧路径仍会同步读取、解析、迁移所有完整 `world.json`。即使 sidecar 写入被限制，主菜单读取成本仍会随世界数量与存档体积线性增长。

本合同为完整权威世界读取增加第三层独立预算：

```text
完整 world.json 读取：每次最多 32
```

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
- 读取预算有余额但写入预算耗尽时，可返回准确 metadata 并推迟 sidecar；
- 读取预算耗尽时，不得继续解析完整世界。

## 世界始终可见

读取预算不能隐藏第 33 个及后续世界。只要世界目录中存在 `world.json`、`.tmp` 或 `.bak` 候选，列表先返回一个固定大小占位行：

```text
id                 = 世界目录名
name               = 世界目录名
map_id             = metadata_pending
save_bytes         = 当前可用候选字节数
authoritative_read_deferred = true
catalog_rebuild_deferred     = true
```

存档浏览器显示“世界信息待读取”。玩家仍可选择并点击继续；`load_world()` 是明确的单世界操作，不受列表读取预算限制，会走原有完整加载、恢复和迁移合同。

## 确定性收敛

世界 ID 继续按字符串升序扫描。96 个健康世界全部缺失 sidecar 时，预期为：

```text
第 1 次：完整读取 32，写目录 16，待读世界 64
第 2 次：命中 16，完整读取 32，写目录 16，待读世界 48
第 3 次：命中 32，完整读取 32，写目录 16，待读世界 32
第 4 次：命中 48，完整读取 32，写目录 16，待读世界 16
第 5 次：命中 64，完整读取 32，写目录 16，待读世界 0
第 6 次：命中 80，完整读取 16，写目录 16
第 7 次：96/96 纯 sidecar 命中
```

读取和写入各自按固定预算收敛，不会随机饥饿。

## 权威存档不变

列表读取与占位收敛期间：

- 不修改健康 `world.json`；
- 不覆盖 `.bak`；
- 不将占位 metadata 写入 sidecar；
- 不进入 backup recovery；
- 不把预算、占位行、队列或诊断写入世界存档。

只有完整读取成功且 primary 已健康时，才允许使用真实 payload 构建 `catalog.json`。

## 固定大小诊断

`SaveService.get_catalog_diagnostics()` 增加：

```text
authoritative_read_budget
last_authoritative_read_budget_used
last_deferred_authoritative_read_count
deferred_authoritative_read_count
```

存档浏览器显示：

```text
待读世界 N（每次最多 32）
```

F3 世界目录行同时显示：

```text
主文件待修复
待读世界
待建目录
主文件修复预算
权威读取预算
目录写入预算
```

待读世界和待建目录属于 warning；主文件恢复失败与目录写入失败继续保持既有严重或警告证据。

## 永久验收

- Headless：96 个健康 primary、96 个缺失 sidecar；
- 每次所有 96 个世界始终可见；
- 完整读取使用量严格为 32、32、32、32、32、16、0；
- 占位行严格为 64、48、32、16、0、0、0；
- sidecar 写入严格为 16、16、16、16、16、16、0；
- primary 修复和 backup recovery 始终为 0；
- 每个 `world.json` 在收敛前后逐字节一致；
- 真实桌面：正式 GameScene、SaveBrowserPanel、40 个世界、8 个占位行和 F3；
- 相邻目录重建、多世界恢复、Save Recovery、World Catalog、Runtime Health、Integration 与 Runtime Stability；
- 权威总 Runtime、三轮 lifecycle soak、完整桌面矩阵与 Windows Release。
