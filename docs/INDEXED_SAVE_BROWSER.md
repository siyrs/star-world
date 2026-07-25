# 索引化存档浏览器合同

## 背景

存档浏览器已经通过固定 24 行池和最多 6 个自动整理轮次控制 UI 节点与目录维护成本，但刷新完成后仍存在三个不合理路径：

```text
list_worlds()
  → 对全部 metadata duplicate(true)
  → 选择时线性扫描全部世界
  → 大目录只能逐页人工查找
```

目录中的世界越多，全量深拷贝、选择查找和人工定位成本越高。

## 只读浅引用索引

一次真实 `list_worlds()` 返回后，面板只保存只读浅引用，并构建：

```text
world_id → metadata
```

索引遵守以下合同：

- 空 ID 被忽略；
- 重复 ID 只保留第一项；
- UI 不修改 metadata Dictionary；
- 刷新不执行 `duplicate(true)`；
- 选择、继续和删除前的 metadata 查找通过 Dictionary 直接完成；
- 索引只存在于面板生命周期，不进入世界存档。

## 有界查询

查询策略是纯 `RefCounted`，不访问 `FileAccess`、`DirAccess`、`SaveService` 或世界 payload。

```text
MAX_QUERY_LENGTH := 64
MAX_QUERY_TOKENS := 8
```

规则：

- 去除首尾空白并转为小写；
- 查询最长 64 个字符；
- 最多保留 8 个不重复 token；
- 所有 token 必须命中同一个世界；
- 可搜索字段为名称、ID、地图和 Seed；
- 空查询返回全部索引项。

输入框不会在逐键输入时运行全目录查询。玩家按 Enter 或点击“搜索”后才应用查询，避免大目录每次键盘输入都执行 O(n) 匹配。

## 确定性排序

支持三种排序：

```text
最近更新     updated_at 降序
名称 A-Z     natural nocase 升序
存档从大到小 save_bytes 降序
```

任何主排序相同的记录都使用稳定 world ID 自然排序打破平局。未知排序值回退到“最近更新”。

## 查询结果与分页

查询只生成匹配 world ID 列表，仍复用固定 24 行池：

```text
第 N / M 页 · 匹配 X / 共 Y · 每页最多 24 个
```

查询、排序和翻页均不调用 `list_worlds()`，不读取磁盘，不消耗以下预算：

```text
Primary 修复 8
权威读取 32
Sidecar 写入 16
目录暂存 64
自动整理 6
```

只有显式刷新或自动目录整理可以重建索引。

## 隐藏选择安全

玩家选择一个世界后，如果新查询把它排除在结果之外，选择立即清空。这样“删除所选”不会删除当前不可见的旧选择。

世界被删除或刷新后不再存在时，选择同样清空。

## 诊断快照

`get_virtualization_snapshot()` 增加固定标量：

```text
indexed_world_count
matched_world_count
applied_query
query_token_count
sort_mode
index_rebuild_count
query_apply_count
```

快照不包含完整 metadata、世界 payload 或无限历史。

## 256 个世界真实验收

正式 Windows 桌面通过 `GameScene`、最终 `ServiceHub`、真实 `SaveService`、`MainMenu` 和 `SaveBrowserPanel` 创建 256 个世界：

- 固定 24 行形成 11 页；
- 首次刷新为 256/256 sidecar 命中；
- Gamma 名称查询得到 64 个世界和 3 页；
- snowfield 地图查询得到 51 个世界；
- Seed 查询精确命中一个世界；
- 查询、排序和分页期间 catalog `list_count` 不增加；
- 名称和存档大小排序保持确定性；
- 隐藏选择被清空；
- 稳态刷新仍为 256/256 sidecar 命中，完整读取和写入均为 0；
- 所有 `world.json` 逐字节不变；
- 输出真实截图、JSON 和日志。

## 永久门禁

- 纯查询策略回归；
- 256 项 Fake Service 索引、分页、查询、排序和隐藏选择回归；
- 256 个真实世界 Windows 桌面验收；
- 相邻虚拟化、目录暂存、权威读取、目录重建、恢复和统一健康回归；
- 权威 Runtime、三轮 lifecycle soak、完整桌面矩阵；
- Windows Release 实际导出和启动。
