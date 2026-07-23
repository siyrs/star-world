# 多世界渐进恢复合同

## 目标

`SaveService.list_worlds()` 必须保证所有拥有有效 `.tmp` 或 `.bak` 候选的世界立即可见，但不能在一次主菜单刷新中同步修复任意数量的损坏 `world.json`。

本合同把高成本主文件提升限制在固定**修复预算**内：

```text
每次目录扫描最多修复 8 个 primary
```

读取候选和生成临时列表 metadata 仍可继续，因此世界始终可见；没有进入本轮预算的世界标记为待渐进修复，不生成声称 primary 健康的新 `catalog.json`。

## 扫描顺序与确定性

世界 ID 在扫描前按字符串升序排序。相同磁盘状态下，每次刷新修复相同的前八个候选，避免文件系统返回顺序造成随机饥饿。

20 个同时损坏世界的预期收敛为：

```text
第 1 次：修复 8，待修复 12
第 2 次：修复 8，待修复 4
第 3 次：修复 4，待修复 0
第 4 次：20/20 纯 sidecar 命中
```

即 **8 → 8 → 4**，单次不会超过八个原子提升。

## 世界可见性

预算只约束 `.recover` 写入、primary 位移和原子提升。以下工作不受修复预算阻止：

- 验证 primary、temporary、backup；
- 从有效候选读取白名单 metadata；
- 在存档浏览器渲染世界行；
- 玩家选择或删除世界。

因此即使 100 个世界同时损坏，首屏也不能隐藏第九个及后续世界。

## 完整加载

`load_world()` 是明确的玩家选择，完整加载不受目录修复预算限制。玩家点击一个仍待修复的世界时，系统必须立即尝试重建该世界 primary，而不是要求反复刷新列表。

## 目录一致性

只有 primary 原本健康或本轮已成功提升后才能写入 `catalog.json`。待渐进修复世界可使用候选 metadata 显示，但目录 sidecar 保持缺失，下一次刷新继续进入恢复队列。

## 固定大小诊断

`get_catalog_diagnostics()` 增加：

```text
primary_repair_budget
last_repair_budget_used
last_deferred_recovery_count
deferred_recovery_count
```

存档浏览器显示：

```text
待渐进修复 N（每次最多 8）
```

F3 世界目录行显示回退、修复、待修复与耗时。待修复数量产生 warning，但不等同于数据丢失；主文件提升失败仍由既有恢复健康合同标为 critical。

## 永久验收

- Headless：20 个损坏世界，验证 8 → 8 → 4 → 纯命中；
- 每次扫描所有 20 个世界都可见；
- 每个 primary 恰好修复一次；
- 真实桌面：正式 GameScene、SaveBrowserPanel、20 行世界、待修复状态和截图；
- 相邻 Save Recovery、World Catalog、Runtime Health、Integration 与 Runtime Stability；
- 权威总 Runtime、三轮 lifecycle soak、完整桌面矩阵与 Windows Release。
