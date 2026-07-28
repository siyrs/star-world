# 架构审计：Iteration 47 — 数据驱动世界地标收口与热路径治理

## 审计基线

本轮以 `master` 已合入的高 DPI、控制器焦点和专业 UI 为基线，迁移并收口原 PR #80 的数据驱动世界地标能力。目标不是直接合并落后分支，而是把 POI/装饰注册表重新建立在最新主分支上，保留全部现有门禁，并修复审计中发现的体素生成热路径分配问题。

## 已确认的问题

### P0：旧功能分支落后最新主分支

原 POI 分支基于 PR #79 后的提交，随后 `master` 已合入 PR #81。直接合并会覆盖同名架构审计文档，并丢失全量测试入口中的 UI Accessibility 验证。

处理：从最新 `master` 重新组装单一提交；保留 `validate_ui_accessibility.ps1` 和 `ui_accessibility_regression.gd`，将本轮审计独立记录为 Iteration 47。

### P0：方块查询热路径重复深拷贝 Profile

`WorldDecorationRegistry.get_profile()` 为保护注册表所有权，会返回 `duplicate(true)`。原实现却在 `_get_decoration_block()` 和 `get_poi_snapshot()` 中重复调用它。体素 Chunk 生成会高频查询方块，这会把正确的防御性拷贝误用成每格分配，带来不必要的 Dictionary/Array 创建与 GC 压力。

处理：

- `StarWorldGenerator` 在构造及每次 `configure()` 时缓存一次规范化 Profile；
- 同时缓存树木排除密度；
- 方块与 POI 热路径只读该缓存；
- 暴露 `profile_refresh_count` 和 `cached_rule_count` 两个有界诊断标量；
- 不缓存世界、Chunk、方块结果或可变运行状态。

### P1：性能回归不能依赖毫秒阈值

CI 的 Windows 软件渲染、机器负载和首次导入会导致计时抖动。只断言“必须快于 N 毫秒”容易假红，也无法证明没有深拷贝。

处理：新增确定性 Headless 回归，在数千次真实 `get_block()` 与 POI 查询前后验证 Profile 刷新计数不变；静态合同同时禁止热路径重新出现 `world_decorations.get_profile()`。

### P1：Schema 与规则预算需要双层门禁

生产数据固定 `schema_version = 1`、单 Profile 最多 16 条规则。运行时 Registry 继续负责类型、方块、概率、Cell、半径和高度归一化；PowerShell 静态合同额外要求生产 Schema 与预算保持精确，避免配置漂移绕过 Headless 测试。

## 最终架构

```text
world_decoration_profiles.json
          │ strict schema / bounded rules
          ▼
WorldDecorationRegistry
          │ one defensive copy per configure()
          ▼
StarWorldGenerator._decoration_profile
          ├─ get_block() / _get_decoration_block()
          ├─ get_poi_snapshot()
          └─ bounded diagnostics
                    │
                    ▼
WorldDecorationPolicy (pure deterministic interpreter)
```

## 保持不变的兼容合同

- 五张地图与 Profile 一一对应；
- Salt、概率阈值、遗迹 Cell、中心偏移、半径与高度保持旧值；
- 已有 Seed 的未探索 Chunk 仍生成相同装饰；
- `world.json` 不新增 POI 或缓存状态；
- 玩家地图简报继续显示资源特点与地表地标；
- 世界生成仍由 `StarWorldGenerator` 和权威 Hash 唯一决定。

## 永久测试沉淀

- `tests/developer_b/validate_world_decoration_registry.ps1`
- `tests/developer_b/validate_world_decoration_hot_path.ps1`
- `tests/qa/world_decoration_registry_regression.gd`
- `tests/qa/world_decoration_hot_path_regression.gd`
- `tests/qa/world_decoration_desktop_acceptance.gd`
- `.github/workflows/world-decoration-poi-tests.yml`
- `tests/run_all.ps1`

## 验收要求

1. 静态 Schema、规则预算、缓存所有权和禁止热路径深拷贝合同通过；
2. 三 Seed、五地图逐点兼容回归通过；
3. 数千次方块/POI 查询期间缓存刷新计数不增长；
4. 真实地图简报、正式 VoxelWorld、3×3 Chunk 与遗迹截图通过；
5. 相邻资源、UI、Integration、Combat、Runtime、桌面矩阵与 Windows Release 全部通过；
6. 固定最终 SHA 无未解决审查项后才允许 squash 合入 `master`。
