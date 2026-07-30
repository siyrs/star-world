# 架构审计 · 2026-07-31 · Iteration 57

## 审计范围

本轮从 Iteration 56 的遭遇奖励经济继续向战斗可玩性推进，重点检查：

- 深渊重击者面对玩家掩体时的行为；
- 深渊射手失去视线后的行为；
- 世界结构 mutation、连接方块和 Chunk rebuild 热路径；
- CreatureSpawner、ProjectileRuntime、CombatService 与保存生命周期；
- 长时战斗中的查询、破坏和 AI 尝试上限。

## 发现一：永久掩体可无限封锁精英

原重击者只有普通近战攻击。玩家放置一格低成本墙体后，可以长期阻断其接近或制造安全输出窗口。

直接让重击者破坏所有低硬度方块是不合理的，因为会把玩家的长期基地、门、栅栏、设备和装饰全部变成不可控损耗。

### 决策

引入严格临时掩体白名单：羊毛和玻璃板族。

同时要求它们是 sparse override，证明属于玩家修改后的世界状态。

每次攻击最多 2 块，每只重击者最多 12 块。

## 发现二：永久墙虽然安全，但近战可能隔墙结算

白名单方案首次自审时发现：如果石墙不被 CoverCounter 处理，原重击者仍可能沿旧近战 commit 路径直接伤害墙后的玩家。

这会形成“建筑没有被破坏，但伤害穿墙”的更严重体验问题。

### 决策

服务返回值拆分为：

- `handled=true`：真实破坏了临时掩体；
- `handled=false, blocks_damage=true`：永久掩体阻挡攻击，但没有 mutation；
- 两者都 false：无遮挡，继续原近战结算。

因此永久基地既不会被拆，也不会被穿墙攻击。

## 发现三：逐块 set_block 会重复刷新世界

一次重击可能影响两格墙体。如果生物逐块调用 `set_block()`，会重复触发 Chunk mesh、碰撞、连接方块与结构完整性检查。

### 决策

所有方块统一组成一个 changes 数组，并调用一次：

```gdscript
world.apply_block_mutations(changes, "hostile_cover_break")
```

正式桌面证据要求两格墙体只产生一次 rebuild flush。

## 发现四：射手只会等待原地恢复视线

原深渊射手已有稳定攻击距离、cover destination 和共享投射物 Runtime，但视线被持续阻挡时主要停留在原行为循环。

### 决策

不创建导航网格或全图战术黑板，只增加局部有限换位：

- 连续受阻 1.8 秒；
- 最多 6 个候选；
- 每个目标最多 4 次；
- 每次换位后冷却 3 秒；
- 半径固定 4.5 格。

候选必须同时满足地面、范围、移动通道和弹道约束。

## 发现五：透明方块不等于弹道可穿透

玻璃、玻璃板、栅栏和门在视觉、碰撞与弹道语义上不能简单复用 `transparent` 属性。

### 决策

建立独立纯弹道语义：

- 玻璃和玻璃板阻挡；
- 栅栏保守阻挡；
- 关门阻挡，开门放行；
- 台阶根据射线局部高度判定；
- 植物、梯子、火把和流体放行。

单条射线最多采样 64 个体素。

## 发现六：世界切换轮询可能漏掉短暂边界

上一轮奖励经济已经证明，快速返回并重载同一 world ID 时，仅依赖 0.25 秒轮询可能观察不到中间的空世界状态。

### 决策

CoverCounter 从一开始就监听：

- `start_world_requested`；
- `return_to_menu_requested`。

在信号边界同步清除重击者预算、射手尝试、探针计数与 HUD。

## 最终架构

```text
HostileCoverCounterPolicy
  ├─ 临时掩体白名单
  ├─ 弹道/移动体素语义
  └─ 有界换位方向

HostileCoverCounterService
  ├─ 监听 CreatureSpawner
  ├─ 最多绑定 32 个精英
  ├─ 最多扫描 64 个初始子节点
  ├─ 执行单批次世界 mutation
  └─ 计算局部换位点

LifecycleBoundHostileCoverCounterService
  └─ 显式世界开始/返回边界

CoverAwareAbyssBrute / CoverAwareAbyssMarksman
  └─ 薄适配原攻击和移动状态机
```

## 质量目标

- Headless 验证纯策略、真实工厂组合、单批次、永久基地、生命周期和 3600 秒预算；
- 正式桌面验证真实深渊世界、重击者突破、永久墙零伤、无遮挡命中、射手换位和投射物恢复；
- 相邻结构、门、连接方块、敌对、枪械和 Soak 全部回归；
- 固定最终 SHA 通过完整桌面矩阵和 Windows Release；
- 所有运行时状态不进入存档。
