# Architecture Audit · 2026-07-29 · Iteration 53

## 审计目标

在猎弓与真实投射物已经合入后，本轮把远程战斗推进到热武器枪械，同时检查是否会破坏现有可靠边界：

- 半自动、全自动与泵动是否会各写一套攻击代码；
- 弹匣是否错误成为第二份背包或第二个存档领域；
- 换弹是否在开始时提前扣除备用弹药；
- 霰弹是否为每颗弹丸重复触发伤害、击退、UI 和击败；
- 命中扫描是否创建逐弹丸节点、Timer 或世界扫描；
- 鼠标、键盘和手柄是否继续共享逻辑输入；
- 装备中的武器是否能在第一人称正确显示；
- 长时间全自动射击是否仍受运行时预算约束。

## 发现 1：弓箭蓄力模型不能直接表达枪械节奏

猎弓是“按下开始蓄力、松开发射”，枪械则需要：

- 手枪：一次按下只发一枪；
- 卡宾枪：保持主动作时按数据驱动间隔连发；
- 霰弹枪：一次按下发射，受泵动间隔限制。

决策：`RangedCombatService` 扩展为通用主动作状态机，profile 使用 `action_kind`、`delivery_kind` 和 `fire_mode`。旧 `begin_charge/release_charge` 入口继续保留，避免破坏猎弓回归。

## 发现 2：弹匣必须属于武器实例

若弹匣存储在全局枪械服务里，交换两把同型号枪会共享子弹；若另建 firearm save domain，则会与装备状态发生双写。

决策：弹匣写入主手装备实例的 `metadata.magazine_rounds`。`EquipmentService.update_slot_metadata()` 是唯一受控更新入口，限制每次最多 16 个键。武器卸下、交换、保存与重载自然携带自己的弹匣。

## 发现 3：换弹开始时扣弹会造成异常退出损失

错误流程：

```text
按 R
→ 立即扣备用弹
→ 换弹动画进行中
→ 自动保存或异常退出
→ 瞬态换弹消失，备用弹永久减少
```

决策：换弹开始只建立有界瞬态计时；完成时才原子移除备用弹并更新弹匣。弹匣更新失败立即返还备用弹。取消、换武器、返回菜单和 shutdown 均零损失。

## 发现 4：霰弹逐弹丸结算会重复副作用

七颗弹丸如果分别调用 `CombatService`，同一目标会产生七次击退、七条 UI 事实、重复击败和不稳定的受击硬直。

决策：`HitscanRuntimeService` 每枪最多发出 12 条射线，先按目标 instance ID 聚合命中弹丸，再对每个目标调用一次 `CombatService.resolve_projectile_hit()`。聚合结果保留 `pellet_hits`，伤害按命中弹丸数计算。

## 发现 5：命中扫描不需要逐弹丸节点

枪械命中是同一帧完成的查询。为每颗子弹创建 Node、Timer 或 `_physics_process()` 只会增加生命周期与泄漏风险。

决策：命中扫描运行时没有 `_process`、`_physics_process`、Timer、线程或视觉节点。每枪最多 12 条射线、最大 128 格；统计只进入诊断，不进入 `world.json`。

## 发现 6：装备武器在第一人称可能不可见

旧 `FirstPersonItemView` 只读取背包选中格，而装备事务会把主手武器移出背包。因此真正装备的弓或枪可能仍显示为原热栏物品。

决策：第一人称视图模型采用“主手装备优先、背包选中格回退”。程序化模型工厂为手枪、卡宾枪和霰弹枪生成不同的像素化枪身、握把、弹匣、枪管、护木、泵与瞄具，无碰撞且保持近裁剪保护。

## 发现 7：物理输入不得泄漏到枪械业务代码

决策：生产逻辑只读取 `reload`、`primary_action` 等逻辑动作。键盘 `R` 与手柄左肩键在 InputMap/profile 层映射。`RangedCombatService` 与玩家枪械代码中禁止出现 `KEY_R`、`JOY_BUTTON_*` 和 `InputEventJoypad*`。

## 最终结构

```text
data/firearms.json
└─ RangedWeaponRegistry
   ├─ charge/projectile · bow
   └─ firearm/hitscan
      ├─ semi · star_pistol
      ├─ auto · frontier_carbine
      └─ pump · scattergun

CharacterProgressionPlayer
└─ shared primary/reload intent

RangedCombatService
├─ ProjectileRuntimeService · 64 physical arrows
└─ HitscanRuntimeService · 12 rays / 128 blocks / no nodes
   └─ group pellets by target
      └─ CombatService · one authoritative hit per target

EquipmentService
└─ main_hand.metadata.magazine_rounds

FirstPersonItemView
└─ main hand equipment first, selected inventory fallback
```

没有第二伤害系统、没有第二背包、没有第二存档服务、没有 per-bullet Timer、没有现实武器实现信息，只有游戏内抽象参数与有界运行时。
