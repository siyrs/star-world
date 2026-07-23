# Architecture Audit · 2026-07-23 · Iteration 29

## 范围

本轮审计世界保存、主菜单存档列表、生产世界序列化和大存档桌面行为，目标是在不改变权威存档与恢复语义的前提下，让世界数量和世界体积可以独立增长。

## 审计发现

### 存档列表读取完整世界

`SaveService.list_worlds()` 原实现对每个世界调用 `_read_world_payload()`：

```text
打开 world.json
→ 解析完整 JSON
→ 深复制完整 payload
→ 执行全部迁移
→ 再取 metadata
```

列表实际只显示六个轻量字段，却读取方块修改、玩家、背包、装备、农业、畜牧、容器、机器和探索记录。随着规模专项已经验证 2,048 作物、512 机器和 3,000+ 世界修改，这条路径会把主菜单延迟绑定到所有存档总大小。

### `loaded_chunks` 被保存但从未恢复

`VoxelWorld.serialize()` 构造当前已加载 Chunk 坐标数组，`SaveService.create_world()` 也预置 `loaded_chunks`。但 `start_world()` 只读取 `block_overrides`，不会用该数组恢复流式状态。

这产生三个问题：

- 每次保存额外遍历全部已加载 Chunk；
- 文件包含无法影响下一次启动的瞬时状态；
- 文档宣称稀疏修改是世界持久事实，但 payload 同时暴露无效运行快照。

### 不能把目录变成第二权威来源

直接把世界列表改为只读独立 metadata 文件会引入崩溃窗口：世界已经保存，但 metadata 仍是旧值，或者反过来。目录必须明确是可丢弃派生缓存，并能通过权威 `world.json` 自愈。

### 缓存失败不应制造假保存失败

若世界文件已原子提交，仅目录写入失败，向玩家返回“保存失败”会阻止安全退出并误导用户。非权威缓存错误应进入诊断，不能改变权威提交结果。

## 决策

### 新增轻量目录

每个世界目录新增：

```text
catalog.json
```

目录只保存 schema、世界 save version、metadata 和权威文件字节数。世界 ID 与文件字节数同时作为低成本一致性校验。

### 权威顺序

```text
world.json 原子提交
→ catalog.json 派生提交
```

只有第一步失败才触发 `save_failed`。第二步失败由 `write_failure_count` 记录，并在下一次列表刷新时修复。

### 兼容迁移

旧世界没有目录时，第一次列表刷新读取一次完整世界并生成目录。目录损坏、ID 错误、版本错误或字节数过期使用相同路径。稳态不再读取完整世界。

### 瞬时字段删除

生产 `CachedBatchedVoxelWorld` 直接序列化稀疏持久字段，不再先构造 `loaded_chunks` 后由上层丢弃。`SaveService` 仍二次擦除该字段，以兼容旧世界和非生产测试替身。

### 可观测性

目录刷新记录：

```text
hits
fallbacks
repairs
avoided_world_bytes
elapsed_usec
write_failures
```

UI 只展示世界数量、目录耗时、修复数量和每个世界的文件大小；完整诊断留给测试和运行报告。

## 实现结果

新增：

```text
src/save/world_catalog_policy.gd
docs/WORLD_CATALOG.md
tests/qa/world_catalog_regression.gd
tests/qa/world_catalog_desktop_acceptance.gd
tests/developer_b/validate_world_catalog.ps1
.github/workflows/world-catalog-tests.yml
```

升级：

```text
src/save/save_service.gd
src/world/cached_batched_voxel_world.gd
src/ui/save_browser_panel.gd
tests/run_all.ps1
docs/PRODUCT_ROADMAP.md
README.md
```

## 真实规模验收

桌面用例使用正式 `GameScene`、`SaveService`、`MainMenu` 和 `SaveBrowserPanel`：

```text
12 个世界
× 每世界 2,048 条 block_overrides
= 24,576 条真实稀疏世界修改
```

验收会主动删除一个目录并破坏另一个目录，要求两个世界都保持可见、目录均自动修复；随后再次刷新，要求所有测试世界由目录命中，并记录避免读取的权威总字节数和实际耗时。

最后保存面板必须真实渲染世界大小和目录耗时，真实“继续”按钮必须进入选中的完整世界，2,048 条修改必须全部恢复，截图和 JSON 报告必须上传。

## 后续建议

轻量目录完成后，下一阶段应基于真实数据推进：

1. 将目录文件大小、最近保存耗时和恢复来源接入 F3 的聚合运行健康报告；
2. 为大量玻璃板、栅栏、门与梯子的跨 Chunk 邻接切换建立统一结构压力门禁；
3. 在有真实使用率和预算不足证据前，继续拒绝管道、电网或跨 Chunk 物流；
4. 更新路线图时必须把已合并功能移出“下一阶段”，避免重复规划已经完成的门、梯子和 reusable CI。
