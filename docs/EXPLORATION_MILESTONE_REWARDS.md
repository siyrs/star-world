# 探索里程碑奖励与背包事务合同

## 目标

探索日志已经能够稳定显示里程碑，但完成条件此前没有真正影响玩家成长。奖励系统必须满足两个同时成立的要求：

1. 玩家能够从探索中获得明确、可重复验证的成长回报；
2. 背包满、重复点击、存档重载或异常数据不能造成物品丢失或重复领取。

生产链路：

```text
ProspectingService
→ ExplorationJournalService
→ ExplorationMilestoneRewardPolicy
→ ExplorationMilestoneRewardService
→ InventoryService.transact_items
```

日志和 UI 不直接写背包。只有奖励事务服务可以在完成全部前置校验后提交物品。

## 为什么需要背包批量事务

旧 `InventoryService.add_item()` 的合同允许部分成功，并返回未放入数量。这个行为适合拾取单个物品，但不适合多物品奖励：

```text
火把 ×4 + 熟鸡肉 ×2
```

分别调用 `can_add_item()` 也不安全，因为两个物品会分别把同一个空槽计算为自己的容量。

旧合成路径还会：

```text
先移除原料
→ 尝试加入产出
→ 失败后移除部分产出
→ 再把原料加回
```

这会在一次业务操作内公开多个中间背包状态，并依赖回滚永远成功。

本轮新增：

```text
InventoryTransactionPolicy.plan
InventoryService.can_transact_items
InventoryService.transact_items
```

事务算法在背包副本上完成：

1. 校验物品 ID 与数量；
2. 模拟移除全部输入；
3. 模拟加入全部输出；
4. 任一步失败时返回原因，不修改真实背包；
5. 全部成功后一次替换槽位；
6. 每个变化槽位发出一次 `slot_changed`；
7. 整个事务只发出一次 `inventory_changed`。

生产合成服务已经切换到该事务入口。

## 奖励数据

生产数据位于：

```text
data/exploration_milestone_rewards.json
```

每个日志里程碑必须恰好拥有一个奖励定义：

```json
{
  "milestone_id": "three_regions",
  "description": "踏勘三个不同区块后领取用于升级工具的铁锭。",
  "items": [
    {"item_id": "iron_ingot", "count": 2}
  ]
}
```

奖励可以包含多个物品。`first_discovery` 还具有地图差异：

| 地图 | 基础奖励 | 地图额外奖励 |
|---|---|---|
| 星辰大陆 | 火把 ×4 | 苹果 ×2 |
| 荒漠遗迹 | 火把 ×4 | 玻璃 ×4 |
| 极寒冰原 | 火把 ×4 | 雪块 ×2 |
| 天空群岛 | 火把 ×4 | 木板 ×8 |
| 深渊世界 | 火把 ×4 | 熟鸡肉 ×2 |

这些都是已有、具有明确用途的生产物品，不增加没有消费场景的装饰材料。

## 当前里程碑奖励

| 里程碑 | 奖励 |
|---|---|
| 初次勘探 | 火把 ×4 + 地图额外物资 |
| 踏勘者 | 铁锭 ×2 |
| 深入地层 | 煤炭 ×8 + 面包 ×2 |
| 富集信号 | 钻石 ×1 |
| 险境侦察 | 铁锭 ×2 + 熟鸡肉 ×4 |
| 地质全览 | 金锭 ×3 + 火把 ×8 |
| 资深探索者 | 铁镐 ×1 + 火把 ×16 + 面包 ×4 |

## 状态所有权

日志里程碑是否完成，仍然由探索记录确定性派生。

奖励服务只持久化已经领取的 ID：

```json
{
  "version": 1,
  "claimed": [
    "first_discovery",
    "three_regions"
  ]
}
```

因此：

```text
locked    = 里程碑未完成
claimable = 已完成且未领取
claimed   = 已完成领取事务
```

“待领取”不需要保存第二份状态；它始终可以从里程碑完成情况与 claimed 集合重新计算。

## 领取事务

`ExplorationMilestoneRewardService.claim()` 的顺序固定：

1. 查找生产奖励定义；
2. 检查里程碑已经完成；
3. 检查奖励尚未领取；
4. 使用当前地图解析奖励包；
5. 调用 `InventoryService.transact_items()`；
6. 只有背包完整接收奖励后才写入 claimed；
7. 更新日志卡片并发出成功反馈。

失败合同：

| 原因 | 结果 |
|---|---|
| 未完成里程碑 | 不修改背包，不修改 claimed |
| 重复领取 | 不修改背包，不重复物品 |
| 背包已满 | 不修改背包，保持 claimable |
| 未知奖励 | 不修改任何状态 |
| 背包服务不可用 | 保留待领取状态 |

## UI 合同

按 `J` 打开探索日志后，每个里程碑显示：

- 完成进度；
- 奖励内容；
- 未解锁、可领取或已领取状态；
- 可领取时的真实按钮。

按钮只调用奖励服务，不持有 Inventory 引用，也不自行设置 claimed。

背包满时，Experience 层显示：

```text
背包空间不足；奖励会保留为待领取状态
```

释放空间后可以再次点击同一奖励。

## 世界存档

新世界初始 schema 现在直接包含：

```text
exploration.version = 3
exploration_rewards.version = 1
```

旧世界缺少这些字段时，`SaveService` 会补齐空状态；具体 claimed 清理仍由奖励域迁移器负责。

未知、空白和重复 claimed ID 会被规范化。服务只接受当前奖励注册表中存在的 ID。

## 测试门禁

### 静态合同

`validate_exploration_rewards.ps1` 验证：

- 每个探索里程碑恰好一个奖励；
- 奖励不引用未知里程碑；
- 奖励物品全部存在；
- 数量在有界范围内；
- 初次勘探覆盖五张地图的额外奖励；
- InventoryService 使用事务策略；
- 奖励状态版本稳定。

### 背包事务回归

`inventory_transaction_regression.gd` 覆盖：

- 两种物品争用同一空槽时整体失败；
- 失败后槽位逐字典不变；
- 失败不发出背包变更事件；
- 成功多物品包只发出一次刷新；
- 原料消耗与产出一次提交；
- metadata 感知堆叠；
- 生产合成服务使用事务入口。

### 奖励领域回归

`exploration_milestone_reward_regression.gd` 覆盖：

- 七个奖励与地图差异；
- locked / claimable / claimed；
- 重复领取幂等；
- 背包满保持待领取；
- 释放空间后重试；
- claimed 保存与恢复；
- 异常 claimed ID 过滤；
- 生产 ServiceHub、GameUI 与新世界 schema。

### 真实桌面

`exploration_milestone_reward_desktop_acceptance.gd` 使用生产：

```text
GameScene
VoxelWorld
ExplorationPlayer
ProspectingService
ExplorationJournalService
ExplorationMilestoneRewardService
InventoryService
SaveService
```

真实执行：

1. 在深渊世界右键探矿；
2. J 键打开日志；
3. 鼠标点击领取地图差异奖励；
4. 验证完整物品包；
5. 完成三个区块；
6. 填满 36 格背包；
7. 点击奖励并验证零部分写入；
8. 释放一个槽位后重试；
9. 正式保存；
10. 返回主菜单并完整重载；
11. 验证 claimed 恢复且物品不重复；
12. 输出 1024×576 截图和日志。
