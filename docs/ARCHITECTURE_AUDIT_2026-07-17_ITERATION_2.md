# 全仓架构审计 · 2026-07-17 · 第二轮

## 审计基线

本轮基于：

```text
master@f35297461d79026d577900528d56c8ed3f313340
```

复核世界生成、方块目录、物品、配方、采集、方向/形状、玩家使用链、ServiceHub 继承链、探索路线、存档、体验层、全部回归和 GitHub Actions。

第一轮已经完成地图资源分布数据化。本轮重点检查“玩家是否真的能利用资源差异”和“现有内容是否形成完整 round-trip”。

## 审计发现

### P0 · 可制作玻璃板是死内容

现状：

- `items.json` 存在 `glass_pane`；
- `recipes.json` 可制作 16 个玻璃板；
- `BlockRegistry` 没有 `glass_pane`；
- `get_block_for_item("glass_pane")` 返回 `air`。

影响：玩家成功消耗玻璃制作物品后，右键不会放置任何方块。该问题不属于视觉瑕疵，而是物品与世界目录断裂造成的功能丢失。

处置：

- 追加 `glass_pane` 与 `glass_pane_ns` 两个世界 ID；
- 统一背包物品和掉落；
- 双轴方向解析；
- 1/8 格真实薄几何；
- 视觉继承、采集、预览、碰撞和保存；
- 新增跨目录 `validate_catalog_integrity.ps1`，防止同类问题再次进入主分支。

### P1 · 资源地图差异缺少游戏内使用闭环

现状：地图选择已经解释资源差异，但进入世界后玩家只能盲目开采，没有区域级反馈。

影响：资源分布属于隐藏规则，难以转化为探索目标。

处置：新增简易探矿仪：

- 工作台制作；
- 真实右键；
- 有预算扫描；
- 深度与密度反馈；
- 最强矿物类型；
- 区块级发现记录；
- 存档恢复。

### P1 · 探矿功能必须避免退化成透视作弊

风险：直接返回矿物位置会绕过洞穴探索、工具成长和地图危险，破坏玩法闭环。

约束：

- 不返回矿物坐标；
- 不返回位置数组；
- 不强制加载远区块；
- 最大 700 个采样；
- 只返回区块、深度、密度和最强类型；
- 文案明确“粗粒度趋势”。

### P1 · 探索状态需要领域自有迁移与预算

风险：不断扫描会让世界存档无限增长，或者把探索迁移继续塞入通用 SaveService。

处置：

- `ProspectingStateMigration` 负责领域状态；
- 稳定 `chunk:depth_band` Key；
- 同区域覆盖旧结果；
- 最多 64 条记录；
- 超额旧数据仅保留最新记录。

### P2 · 仍存在的后续优化

1. `validate_data.ps1` 仍保留一份历史硬编码方块清单；本轮新增权威跨目录校验，但后续可逐步让其他校验器复用生产目录解析结果。
2. 专项 GitHub Actions 数量继续增长；应提取 reusable workflow，保留功能专项名称但复用 import/validator/domain/desktop 模板。
3. 玻璃板目前根据玩家方向选择单轴，尚未自动连接相邻玻璃板；可作为建筑交互下一阶段。
4. 探矿发现已经持久化，但还没有独立探索日志 UI；下一步应把发现、危险度与首次探索里程碑整合展示。
5. 地图危险度尚未进入探矿摘要；后续应由地图、深度、洞穴、岩浆和昼夜纯策略计算。

## 本轮交付

```text
ProspectingRegistry / Policy / Service / Migration
ExplorationPlayer
ExplorationProgressionServiceHub
prospecting_kit item + recipe
coarse HUD prompt + first-person action
glass_pane real world variants
catalog integrity validator
prospecting validator
domain regressions
real desktop acceptance
specialized CI
architecture contracts and roadmap
```

## 最终合并标准

- 严格 Godot import；
- 数据、目录、视觉与探矿静态校验；
- 探矿领域和存档回归；
- 玻璃板方向、几何、网格和碰撞回归；
- 真实右键探矿；
- 真实双轴玻璃板放置与物理射线；
- 保存、重载和 UI 输入阻断；
- 全量既有 Runtime 与桌面矩阵；
- Windows Release 实际导出与启动；
- 无脚本错误、解析错误或资源泄漏。
