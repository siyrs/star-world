# Architecture Audit · 2026-07-30 · Iteration 56

## 审计目标

在 Encounter Director 已经能够编排混合小队后，继续建立长期枪械经济闭环，并验证奖励不会被卸载、重复 completion、最后一击时序或满背包破坏。

## 发现 1：单体掉落不能表达小队完成奖励

生物掉落只知道单个成员死亡。它无法判断：

- 一支小队是否全部击败；
- 其他成员是否只是区块卸载；
- 本队消耗了多少弹药；
- 是否满足高效率奖励。

决策：保留生物掉落，新增一个只观察 Encounter 生命周期的奖励协调服务。

## 发现 2：Director completion 不能单独证明击败

`living_member_count == 0` 可能由以下情况产生：

- 全部成员真实死亡；
- 距离清理；
- 区块卸载；
- 返回主菜单；
- 世界切换。

决策：Reward Service 在 encounter start 保存初始成员 ID，并逐个订阅成员 `died`。只有全部初始 ID 都被死亡信号覆盖，才允许发放奖励。

## 发现 3：最后一击先死亡、后发布 shot_fired

枪械 hitscan 的调用顺序为：

```text
resolve shot
→ apply target damage
→ target died
→ hitscan result returns
→ RangedCombatService emits shot_fired
```

若最后一个 `died` 回调立即发奖，最终一发不会进入 shot count，可能错误触发高效奖励并扭曲净弹药。

决策：最后死亡只标记“全员已击败”，奖励提交延迟到当前调用栈之后；或由后续 Director completion 补偿触发。正式桌面测试明确验证 4 次开火都进入首队账本。

## 发现 4：两支小队同时存在时不能把一次 miss 计两遍

命中射击可以通过 target ID 精确归属；未命中没有目标 ID。

决策：

- 命中：按目标成员 ID 归属；
- 只有一队：miss 归入该队；
- 两队以上：miss 记为 unattributed，不重复计入多个账本。

## 发现 5：奖励必须使用背包原子事务

逐项 `add_item()` 会在背包空间不足时产生半奖励。

决策：所有奖励转成一个 additions 数组，通过：

```gdscript
inventory.transact_items({}, additions)
```

一次计划、一次提交。失败时背包保持字节级等价状态。

## 发现 6：满背包需要有界待领取

直接丢弃奖励不可靠，无限 pending 又会形成内存增长。

决策：

- 最多 8 条待领取；
- 监听现有 `inventory_changed`；
- 背包变化后延迟一次原子重试；
- 使用重入保护，事务产生的 inventory_changed 不递归领取；
- 世界切换清除瞬态队列。

## 发现 7：重复 completion 必须幂等

Director 正常 completion、测试重放或未来事件重复都不应二次发奖。

决策：每世界维护最多 256 个已处理 encounter ID，超出后淘汰最旧条目。正常 encounter ID 单调增长，旧 completion 不会被重新发布。

## 发现 8：奖励只应通过 Inventory 持久化

活动账本、pending 和 claim history 不应进入存档。奖励成功写入 Inventory 后，自然由已有存档权威持久化。

没有新增：

- `encounter_rewards`；
- `encounter_economy`；
- `pending_encounter_rewards`；
- 第二份 inventory 文件。

## 发现 9：奖励经济必须有确定性长时证明

等待一小时真实墙钟时间不适合作为每次 PR 门禁。

决策：Headless 逐 45 秒模拟 3600 秒，共 80 场混合遭遇，验证：

- 每场最多 16 件奖励；
- 总产出只随场次数线性增长；
- 高效玩法的轻型弹净产出不无限膨胀；
- 也不会持续负增长导致枪械经济断裂。

## 最终架构

```text
HostileEncounterDirector
  ├─ encounter_started ───────────┐
  └─ encounter_completed ─────────┤
Creature.died ─────────────────────┤
RangedCombatService.shot_fired ────┤
                                   ▼
                       EncounterRewardService
                         ├─ 2 active ledgers
                         ├─ 8 pending rewards
                         ├─ 256 claim ids
                         └─ atomic additions
                                   │
                                   ▼
                        InventoryService.transact_items
                                   │
                     existing authoritative save
```
