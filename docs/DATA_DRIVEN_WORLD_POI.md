# 数据驱动世界地标与装饰

## 目标

将 K3 阶段直接写在 `world_generator.gd` 中的草丛、花朵、仙人掌、枯灌木、发光晶体和荒漠遗迹迁移到严格的数据注册表，同时保持旧 Seed、Hash Salt、阈值、结构中心和未探索 Chunk 的生成结果不变。

## 状态所有权

```text
data/world_decoration_profiles.json
        |
        v
WorldDecorationRegistry
  - schema / profile / rule validation
  - 5 map profiles
  - <= 16 rules per profile
  - built-in compatibility fallback
        |
        v
WorldDecorationPolicy
  - surface_roll
  - column_roll
  - ruin_grid
  - ruin_debris
        |
        v
StarWorldGenerator
  - terrain context
  - tree exclusion
  - sky-island strength
  - authoritative seed hash
```

`WorldDecorationRegistry` 是装饰配置的唯一解释者；`WorldDecorationPolicy` 是无状态纯策略；`StarWorldGenerator` 只提供地形上下文与既有 Hash 函数，不再拥有地图装饰的 `match` 分支。

## 稳定兼容合同

- `WORLD_HEIGHT`、`SEA_LEVEL` 和基础地形算法不变；
- 旧 Hash 函数不变；
- 草原继续使用 Salt 911 与 600/680/740 阈值；
- 天空岛继续使用 Salt 907、0.35 岛体强度和 500/580/640 阈值；
- 深渊继续使用 Salt 991 与 130 阈值；
- 仙人掌继续使用 Salt 937/941、90 阈值和 1–2 高度；
- 荒漠遗迹继续使用 48×48 Cell、Salt 971、4200 激活下界、953/967 中心偏移、3 格网格和 1–4 高度；
- 遗迹碎片继续使用 Salt 991 与 110 阈值；
- 未知地图仍回落到 `star_continent`；
- POI 与装饰不进入 `world.json`，世界存档只保存玩家真实修改的稀疏覆盖。

## 有界预算

- 五个正式地图 Profile；
- 每个 Profile 最多 16 条规则；
- 当前生产规则总数 12；
- 单次方块查询只顺序解释当前地图的规则；
- POI 查询只计算当前 Cell，不扫描世界；
- 地图简报只读取注册表摘要，不触发 Chunk 或文件遍历；
- 真实桌面验收只加载遗迹中心周围 3×3 Chunk。

## 玩家体验

地图选择页新增“地表地标”摘要，与“资源特点”并列。玩家在创建世界前即可理解：

- 草原的草丛和野花；
- 荒漠的遗迹、仙人掌与碎片；
- 冰原的稀疏荒寒装饰；
- 天空岛的岛体强度约束；
- 深渊的低频发光晶体。

## 测试矩阵

### 静态合同

`tests/developer_b/validate_world_decoration_registry.ps1`

验证：

- 五地图与五 Profile 一一对应；
- Schema、默认 Profile 和 16 规则预算；
- Rule ID、类型、方块、概率、Cell 与半径范围；
- 生成器不再保留旧 `_cactus_height` / `_ruin_*` 硬编码函数；
- 地图简报、Headless、桌面脚本和工作流均已接线。

### Headless 回归

`tests/qa/world_decoration_registry_regression.gd`

验证：

- 生产 JSON 无错误；
- 非法方块注册表被拒绝；
- 三个 Seed、五张地图、多个地表高度上的新策略与旧算法逐点一致；
- 遗迹 Cell、激活、中心和真实断柱对应；
- 地图简报显示权威地标摘要。

### 真实桌面

`tests/qa/world_decoration_desktop_acceptance.gd`

验证：

- 真实鼠标选择荒漠遗迹；
- 地图简报显示地表地标；
- 在有界 Cell 内找到真实激活遗迹；
- 正式 `VoxelWorld` 加载中心周围 3×3 Chunk；
- 已加载方块与权威生成器逐点一致；
- 真实断柱、仙人掌或碎片存在；
- 输出地图简报截图、真实遗迹截图、JSON、stdout 和 stderr。

### 权威门禁

合入前继续要求：

- 32 阶段 Runtime；
- 完整真实桌面矩阵；
- UI 十屏旅程；
- Windows EXE/PCK 实际导出与启动。
