# 地图资源分布合同

## 目标

把矿物深度、密度和地图偏好从 `StarWorldGenerator` 的硬编码分支中拆出，形成可审计、可解释、可扩展的数据合同。

```text
地图选择
→ ResourceDistributionRegistry
→ ResourceDistributionPolicy
→ StarWorldGenerator
→ VoxelWorld / VoxelChunk
```

玩家在创建世界前可以看到资源特点；世界生成继续保持确定性 Seed 和既有矿物概率。

## 数据结构

生产数据位于：

```text
data/resource_distribution.json
```

每个地图资源档案包含：

```json
{
  "id": "star_continent",
  "name": "均衡矿层",
  "summary": "玩家可见说明",
  "fallback_block": "stone",
  "entries": [
    {
      "block_id": "diamond_ore",
      "min_y": 1,
      "max_y": 10,
      "cumulative_threshold": 22
    }
  ]
}
```

`cumulative_threshold` 使用 `0..9999` 的确定性 hash roll，并按数组顺序依次判断。阈值必须严格递增，避免后一个矿物永远无法命中。

## 兼容策略

本轮把旧公式展开为精确整数阈值，不改变已有世界与未探索区域的结果：

| 地图 | 钻石 | 金 | 铁 | 煤 | 旧倍率 |
|---|---:|---:|---:|---:|---:|
| 星辰大陆 | 22 | 70 | 205 | 500 | 1.00 |
| 荒漠遗迹 | 29 | 94 | 276 | 675 | 1.35 |
| 极寒冰原 | 22 | 70 | 205 | 500 | 1.00 |
| 天空群岛 | 15 | 49 | 143 | 350 | 0.70 |
| 深渊世界 | 36 | 115 | 338 | 825 | 1.65 |

以上数值与旧实现的 `int(base_threshold * bonus)` 完全一致。

以下合同保持不变：

- hash 算法与 salt `211` 不变；
- 世界 Seed 不变；
- 矿物深度边界不变；
- 方块 ID 与 numeric ID 不变；
- 存档结构不变；
- 已保存的 `block_overrides` 优先于生成结果；
- 未知地图仍回退到 `star_continent`。

## 模块责任

### ResourceDistributionRegistry

负责：

- 加载 JSON；
- 校验档案、方块、深度和阈值；
- 解析默认地图；
- 提供玩家可见摘要；
- 数据损坏时安装最小内置均衡档案。

Registry 不读取场景树，也不修改世界。

### ResourceDistributionPolicy

纯策略，仅根据：

```text
profile + y + roll
```

返回矿物或 fallback block。它不生成随机数、不知道 Seed，也不访问文件。

### StarWorldGenerator

继续负责地形、洞穴、树木和 Seed hash。进入深层石质生成时，只把同一 roll 委托给资源 Registry，不再持有地图倍率分支。

### MapSelectionPanel

只读取 Registry 的 `summary` 并展示“资源特点”，不复制阈值或生成规则。

## 扩展规则

新增地图时必须同时：

1. 在 `map_profiles.json` 添加地图；
2. 在 `resource_distribution.json` 添加同 ID 档案；
3. 保证阈值严格递增；
4. 使用已注册的方块 ID；
5. 提供玩家可理解的资源摘要；
6. 更新数据校验和密度回归；
7. 完成真实桌面与 Windows Release 验收。

增加新矿物时应先追加 Block ID，随后定义深度与累计阈值。不得在 `world_generator.gd` 新增地图专用矿物 `if/elif`。

## 测试门禁

### 静态数据合同

`tests/developer_b/validate_resource_distribution.ps1` 验证：

- 五张地图与五个资源档案一一对应；
- 默认档案存在；
- 四类矿物完整且不重复；
- 深度合法；
- 阈值严格递增且小于 10000；
- fallback block 合法；
- 玩家摘要非空。

### 领域回归

`tests/qa/resource_distribution_regression.gd` 覆盖：

- Registry 加载和默认回退；
- 每个阈值的前一格、边界格；
- 深度边界；
- 旧地图别名；
- Generator 与 Registry 委托一致；
- 同 Seed 下 `深渊 > 荒漠 > 均衡 = 冰原 > 天空`；
- 地图选择界面使用权威摘要。

### 真实桌面

`tests/qa/resource_distribution_desktop_acceptance.gd` 使用生产：

```text
MapSelectionPanel
真实鼠标事件
StarWorldGenerator
VoxelWorld
VoxelChunk
```

验证玩家选择、摘要展示、Seed 确定性、地图密度差异、生产世界生成一致性、出生区块加载和截图证据。

独立工作流：

```text
Resource distribution quality gates
```

完整 PR 还必须通过仓库现有的全量 Runtime、全部真实桌面流程和最终 Windows Release smoke。
