# 敌对攻击前摇与可躲避命中合同

## 目标

把敌对生物的近战攻击从“进入范围后立即扣血”改造成玩家能够观察、判断、躲避和打断的可读战斗事务，同时保持现有伤害、存档和生态兼容。

```text
hostile_attacks.json
→ HostileAttackRegistry
→ CreatureFactory
→ BaseCreature attack state machine
→ red telegraph + entity focus
→ player damage / cooldown
```

## 原实现问题

旧路径在 `BaseCreature._choose_direction()` 中发现目标进入 `attack_range` 后立即调用攻击：

```text
进入范围
→ _attempt_attack
→ take_damage
```

这导致：

- 玩家没有观察前摇；
- 后退没有明确躲避窗口；
- 击退和硬直无法表达“打断”；
- 攻击间隔固定写在通用生物基类；
- 伤害来源固定写成 `zombie`；
- 新增敌对物种只能继续增加条件分支；
- 攻击频率和玩家重复伤害保护没有跨领域验证。

## 数据合同

生产数据位于：

```text
data/hostile_attacks.json
```

每个档案包含：

```json
{
  "species_id": "zombie",
  "source_id": "zombie",
  "detection_range": 18.0,
  "attack_range": 1.65,
  "windup_seconds": 0.8,
  "cooldown_seconds": 5.0,
  "cancel_range_multiplier": 1.35,
  "cancel_recovery_seconds": 0.6,
  "target_leash_multiplier": 1.4,
  "telegraph_radius_multiplier": 1.05
}
```

### 字段含义

| 字段 | 含义 |
|---|---|
| `species_id` | 对应生产生物 ID |
| `source_id` | 传给玩家伤害系统的稳定来源 |
| `detection_range` | 生物追踪玩家的水平距离 |
| `attack_range` | 前摇结束时允许命中的真实范围 |
| `windup_seconds` | 命中前可观察和可响应的时间 |
| `cooldown_seconds` | 成功命中后的攻击恢复 |
| `cancel_range_multiplier` | 前摇期间允许目标短暂移动的范围倍率 |
| `cancel_recovery_seconds` | 躲避或打断后的短恢复 |
| `target_leash_multiplier` | 已锁定目标的最大保留距离倍率 |
| `telegraph_radius_multiplier` | 红色预警圈相对命中范围的尺寸 |

运行时 Registry 约束：

- 攻击范围 `0.25..6`；
- 侦测范围必须大于攻击范围；
- 前摇 `0.1..3` 秒；
- 冷却 `0.5..30` 秒；
- 取消范围倍率 `1..3`；
- 取消恢复不能超过完整冷却；
- 目标追踪倍率 `1..3`；
- 预警圈倍率 `0.5..2`。

静态合同还会验证完整攻击冷却不短于玩家的重复敌对伤害冷却，防止生物不断完成攻击但伤害被另一个领域静默丢弃。

## 状态机

攻击状态只有：

```text
idle
windup
cooldown
```

### 开始前摇

只有以下条件全部满足才允许进入 `windup`：

- 目标有效；
- 目标位于真实攻击范围内；
- 当前没有前摇；
- 当前没有攻击冷却。

进入前摇时：

- 不造成伤害；
- 停止主动移动；
- 面向目标；
- 显示红色预警圈；
- 发出 `attack_windup_started`；
- Snapshot 暴露剩余时间和进度。

### 前摇取消

前摇会在以下情况取消：

| 原因 | 稳定 ID |
|---|---|
| 目标失效 | `target_unavailable` |
| 目标离开取消范围 | `target_evaded` |
| 生物被攻击或进入硬直 | `interrupted` |

取消后：

- 不造成伤害；
- 立即隐藏预警圈；
- 进入短恢复；
- 发出 `attack_windup_cancelled`；
- 记录最近取消原因。

### 命中提交

前摇完成时重新验证：

```text
目标仍有效
AND 目标仍在 attack_range 内
AND 生物没有处于硬直
```

只有满足全部条件才调用玩家伤害入口。成功提交后进入完整冷却，并继续发出兼容的 `attack_landed`。

## 视觉合同

预警圈使用纯 `MeshInstance3D`：

- 红色；
- 半透明；
- 自发光；
- 随前摇进度脉冲；
- 无碰撞；
- 不阻挡玩家射线；
- 不写入世界或存档；
- 取消、命中、死亡和清理后立即隐藏。

它是攻击范围的可读提示，不是伤害判定体。真实命中仍由状态机在前摇结束时根据水平距离计算。

## 玩家提示

`PlayerFocusResolver` 只暴露无坐标攻击 Snapshot：

```text
state
windup_remaining
windup_progress
cooldown_remaining
attack_range
cancel_range
target_distance
last_cancel_reason
```

不会暴露目标或攻击路径坐标。

瞄准蓄力中的敌人时，提示为：

```text
正在蓄力 · 0.4 秒后攻击；后退或击退可打断
[鼠标左键] 攻击并打断
离开红色预警圈可躲避
```

## 兼容性

本轮保持：

- 僵尸生产伤害为 1；
- 成功攻击后的五秒节奏；
- 玩家重复敌对伤害冷却为 4.5 秒；
- `attack_landed` 信号；
- 生物掉落和生态权重；
- 世界、玩家和生物存档 schema；
- 方块、物品和 Seed 合同。

旧 `zombie.gd` 后备伤害从错误的 3 修正为与生产数据一致的 1。该后备路径只在生产数据无法注入时使用。

## 扩展规则

新增敌对物种时必须：

1. 在 `creatures.json` 注册具有正伤害的生物；
2. 在 `CreatureFactory.SCRIPTS` 注册实现；
3. 在 `hostile_attacks.json` 注册攻击档案；
4. 使用稳定 `source_id`；
5. 确保冷却不短于玩家重复伤害保护；
6. 提供可观察前摇；
7. 补充正向命中、躲避和打断测试；
8. 完成真实桌面和 Windows Release 验收。

不得在 `BaseCreature` 增加物种专用攻击 `if/elif`。

## 测试门禁

### 静态合同

```text
tests/developer_b/validate_hostile_attacks.ps1
```

验证数据范围、物种、伤害、Factory 组合、生产/后备一致性、玩家伤害冷却、提示接入和全量测试入口。

### 领域回归

```text
tests/qa/hostile_attack_windup_regression.gd
```

覆盖 Registry、纯策略、前摇零早期伤害、躲避取消、短恢复、单次命中、完整冷却、硬直打断、信号、预警圈和提示。

### 真实桌面

```text
tests/qa/hostile_attack_windup_desktop_acceptance.gd
```

使用生产世界、玩家、Spawner、Zombie、Survival 和 SaveService，真实执行：

```text
红色预警
→ S 键后退
→ target_evaded
→ 零伤害
→ 再次进入范围
→ 完整前摇
→ 扣除 1 点生命
→ 冷却防重复
→ 正式保存
```

独立工作流：

```text
Hostile attack windup quality gates
```

完整 PR 还必须通过全部 Runtime、真实桌面矩阵和最终 Windows Release smoke。
