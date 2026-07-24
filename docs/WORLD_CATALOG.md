# 轻量世界目录合同

## 目标

主菜单的“存档 / 继续”只需要世界名称、地图、Seed、更新时间、游玩时长和文件大小，不应为了展示一行列表而读取、解析、深复制并迁移完整 `world.json`。

随着稀疏世界修改、机器、农业、畜牧、探索记录和背包状态增长，旧实现的目录刷新成本为：

```text
O(所有世界存档总字节数)
```

轻量世界目录把稳态刷新成本收敛为：

```text
O(世界数量 × 小型 catalog.json)
```

## 权威边界

`world.json` 始终是唯一权威存档。每个世界目录新增可丢弃、可重建的：

```text
catalog.json
```

目录文件只保存：

- `catalog_version`；
- `save_version`；
- 当前权威 `world.json` 字节数；
- 严格白名单 metadata：`id`、`name`、`map_id`、`seed`、`created_at`、`updated_at`、`play_seconds`。

所有字符串限制为 128 个字符。`map_profile`、自定义 metadata、玩家、背包、机器、农业、实体、探索记录和方块修改都不得进入目录，避免扩展字段把派生侧车重新膨胀成第二个世界存档。

## 保存事务

生产保存顺序：

```text
原子写入 world.json
→ 读取最终 world.json 字节数
→ 原子写入 catalog.json
→ 发布 world_saved
```

`catalog.json` 是派生缓存。若目录写入失败但 `world.json` 已成功提交，世界保存仍返回成功，并累加 `write_failure_count`。下一次列出世界时会从权威存档回退并修复目录，不能因为非权威缓存失败而阻止玩家保存或返回主菜单。

## 命中校验

目录命中必须同时满足：

```text
catalog_version == 当前版本
metadata.id == 世界目录名
catalog.save_bytes == 当前 world.json 文件长度
catalog.json 主文件可正常解析
```

任何不匹配都视为未命中。临时文件或备份虽然可用于权威世界恢复，但不会被当作稳态目录命中，以避免长期展示陈旧摘要。

## 回退与自愈

目录缺失、损坏、版本过旧、世界 ID 不匹配或字节数过期时：

```text
读取并迁移 world.json
→ 从权威 payload 派生白名单 metadata
→ 重写 catalog.json
→ 返回同一个世界条目
```

因此旧世界无需一次性迁移，第一次打开存档列表即可按需自愈；损坏目录不会隐藏或删除世界。

### 有界目录 sidecar 重建

主文件原子修复与目录 sidecar 写入使用独立预算。健康 `world.json` 缺少目录时，每次列表扫描最多重建 16 个 `catalog.json`；预算外世界仍立即可见，并显示为待建目录。48 个缺失 sidecar 的世界按 16 → 16 → 16 确定性收敛，避免主菜单写盘成本随世界数量无界增长。目录重建不修改权威主文件。

## 瞬时世界状态与生产投影

`loaded_chunks` 只是当前渲染距离内的运行快照，世界启动并不读取它。最近 Chunk 缓存和重建批处理必须继续保持瞬时，不拥有保存接口。

正式 `GameScene` 使用 `PersistentCachedBatchedVoxelWorld` 作为窄持久化投影：

```text
PersistentCachedBatchedVoxelWorld
└─ CachedBatchedVoxelWorld
   └─ BatchedVoxelWorld
      └─ VoxelWorld
```

投影只返回：

```text
version
profile_id
seed
world_id
block_overrides
```

因此保存路径不会先遍历或构造 `loaded_chunks`。`SaveService` 仍在磁盘边界再次移除旧 payload 中的该字段，兼容历史调用方和旧存档。Chunk 缓存、重建计数、流式队列和目录诊断均不得进入世界保存。

## 目录诊断

`SaveService.get_catalog_diagnostics()` 提供有界聚合数据：

- 累计目录刷新、命中、权威回退、自愈和目录写入失败次数；
- 最近一次世界数、命中数、回退数和修复数；
- 最近一次避免读取的权威世界总字节数；
- 最近一次目录刷新微秒、毫秒和命中率；
- 主文件修复预算、目录写入预算、各自使用量和待处理数量。

诊断不包含完整 metadata 或世界状态，也不写入存档。

## 用户界面

存档浏览器继续同步刷新，但稳态只读取轻量目录。每行显示权威 `world.json` 的人类可读大小，状态栏显示目录刷新耗时；发生旧目录自愈时显示修复数量，目录写入预算耗尽时显示待建目录数量和每次最多 16 的边界。

点击“继续”后仍通过 `load_world()` 读取、恢复和迁移完整权威世界，目录优化不改变真正的加载语义。

## 永久验收

领域与单元测试覆盖：

- 目录策略字段规范化和严格 metadata 白名单；
- 未知、嵌套和大体积 metadata 扩展被排除；
- 世界 ID 和文件长度不匹配拒绝；
- 新世界立即写入目录；
- 稳态列表只命中目录；
- 缺失和损坏目录回退并自愈；
- 48 个健康主文件的目录重建按 16 → 16 → 16 渐进收敛；
- 目录写入预算不消耗主文件修复预算；
- 完整世界加载保持不变；
- `loaded_chunks` 不进入磁盘或迁移结果；
- 缓存层不定义保存接口，生产投影不构造瞬时 Chunk 列表。

真实桌面验收创建 12 个世界、每个 2,048 条稀疏修改和大体积 `map_profile` 扩展。每个 `catalog.json` 必须保持在 4 KiB 以内；测试破坏两个目录后验证自愈，再通过正式存档面板显示大小、截图、点击“继续”、进入可玩世界并恢复全部修改。独立目录预算验收还会创建 24 个健康世界并移除全部 sidecar，验证首轮只写 16 个、所有世界仍显示、F3 呈现待建目录，最终进入纯命中。所有候选最终还必须通过总 Runtime、完整桌面矩阵和 Windows Release 实际导出与启动。
