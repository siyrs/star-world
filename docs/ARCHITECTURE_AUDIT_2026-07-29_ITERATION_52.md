# Architecture Audit · 2026-07-29 · Iteration 52

## 审计范围

在异常会话恢复合入 `master` 后，本轮审计下一项可玩性跃迁：远程攻击。重点检查：

- 是否能复用现有 CombatService，而不是复制伤害系统；
- 弹药、耐久和投射物创建能否形成无损事务；
- 高速投射物是否会穿透目标；
- 每箭 Timer / 节点数量是否有界；
- 鼠标与控制器能否共享同一输入状态机；
- 飞行状态是否错误进入存档；
- 基础数据扩展是否可能静默覆盖已有 ID。

## 发现 1：现有攻击入口只支持准星即时近战

`HarvestEnabledPlayer._start_primary_action()` 在按下时立即检查 RayCast：命中生物就调用近战，命中方块就进入采集。该模型无法表达“按下蓄力、松开发射”，也不能覆盖远于交互 RayCast 的目标。

决策：在 `CharacterProgressionPlayer` 拦截已装备远程武器的主动作；非远程武器继续调用原近战/采集链。鼠标和控制器最终都调用 `_start_primary_action()` 与 `_cancel_harvest()`，因此不创建第二套输入处理。

## 发现 2：投射物不能直接拥有伤害公式

若箭在碰撞时直接 `target.take_damage(config.damage)`，会绕过：

- 目标实时 defense；
- 统一击退和受击硬直；
- `outgoing_attack_resolved` UI 事实；
- 目标能力检测和击败语义；
- 后续伤害平衡入口。

决策：`ProjectileRuntimeService` 只负责运动和碰撞，命中后调用 `CombatService.resolve_projectile_hit()`。发射时固定基础伤害，撞击时读取目标实时防御。

## 发现 3：逐箭 Timer 会放大节点和调度成本

每支箭一个 Timer 或 `_process` 节点会让调度数量随箭数增长，并使暂停、世界清理和泄漏测试复杂化。

决策：一个 `ProjectileRuntimeService._physics_process()` 管理最多 64 条记录；每条每帧最多一次线段射线。视觉节点没有自己的脚本和 Timer。

## 发现 4：先扣箭再尝试生成会产生物品损失

错误顺序：

```text
remove arrow
→ runtime full / spawn failure
→ arrow lost
```

决策：先验证装备、弹药、冷却和容量；再原子移除 1 arrow；投射物创建失败立即回滚；创建成功后才扣猎弓耐久并进入冷却。蓄力不足、取消、无箭、武器变化和容量已满必须保持箭矢与耐久**零消耗**。

## 发现 5：基础注册表会静默覆盖重复 ID

原 `ItemRegistry` 和 `CraftingService` 逐项写入 Dictionary，同一 ID 后出现者会覆盖前者。引入扩展数据后，这种行为会把内容冲突隐藏成运行时差异。

决策：基础文件和扩展文件先进入 staged Dictionary；重复或无效 ID 使整个加载失败；全部成功后一次提交。自定义 fixture 路径只加载指定文件，避免测试被生产扩展污染。

## 发现 6：飞行状态不属于世界持久状态

保存飞行中的箭会引入跨版本物理重放、碰撞对象身份和半完成攻击事务。

决策：只保存已有 inventory 与 equipment；蓄力、冷却、箭位置、计数器和最近命中全部瞬态。世界开始、失败、返回菜单和 shutdown 确定性 `clear()`。

## 发现 7：单元测试不能替代真实输入与物理

纯策略可以证明插值和范围，却不能证明：

- Godot 物理射线命中真实碰撞体；
- 真实鼠标长按与松开；
- 真实手柄扳机被输入服务轮询；
- Overlay 在软件渲染桌面窗口中可见；
- 保存重载保持弹药和耐久。

决策：专项门禁同时包含纯注册表、真实物理运行时和正式 `game.tscn` 桌面旅程，并继续要求仓库权威 Runtime、桌面矩阵和 Windows Release。

## 最终结构

```text
CharacterProgressionServiceHub
├─ CombatService                 唯一命中结算
└─ RangedCombatService           蓄力/冷却/事务
   └─ ProjectileRuntimeService   64 上限共享运动

CharacterProgressionPlayer
└─ mouse + controller shared primary-action state

CharacterGameUI
└─ CombatFeedbackOverlay
   └─ charge / cooldown / ammo / hit facts
```

没有新世界 schema、没有第二存档服务、没有 per-projectile Timer、没有平行输入服务。
