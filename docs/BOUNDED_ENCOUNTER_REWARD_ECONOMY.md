# 有界遭遇奖励与弹药经济

> **Iteration 57 更新（2026-08-06）**：本文件中的账本、原子事务、pending、幂等与持久化边界继续有效；奖励 payload 已改为仅发放燧石和火药，禁止成品弹药。当前合同见 `COMBAT_FEEDBACK_INTENSITY_ECONOMY.md`。


## 目标

敌对小队不再只是若干独立生物的掉落集合。完整击败一支由 Encounter Director 编排的小队后，玩家获得一次数据驱动的制造输入补给事务，同时记录该队战斗期间的真实成品弹药消耗和净值。

## 权威边界

- `HostileEncounterDirector` 继续拥有小队编排和成员生命周期；
- 生物自身 `died` 信号是“成员被击败”的唯一来源；
- `RangedCombatService.shot_fired` 是弹药消耗统计来源；
- `InventoryService.transact_items()` 是奖励写入的唯一权威；
- `EncounterRewardService` 只协调信号、账本、去重和待领取重试；
- 不创建第二套伤害、掉落、背包或保存系统。

## 数据模型

`data/encounter_rewards.json` 以 Encounter profile ID 为键，定义：

- 基础补给；
- 高效率射击上限；
- 高效率加成；
- 玩家可获得的显示名称。

首批补给：

- 夜行巡猎补给：燧石；
- 深渊游猎补给：燧石与火药；
- 深渊突袭补给：更多燧石与火药。

注册表只允许 `flint` 和 `gunpowder`，明确拒绝 `arrow`、`light_round` 和 `shotgun_shell` 等成品弹药。

## 原子注册表

`EncounterRewardRegistry` 使用 staged Dictionary：

```text
parse
→ normalize all profiles
→ validate identities, items and quantities
→ any error: preserve previous complete registry
→ all valid: replace published registry once
```

硬边界：

- 最多 16 个奖励 profile；
- 每次奖励最多 4 种物品；
- 单种物品最多 8 个；
- 基础加高效奖励总数最多 16；
- 高效射击阈值最多 16。

## 击败与卸载语义

Reward Service 在遭遇开始时保存初始成员实例 ID，并直接订阅这些成员的 `died` 信号。

- 全部初始成员都触发 `died`：允许奖励；
- 区块卸载、距离清理、返回菜单或世界切换：不计为击败；
- Director 后续 completion 只负责关闭账本；
- 重复 completion 由运行时 claim history 拒绝，不能再次修改背包。

## 最后一击竞态

枪械 hitscan 会先结算目标死亡，再发布 `shot_fired`。因此最后一个成员死亡时，奖励提交必须延迟到当前调用栈结束后，保证最后一发弹药先进入账本，再计算高效率加成和净弹药。

## 弹药归属

- 命中结果携带目标 ID 时，射击归入包含该成员的遭遇；
- 只有一支活动小队时，未命中的射击归入该队；
- 同时存在两队且未命中时，射击记为“无法归属”，不会双重计费；
- 霰弹一次开火只消耗一枚霰弹，不按 pellet 数重复统计。

## 满背包

奖励使用一次 `transact_items({}, additions)` 提交：

- 所有物品同时写入；
- 任一物品没有容量时，整个事务保持不变；
- 奖励进入最多 8 条的待领取队列；
- 背包变化后自动重试；
- 不会出现部分奖励。

## 有界运行时

- 最多 2 个活动遭遇账本；
- 最多 8 个待领取奖励；
- 最多 256 个本世界已领取 ID；
- 世界切换时账本、待领取与 claim history 清零；
- 无 Timer、线程、全图节点扫描或每帧背包复制。

## 持久化边界

以下均为瞬态，不进入 `world.json`：

- 活动奖励账本；
- 成员实例 ID；
- 弹药消耗统计；
- 待领取奖励；
- 已领取 ID；
- Reward HUD 状态。

奖励一旦原子写入 Inventory，便自然随现有背包存档保存，不需要平行 schema。
