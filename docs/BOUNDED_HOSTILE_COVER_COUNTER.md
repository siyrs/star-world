# 有界敌对掩体反制契约

## 目标

Iteration 57 为深渊精英增加结构反制能力，但不允许敌对生物演化为无界拆家系统。

系统只解决两个战斗问题：

1. 玩家使用廉价临时掩体后，重击者能够有限突破；
2. 射手的弹道长期被遮挡时，能够在局部范围有限换位。

## 临时掩体白名单

正式版本只允许破坏：

- `wool`；
- `glass_pane`；
- `glass_pane_ns`。

这些方块还必须存在于当前世界的 sparse override 中，证明它们是玩家放置或玩家修改后的世界状态。

自然生成的同名脆弱方块不会被误认为玩家临时掩体。

## 永久基地保护

以下类别不进入敌对破坏白名单：

- 石头、圆石、石砖和台阶；
- 木板、原木和楼梯；
- 门、栅栏和梯子；
- 箱子、工作台、熔炉、石材切割机和修理台；
- 耕地、作物、床与其他生产设施。

当永久基地挡在重击者和玩家之间时：

- 不破坏方块；
- 不产生世界 mutation batch；
- 该次攻击进入冷却；
- 不允许隔墙伤害玩家。

## 重击者预算

硬限制：

```text
单次攻击最多破坏：2 块
单个重击者生命周期最多破坏：12 块
单次攻击世界批处理：1 次
```

同一次攻击的所有变更必须通过：

```gdscript
world.apply_block_mutations(changes, "hostile_cover_break")
```

禁止从生物脚本直接逐块调用 `set_block()`，避免重复 Chunk mesh、碰撞和连接方块刷新。

拆除临时掩体的这一击只用于突破，不同时穿墙伤害玩家。墙体消失后的下一次无遮挡攻击才按原近战规则结算。

## 射手换位预算

硬限制：

```text
弹道连续受阻：1.8 秒
单次换位候选：最多 6 个
同一目标换位尝试：最多 4 次
换位冷却：3 秒
局部半径：4.5 格
```

候选点必须同时满足：

- 落点可解析到地面；
- 与目标距离处于射手正式攻击范围；
- 射手到落点的脚部和身体通道都可通过；
- 落点到目标拥有可用弹道。

系统不创建导航网格、不进行全图扫描，也不维护跨世界共享黑板。

## 弹道语义

- 关闭的门阻挡弹道；
- 打开的门不阻挡；
- 栅栏保守地阻挡弹道；
- 玻璃与玻璃板虽然透明，仍阻挡弹道；
- 石台阶只阻挡低于半格的射线，高射线可以越过；
- 植物、火把、梯子、水和空气不阻挡弹道。

单次线段采样最多 64 个体素位置。

## 生命周期与存档

掩体破坏数量、重击者生命周期预算、射手换位次数、探针次数和 HUD 消息全部是瞬态运行数据。

它们：

- 监听 `start_world_requested` 和 `return_to_menu_requested`；
- 在世界边界同步清零；
- 不进入 `world.json`；
- 不改变已有 sparse block override 保存格式；
- 不创建第二套结构或 AI 存档域。

被真实破坏的方块仍由现有世界 override 权威保存，因此保存重载后墙体状态正确，但敌对生物的旧预算不会跨会话保留。

## 架构边界

- `HostileCoverCounterPolicy`：纯白名单、射线和候选方向策略；
- `HostileCoverCounterService`：唯一世界查询、批处理和局部绑定所有者；
- `LifecycleBoundHostileCoverCounterService`：Hub 世界边界适配；
- `CoverAwareAbyssBruteCreature`：只决定攻击是否由服务消费；
- `CoverAwareAbyssMarksmanCreature`：复用已有 cover destination 和攻击状态机；
- `HostileCoverCounterOverlay`：只显示瞬态反馈。

稳定的 CreatureSpawner、CombatService、ProjectileRuntime、BatchedVoxelWorld 和 SaveService 继续保持权威。
