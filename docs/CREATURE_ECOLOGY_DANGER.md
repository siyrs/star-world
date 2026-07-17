# 地图生态与实时危险度合同

## 目标

把此前没有真正使用的 `CreatureSpawner.map_id` 转化为地图级生态差异，并让玩家能够理解当前区域为什么危险。

```text
creature_ecology.json
→ CreatureEcologyRegistry
→ CreatureEcologyPolicy
→ CreatureSpawner
                ↓
exploration_danger.json
→ ExplorationDangerRegistry
→ ExplorationDangerPolicy
→ ExplorationDangerService
→ HUD / Prospecting Record
```

## 地图生态

每张地图独立定义：

- 被动生物上限；
- 白天和夜间敌对生物上限；
- 日出、白昼、黄昏和夜晚的敌对生成概率；
- 被动与敌对物种权重；
- 生成节奏；
- 地图基础危险分。

代表性差异：

| 地图 | 生态特点 |
|---|---|
| 星辰大陆 | 被动生物丰富，白天无自然敌对生物，夜间压力较低 |
| 荒漠遗迹 | 被动生物较少，黄昏和夜间敌对概率较高 |
| 极寒冰原 | 牛更常见，夜间敌对上限高于均衡大陆 |
| 天空群岛 | 鸡占主要权重，敌对生物上限最低 |
| 深渊世界 | 白天也存在敌对压力，夜间上限和生成概率最高 |

`CreatureSpawner` 仍负责生成生命周期与距离回收，但不再持有地图专用条件分支。

## 危险度来源

危险度是 `0..100` 的粗粒度分数，由以下信息组合：

```text
地图基础危险
+ 玩家深度
+ 昼夜阶段
+ 附近敌对生物
+ 附近岩浆样本
+ 洞穴开放比例
```

危险等级：

| ID | 显示 |
|---|---|
| safe | 低 |
| guarded | 警戒 |
| dangerous | 危险 |
| severe | 极高 |

HUD 同时显示等级、分数和最多三个主要原因，不能只用颜色表达结果。

## 性能合同

危险评估不是全区域扫描，也不会强制加载区块。

默认采样：

```text
水平半径 4
垂直半径 4
水平步长 2
垂直步长 2
理论样本 125
硬上限 125
刷新间隔 0.75 秒
```

静态校验要求硬上限不得超过 512。

环境读取使用：

```text
VoxelWorld.get_initial_block(position)
```

因此不会因为 HUD 更新触发区块构建或修改玩家世界。

## 探矿联动

成功探矿时，当前危险快照会写入发现记录：

```text
danger_tier_id
danger_label
danger_score
danger_reasons
```

探索存档版本升级为 `v2`：

- v1 记录自动补齐 `unknown` 危险信息；
- 新记录保存扫描当时的风险，而不是在读取日志时重新计算；
- 原有 64 条去重与上限合同保持不变；
- 仍不保存矿物精确坐标。

## 生命周期

```text
_begin_world
→ 选择地图生态
→ 迁移探索记录
→ attach_game
→ 绑定 World / Player
→ activate_gameplay
→ 启动危险评估
→ return_to_menu / failure
→ 停止并清理
```

暂停、死亡和阻塞 UI 不会绕过生产输入上下文。危险面板是纯展示层，必须鼠标透传。

## 测试门禁

### 静态合同

`validate_ecology_danger.ps1` 验证：

- 五张地图与五个生态档案一一对应；
- 物种 ID、权重、上限和阶段概率合法；
- 深渊白天敌对压力与天空鸡权重等产品合同；
- 危险采样预算；
- 深度区间和危险等级完整覆盖。

### 领域回归

`ecology_danger_regression.gd` 覆盖：

- Registry 加载与默认回退；
- 昼夜上限和权重选择；
- 生产 Spawner 的地图档案和附近敌对查询；
- 危险分数边界与原因；
- 125 样本预算；
- 安全环境与高危环境切换；
- 探矿记录携带风险；
- v1→v2 迁移。

### 真实桌面

`ecology_danger_desktop_acceptance.gd` 使用生产：

```text
GameScene
ExplorationProgressionServiceHub
CreatureSpawner
DayNightService
VoxelWorld
ExplorationDangerService
GameHUD
ProspectingService
SaveService
```

真实验证深渊地图、夜间敌对上限、附近僵尸、HUD 危险面板、右键探矿、正式保存和昼夜降险。
