# Architecture Audit · 2026-07-23 · Iteration 29

## 范围

本轮审计世界保存、主菜单存档列表、生产世界序列化、大存档桌面行为和可复用 Headless 证据判断，目标是在不改变权威存档与恢复语义的前提下，让世界数量和世界体积可以独立增长，并确保退出码 0 不会掩盖资源问题。

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

### 目录也必须严格有界

第一版策略复制完整 metadata。虽然比完整世界小，但 `map_profile` 和未来扩展字段仍可能把目录膨胀为第二个不受控 payload。目录必须使用固定白名单，不能把“派生缓存”变成平行状态所有者。

### 缓存失败不应制造假保存失败

若世界文件已原子提交，仅目录写入失败，向玩家返回“保存失败”会阻止安全退出并误导用户。非权威缓存错误应进入诊断，不能改变权威提交结果。

### 捕获 Headless 日志仍可能假绿

新目录领域回归第一次真实运行打印：

```text
QA WORLD CATALOG PASS | checks=38 | worlds=3
```

进程退出码为 0，但同一 Artifact 的 stderr 同时包含：

```text
18 ObjectDB instances were leaked at exit
8 resources still in use at exit
```

`run_godot_headless_test.ps1` 当时只检查超时与退出码，不像桌面包装器那样扫描致命 Godot 诊断。这意味着带 stdout/stderr 证据的主领域脚本仍可在资源泄漏时假绿。

## 决策

### 新增轻量目录

每个世界目录新增：

```text
catalog.json
```

目录只保存 schema、世界 save version、权威文件字节数，以及 `id/name/map_id/seed/created_at/updated_at/play_seconds` 七个白名单字段。所有字符串限制为 128 字符；世界 ID 与文件字节数同时作为低成本一致性校验。

### 权威顺序

```text
world.json 原子提交
→ catalog.json 派生提交
```

只有第一步失败才触发 `save_failed`。第二步失败由 `write_failure_count` 记录，并在下一次列表刷新时修复。

### 兼容迁移

旧世界没有目录时，第一次列表刷新读取一次完整世界并生成目录。目录损坏、ID 错误、版本错误或字节数过期使用相同路径。稳态不再读取完整世界。

### 分离缓存与持久化所有权

`CachedBatchedVoxelWorld` 继续只拥有最近 Chunk 快照，不定义保存接口。新增窄层 `PersistentCachedBatchedVoxelWorld` 作为正式生产组合的持久化投影，只序列化 profile、Seed、world id 和稀疏 `block_overrides`。

```text
PersistentCachedBatchedVoxelWorld  ← 稀疏持久化投影
└─ CachedBatchedVoxelWorld         ← 最近 Chunk 快照（瞬时）
   └─ BatchedVoxelWorld            ← 重建批处理（瞬时）
      └─ VoxelWorld                ← 世界与流式运行
```

这样保存路径不再构造 `loaded_chunks`，同时不会让缓存层成为持久化所有者。`SaveService` 仍二次擦除该字段，以兼容旧世界和非生产测试替身。

### Headless 与 Desktop 使用同一成功标准

`run_godot_headless_test.ps1` 与 `run_godot_desktop_test.ps1` 现在都在 PASS 前扫描 stdout/stderr：

```text
SCRIPT ERROR
Parse Error
ObjectDB instances were leaked
Leaked instance:
Resources still in use at exit
```

目录回归主动释放未挂入 SceneTree 的生产世界节点。共享静态合同同时验证两个包装器的扫描函数和实际调用，防止后续重构删除该门禁。

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
src/world/persistent_cached_batched_voxel_world.gd
docs/WORLD_CATALOG.md
tests/qa/world_catalog_regression.gd
tests/qa/world_catalog_desktop_acceptance.gd
tests/developer_b/validate_world_catalog.ps1
.github/workflows/world-catalog-tests.yml
```

升级：

```text
src/save/save_service.gd
src/core/batched_game.gd
src/ui/save_browser_panel.gd
tests/ci/run_godot_headless_test.ps1
tests/developer_b/validate_reusable_ci_workflows.ps1
tests/run_all.ps1
docs/REUSABLE_GODOT_QUALITY_GATES.md
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

每个世界还写入大体积 `map_profile` 扩展，但 `catalog.json` 必须保持在 4 KiB 以内。验收会主动删除一个目录并破坏另一个目录，要求两个世界都保持可见、目录均自动修复；随后再次刷新，要求所有测试世界由目录命中，并记录避免读取的权威总字节数和实际耗时。

最后保存面板必须真实渲染世界大小和目录耗时，真实“继续”按钮必须进入选中的完整世界，2,048 条修改必须全部恢复，截图和 JSON 报告必须上传。领域和桌面日志同时必须没有脚本错误、解析错误和资源泄漏。

## 后续建议

轻量目录完成后，下一阶段应基于真实数据推进：

1. 将目录文件大小、最近保存耗时和恢复来源接入 F3 的聚合运行健康报告；
2. 为大量玻璃板、栅栏、门与梯子的跨 Chunk 邻接切换建立统一结构压力门禁；
3. 在有真实使用率和预算不足证据前，继续拒绝管道、电网或跨 Chunk 物流；
4. 更新路线图时必须把已合并功能移出“下一阶段”，避免重复规划已经完成的门、梯子和 reusable CI。
