# 全仓架构审计 · 第五轮 · 2026-07-17

## 审计范围

本轮以 `master@29ed5e91a0ac49a80856f53c13f72b711bfd284d` 为基线，继续审查：

- 探索日志、里程碑、危险和探矿状态；
- 背包容量、物品写入和合成回滚；
- 新世界初始 schema 与旧世界迁移；
- GameUI 扩展面板与输入上下文；
- ServiceHub 组合方式；
- 全量 Runtime、专项真实桌面和 Windows Release 门禁；
- 产品路线中的“地图特有发现与奖励事务”。

## 总体结论

上一轮已经让探索记录可读、可排序、可迁移，但里程碑仍然只是一组只读勾选项。直接在 UI 中发物品会破坏现有“UI 不写领域状态”的原则；逐个调用 `InventoryService.add_item()` 又无法保证多物品奖励整体成功。

本轮先建立可复用的背包事务，再实现奖励状态所有者和玩家领取闭环。该顺序不仅解决探索奖励，也修复了生产合成服务长期存在的“先扣除、失败再回滚”路径。

## P0 / P1 发现与处置

### 1. 多物品容量不能通过逐项 `can_add_item()` 判断

#### 原因

假设背包只剩一个空槽，奖励包含两个不同物品：

```text
火把 ×4
熟鸡肉 ×2
```

分别调用：

```text
can_add_item("torch", 4)
can_add_item("cooked_chicken", 2)
```

两次都会把同一个空槽计算为可用容量，最终提交时只能放入其中一种。

#### 处置

新增纯 `InventoryTransactionPolicy`，在一个背包副本上模拟全部移除和加入。生产 `InventoryService.transact_items()` 只有在完整计划成功后才替换真实槽位。

### 2. 合成使用补偿式回滚而非原子提交

#### 原实现

```text
移除所有原料
→ 加入产出
→ 若空间不足，删除已加入产出
→ 重新加入原料
```

#### 风险

- 一次业务事务会发出多次中间 `inventory_changed`；
- 观察者可能看到暂时缺少原料或暂时存在产出；
- 依赖补偿操作永远可以恢复；
- 后续若配方支持 metadata 或多产出，回滚复杂度快速上升。

#### 处置

生产 `CraftingService` 改为调用同一个 `transact_items()`：

```text
ingredients → removals
output      → additions
```

失败时没有任何槽位或信号变化，成功时只发布一次背包刷新。

### 3. 里程碑没有奖励状态所有者

#### 风险

若把奖励直接加入日志服务：

- 派生只读模型开始持久化业务状态；
- 日志刷新可能重复发放；
- UI 容易直接写背包；
- 背包满时无法表达“完成但未领取”。

#### 处置

新增 `ExplorationMilestoneRewardService`：

```text
里程碑完成情况  来自 ExplorationJournalService
已领取集合      由 RewardService 唯一持有
待领取状态      由二者确定性派生
物品提交        由 InventoryService 事务完成
```

### 4. 背包满时不能吞掉奖励

奖励只在完整物品包进入背包后写 claimed。空间不足时：

```text
背包不变
claimed 不变
状态保持 claimable
玩家收到可理解反馈
```

释放空间后可以再次领取。

### 5. 新世界初始 schema 缺少近期领域

`SaveService.create_world()` 此前没有显式写入探索状态。虽然 ServiceHub 能在运行时处理空字段，但刚创建的原始世界 JSON 与运行一轮后的 schema 不一致。

本轮让新世界直接包含：

```text
exploration.version = 3
exploration_rewards.version = 1
```

旧世界加载时也补齐这两个字典。

### 6. 地图差异还没有进入成长回报

资源概率、生态和危险已经具有地图差异，但奖励完全没有地图上下文。

本轮先让“初次勘探”奖励具有五地图差异，同时只使用已有且有明确用途的物品，避免新增没有配方或玩法消费场景的死材料。

## 本轮功能闭环

```text
完成探索里程碑
→ J 键打开日志
→ 查看奖励内容
→ 点击领取
→ 原子容量模拟
→ 完整加入背包
→ 保存 claimed
→ 返回菜单
→ 完整世界重载
→ 奖励保持已领取且物品不重复
```

当前七个里程碑全部拥有生产奖励。

## 测试实际覆盖

### 静态

- 奖励与里程碑一一对应；
- 奖励物品存在；
- 五地图初次勘探额外奖励完整；
- 背包事务入口存在；
- 奖励状态版本稳定。

### 纯策略与领域

- 两个物品争用一个空槽；
- 失败零写入、零刷新事件；
- 成功批量事务只刷新一次；
- metadata 堆叠；
- 生产合成事务；
- 锁定、待领取、已领取；
- 重复领取；
- 背包满重试；
- claimed 保存、迁移和异常 ID 过滤。

### 真实桌面

- 真实鼠标右键探矿；
- 真实 J 键；
- 真实 UI 按钮点击；
- 地图差异奖励；
- 填满 36 格背包；
- 零部分写入；
- 释放槽位后重试；
- 正式保存、返回菜单和完整重载；
- 1024×576 截图与日志证据。

## 尚未在本轮大拆的结构债务

### A. ServiceHub 继承链过深

当前生产 Hub 通过多层继承逐步叠加：

```text
Gameplay
→ Equipment
→ Combat
→ Agriculture
→ Fertilizer
→ Rest
→ Repair
→ Husbandry
→ Ranch
→ Exploration
```

每层都覆盖 `_ready`、`_begin_world`、`save_current`、`return_to_menu` 和 `_exit_tree`。继续增长会提高：

- super 调用顺序错误风险；
- 某领域漏存或漏清理风险；
- 测试必须实例化完整世界的成本；
- 功能组合和裁剪难度。

本轮不在奖励功能中同时重写整个生命周期。建议下一架构迭代建立小型 Lifecycle Participant 接口：

```text
register participant
prepare_world
attach_game
activate
serialize_into
clear
snapshot
```

先迁移新领域，再逐步迁移旧层，保持生产场景与存档兼容。

### B. GitHub Actions 专项重复成本继续上升

仓库目前每个领域都拥有高可读性的专项工作流，但重复执行：

- checkout；
- Godot 安装；
- strict import；
- PowerShell 前置；
- 桌面运行器封装；
- artifact 上传。

建议提取 reusable workflow，并让专项只声明：

```text
validators
headless scripts
desktop script
artifact prefix
timeout
```

完整 Windows Release 仍保留为唯一权威最终门禁。

### C. 地图特有材料仍需真实消费场景

本轮只提供地图差异补给，没有为了“看起来有内容”而增加五种新材料。下一步新增材料时必须同时具备：

- 探索发现来源；
- 物品注册；
- 明确配方或功能；
- 探矿与日志表达；
- 存档和目录完整性；
- 平衡与真实桌面验收。

## 下一阶段建议

优先顺序：

```text
地图特有发现与有用途材料
→ 里程碑首次完成通知与奖励批量领取
→ ServiceHub 生命周期参与者
→ 敌对攻击前摇和少量精英变体
→ Machine Base
→ GitHub Actions reusable workflow
```
