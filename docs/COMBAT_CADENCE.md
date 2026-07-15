# 战斗节奏、击退与命中反馈合同

## 玩家目标

基础战斗必须形成清晰且可预测的闭环：

```text
准星锁定生物
→ 单击鼠标左键
→ 校验攻击是否已恢复
→ 计算装备后的最终伤害
→ 目标受到伤害、击退和短硬直
→ 成功命中后消耗一次武器耐久
→ HUD 显示命中与恢复进度
```

快速连点不能产生重复伤害、重复耐久消耗，也不能穿透生物去采集后面的方块。

## 模块边界

```text
CharacterProgressionPlayer
          │ 攻击意图
          ▼
CombatService
├─ CombatCadenceRegistry
├─ CombatCadencePolicy
├─ DamageCalculator
└─ EquipmentService durability port
          │ 标准命中上下文
          ▼
BaseCreature.apply_combat_hit
├─ health
├─ knockback velocity
└─ hit stun

CombatService signals
          ▼
CombatFeedbackOverlay
```

### `CombatCadenceRegistry`

从 `data/combat_cadence.json` 读取：

- 默认徒手节奏；
- 武器专用冷却；
- 水平击退；
- 垂直抬升；
- 命中硬直时间。

新增武器时优先扩展数据，不在 Player 或 UI 中判断物品 ID。

### `CombatCadencePolicy`

纯策略只接收：

```text
攻击配置
剩余冷却
目标是否可用
攻击者与目标位置
攻击者朝向
```

输出：

```text
handled
accepted
reason
cooldown_seconds
cooldown_remaining
ready_ratio
knockback vector
```

策略不访问 SceneTree、Inventory、Equipment、UI 或存档。

### `CombatService`

攻击事务的唯一协调者：

```text
读取主手武器
→ 查询 cadence profile
→ 校验目标和冷却
→ DamageCalculator 计算伤害
→ 构建击退与硬直上下文
→ 目标确认命中提交
→ 启动冷却
→ 消耗一次主手耐久
→ 发布结果事件
```

只有目标确认 `applied=true` 后，系统才会：

- 启动冷却；
- 消耗武器耐久；
- 发布成功命中。

冷却拒绝不会修改目标、装备或存档。

### `BaseCreature`

生物只提供通用能力：

```gdscript
is_combat_target_available()
apply_combat_hit(hit, attacker)
get_combat_snapshot()
```

生物不读取玩家背包或武器配置。它只执行已经由 Combat 领域解析好的：

- 最终伤害；
- 击退向量；
- 硬直时间。

### Player 适配

`HarvestEnabledPlayer` 提供 `_try_attack_entity` 扩展钩子。

`CharacterProgressionPlayer` 覆盖该钩子，把真实左键攻击委托给 `CombatService`。采集状态机仍然只负责方块；冷却中的生物攻击会被视为已处理，避免点击穿透到后方方块。

### `CombatFeedbackOverlay`

纯展示层：

- 命中目标和最终伤害；
- 击败结果；
- 攻击恢复百分比；
- 冷却中的明确文字。

它不创建碰撞、不拦截鼠标、不暂停世界，也不修改战斗状态。

## 当前配置

| 状态/武器 | 冷却 | 水平击退 | 垂直抬升 |
|---|---:|---:|---:|
| 徒手 | 0.72 秒 | 2.4 | 0.42 |
| 木剑 | 0.64 秒 | 3.0 | 0.48 |
| 石剑 | 0.62 秒 | 3.2 | 0.50 |
| 铁剑 | 0.60 秒 | 3.5 | 0.52 |
| 金剑 | 0.48 秒 | 3.1 | 0.48 |
| 钻石剑 | 0.56 秒 | 3.9 | 0.58 |

金剑恢复最快但耐久较低；钻石剑拥有最高伤害和击退。数值后续可以只通过数据平衡。

## 输入与界面生命周期

```text
Gameplay
→ 攻击输入可用
→ 命中与冷却反馈可见

Inventory / Crafting / Machine / Container / Pause / Death
→ Player input disabled
→ CombatFeedbackOverlay 隐藏

关闭覆盖层
→ gameplay context
→ 鼠标重新捕获
→ Player input enabled
→ 当前冷却反馈恢复
```

## 存档合同

攻击冷却、击退速度和硬直均为瞬态运行状态：

- 不写入世界存档；
- 不修改 `save_version`；
- 重新进入世界时从可攻击状态开始；
- 装备耐久仍由 Equipment metadata 持久化。

## 最低质量门禁

### 领域回归

`combat_cadence_regression.gd` 覆盖：

- 注册表与五种剑配置；
- 冷却接受与拒绝；
- 击退方向；
- 装备伤害；
- 命中后单次耐久；
- 冷却拒绝零伤害、零耐久；
- 冷却恢复；
- 武器损坏；
- 徒手回退；
- 无效目标；
- 生物击退/硬直能力；
- HUD 无碰撞和阻塞界面隐藏。

### 真实桌面验收

`combat_cadence_desktop_acceptance.gd` 必须使用生产场景验证：

```text
真实 GameScene
真实 VoxelWorld
真实 PlayerScene
真实 Camera3D / RayCast3D
真实鼠标左键
真实 CreatureSpawner
真实物理位移
真实 Inventory Overlay
真实保存事务
```

必须证明：

- 第一次攻击命中；
- 生物产生实际水平位移；
- 立即第二击被冷却拒绝；
- 拒绝不伤害、不扣耐久；
- 冷却结束后再次命中；
- 鼠标和 WASD 始终可恢复；
- 最终 Windows Release 可导出、启动并退出无泄漏。
