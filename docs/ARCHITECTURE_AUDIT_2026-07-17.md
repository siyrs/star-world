# 全仓架构审计 · 2026-07-17

## 范围

本轮基于 `master@e05e01464428c931e371f686be3e57e8d0718783` 审查：

- 根目录产品、构建与架构文档；
- `data` 数据合同；
- 世界、区块、玩家、输入、交互、背包、机器、农业、装备、战斗、牧场、存档、体验和 UI；
- `tests/developer_*`、`tests/qa`、桌面验收脚本；
- GitHub Actions 与最近 28 个合并 PR 的实现和验收记录。

审计原则：先保护输入、保存、世界可见性、发行包和旧存档，再推进新功能。

## 总体结论

项目已经从体素 Demo 发展为具有清晰领域边界、真实桌面验收和 Windows Release 门禁的可持续沙盒基础。最近的农业、维修、牧场、战斗反馈、第一人称表现、原创像素纹理、非整块几何与四方向楼梯均有完整闭环。

当前最需要解决的不是继续堆内容，而是把仍然留在核心生成器中的地图差异逐步数据化，并降低后续扩展的重复校验和 CI 维护成本。

## 本轮发现与处置

### P0 · 守护既有可靠性

#### 1. 主分支存在并行提交风险

影响：若从旧提交直接修改，可能回退四方向楼梯、玩家控制与生存节奏等同事改动。

处置：本轮分支严格从最新 `master@e05e0146` 创建，不重写已有提交，不移动任何旧方块 numeric ID。

#### 2. 新系统必须继续经过真实发行验收

影响：Godot headless 通过不能证明真实鼠标、窗口渲染、区块碰撞或导出 EXE 可用。

处置：新增专项真实桌面用例，并继续依赖现有全量 Runtime、桌面矩阵和 Windows Release smoke 作为合并门禁。

### P1 · 已完成优化

#### 3. 矿物分布硬编码在 `world_generator.gd`

影响：

- 地图资源偏好与地形算法耦合；
- 调整阈值必须修改代码；
- 玩家在地图选择前无法理解资源差异；
- 新增地图或矿物容易继续扩大 `if/elif`；
- 数据、文档与测试无法独立审计。

处置：

```text
resource_distribution.json
→ ResourceDistributionRegistry
→ ResourceDistributionPolicy
→ StarWorldGenerator
```

同时保持旧 hash、salt、深度、整数阈值、Seed 和存档结果完全兼容。

#### 4. 地图选择只显示环境描述，不显示成长资源差异

影响：玩家在创建世界后才发现天空群岛资源稀缺或深渊资源富集，选择缺少可理解的风险收益信息。

处置：地图选择界面显示权威“资源特点”，来源与生成器使用同一 Registry，不复制文案和规则。

#### 5. 缺少资源分布的边界与密度回归

影响：一次阈值顺序错误可能让某种矿物永远不生成；一次倍率调整可能在没有证据的情况下破坏旧 Seed。

处置：新增静态数据校验、每个阈值边界测试、同 Seed 密度排序、Generator 委托一致性、生产 VoxelWorld 和真实桌面验收。

### P1 · 建议下一轮处理

#### 6. `PRODUCT_ROADMAP.md` 的“下一阶段”已明显落后

现状：文档仍把灌溉、多作物、肥料、动物繁殖、维修、攻击冷却和击退列为未来工作，但这些能力已在 PR #14–#28 完成。

影响：产品优先级会误导后续开发，导致重复实现或错误拆分任务。

建议：下一轮重写为当前实际状态，优先顺序调整为：

```text
探索反馈与资源层级
→ 敌对生态与地图危险度
→ Machine Base / 自动化接口
→ 建筑交互扩展
→ 内容规模化与性能压测
```

#### 7. 数据校验仍维护多份硬编码方块清单

现状：`validate_data.ps1` 等脚本各自维护 `knownBlocks` 或必需 ID。

影响：新增方块时容易遗漏某个校验器，造成注册表、视觉、采集和数据脚本不一致。

建议：增加一个由生产 `BlockRegistry.BLOCK_IDS` 导出的统一测试目录，其他 PowerShell 校验复用同一清单；逐步减少重复常量。

#### 8. 专项 GitHub Actions 数量持续增长

现状：每个功能都有独立工作流，同时 PR 还会触发完整 Godot quality gates。

影响：质量很强，但 Windows runner 时间和维护成本快速增加，重复安装 Godot、导入项目与运行相同前置步骤。

建议：保留专项可读性，但提取 reusable workflow：

```text
strict import
→ static validator
→ domain script
→ optional desktop script
→ artifact upload
```

各专项只传参数。完整 Windows Release 仍保留单一权威工作流。

#### 9. `StarWorldGenerator` 仍同时承担多个生成领域

现状：地形高度、河流、洞穴、树木、天空岛与资源都在一个类中。本轮已先拆出资源策略。

影响：继续加入遗迹、危险区域、地图特有结构后会再次扩大。

建议按风险从低到高逐步拆分：

```text
ResourceDistributionPolicy（已完成）
→ SurfaceLayerPolicy
→ TreePlacementPolicy
→ CaveCarvingPolicy
→ StructurePlacementPolicy
```

Generator 保留 Seed、坐标和策略编排，不成为万能规则集合。

### P2 · 功能推进建议

#### 10. 探索层缺少玩家可见反馈

当前资源深度已经不同，但游戏内还没有指南针、矿层提示、地图危险度或探索里程碑。

建议下一可玩闭环：

```text
制作简易探矿工具
→ 对当前区块给出粗粒度资源倾向
→ 引导玩家前往更深或更危险区域
→ 发现记录持久化
→ 地图特有资源/危险反馈
```

探矿结果应为粗粒度信息，不能直接透视每个矿物坐标。

#### 11. 自动化机器需要共享基础合同

现有 Furnace 已成熟，但新增机器若继续复制槽位、进度、暂停、离线恢复和存档逻辑，会形成多个独立实现。

建议先建立小型 Machine Base：

- 输入/输出能力；
- 进度与阻塞状态；
- 能源或燃料端口；
- 有界离线推进；
- 位置型序列化；
- UI 只读 snapshot；
- 不把所有机器塞进万能 Manager。

## 本轮交付清单

- `data/resource_distribution.json`；
- `ResourceDistributionRegistry`；
- `ResourceDistributionPolicy`；
- `StarWorldGenerator` 解耦；
- 地图资源提示；
- 静态数据校验；
- 领域与边界回归；
- 真实桌面生产验收；
- 独立 CI 质量门禁；
- 资源分布架构文档；
- 全仓审计报告。

## 验收标准

本轮只有在以下全部成立时才允许进入 `master`：

1. 数据合同通过；
2. Godot 严格导入通过；
3. 新资源领域回归通过；
4. 真实地图选择和生产世界验收通过；
5. 全量既有 Runtime 与领域回归通过；
6. 全部既有真实桌面流程无回归；
7. Windows Release 实际导出、启动和结构化报告通过；
8. 日志无脚本错误、解析错误、ObjectDB 或资源泄漏；
9. PR 基于最新 `master`，无回退同事改动。
