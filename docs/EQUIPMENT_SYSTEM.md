# 装备、属性与战斗系统合同

## 产品目标

本系统把“获得材料”连接到“制作装备、提升角色、承受更强挑战”的成长循环：

```text
采集资源 → 制作武器/防具 → 装备 → 属性变化
        → 攻击提升 / 伤害减免 → 耐久消耗 → 维修或替换（后续）
```

装备必须对玩家可见、可理解、可保存，并且不能把 Inventory、Player、UI 和 Combat 再次耦合成一个大型脚本。

## 运行时结构

```text
CharacterProgressionServiceHub
├─ EquipmentService
│  └─ EquipmentRegistry ← data/equipment.json
├─ AttributeService
├─ CombatService
│  └─ DamageCalculator
└─ CharacterGameUI
   └─ CharacterInventoryPanel

CharacterProgressionPlayer
└─ 只把移动、攻击与受伤意图委托给领域服务
```

### 状态所有权

| 状态 | 唯一所有者 |
|---|---|
| 背包槽位和数量 | `InventoryService` |
| 已装备物品 | `EquipmentService` |
| 最终角色属性 | `AttributeService` |
| 伤害计算结果 | `DamageCalculator` / `CombatService` |
| 生命与死亡 | `SurvivalService` |
| 面板可见性 | `GameUI` |

UI 只能调用公开方法并渲染 snapshot，不允许直接写 `slots`、`metadata` 或属性 Dictionary。

## 数据合同

### 装备槽位

`data/equipment.json` 定义：

```json
{
  "id": "chestplate",
  "name": "胸甲",
  "allowed": ["armor"],
  "order": 2
}
```

当前槽位：

```text
main_hand
helmet
chestplate
leggings
boots
```

新增槽位时必须同时补充：

1. 数据注册表；
2. UI 展示顺序；
3. Item 的 `equipment.slot`；
4. 数据校验；
5. 领域与桌面测试。

### 可装备物品

ItemRegistry 中的装备能力示例：

```json
{
  "id": "iron_chestplate",
  "category": "armor",
  "max_stack": 1,
  "durability": 240,
  "equipment": {
    "slot": "chestplate",
    "attributes": {
      "defense": 6
    }
  }
}
```

约束：

- 可装备物品必须不可堆叠；
- `equipment.slot` 必须存在；
- Item category 必须被槽位允许；
- 属性 ID 必须存在于装备属性注册表；
- 耐久存放在物品 `metadata.durability`，缺失时按满耐久读取。

## EquipmentService

公开能力：

```text
setup
get_slot
get_snapshot
get_attribute_modifiers
can_equip_item
resolve_item_slot
equip_from_inventory
unequip_to_inventory
consume_durability
consume_armor_durability
serialize
deserialize
```

### 原子装卸事务

装备流程：

```text
验证物品和目标槽
→ 预检旧装备回背包的容量
→ 从准确的背包槽移除 1 件
→ 旧装备回背包
→ 新装备写入装备槽
→ 发布事件与 snapshot
```

任何失败都必须保留原物品，不允许出现：

- 新物品从背包消失；
- 旧装备被覆盖；
- 背包已满却静默丢弃；
- 数量大于 1 的装备槽；
- UI 与领域状态不一致。

## AttributeService

属性由三个层次组成：

```text
基础属性
+ 命名 modifier source
+ EquipmentService 的 equipment source
= 最终 snapshot
```

当前属性：

```text
max_health
attack_damage
defense
movement_speed
mining_speed
```

每个系统只能更新自己的 source，例如：

```text
equipment
buff:speed
map:frozen
skill:mining
```

禁止通过反复 `add_modifier` 累加同一装备，否则加载、替换或 UI 刷新会造成重复属性。

`equipment` source 从装备状态实时重建，不单独持久化；其他标记为 persistent 的 source 可以保存。

## CombatService 与 DamageCalculator

伤害策略为纯计算：

```text
mitigation = min(80%, defense / (defense + 20))
final = max(0.5, raw × (1 - mitigation))
```

零伤害输入仍为零。DamageResult 会包含：

```text
raw_damage
final_damage
defense
mitigation_ratio
absorbed
source
```

职责边界：

- Player 提供攻击或受伤意图；
- CombatService 读取 Attribute snapshot；
- DamageCalculator 不访问场景树；
- SurvivalService 只接收最终伤害；
- 防具仅在实际吸收伤害时消耗耐久；
- 装备武器攻击时消耗主手耐久。

## UI 与交互

`CharacterInventoryPanel` 替代原来的纯背包面板，同时展示：

- 主手、头盔、胸甲、护腿、靴子；
- 最终攻击、防御、预计减伤、移动和采集速度；
- 36 格玩家背包；
- 装备与卸下失败原因。

交互：

```text
E                        打开/关闭角色与背包
右键或双击武器/防具      自动装备
点击已装备槽             放回背包
```

面板必须完整位于 `1024×576`，关闭后恢复鼠标捕获和 WASD。

## 存档与迁移

世界存档新增兼容字段：

```json
{
  "equipment": {
    "version": 2,
    "slots": {}
  },
  "attributes": {
    "version": 1,
    "base": {},
    "sources": {}
  }
}
```

旧存档缺少字段时自动补为空装备和默认属性。装备与世界、玩家、背包、容器、机器、生存、昼夜和引导处于同一次原子保存事务。

## 扩展规范

### 新增防具

1. 在 `items.json` 增加不可堆叠 Item；
2. 定义耐久、装备槽和属性；
3. 增加合成或掉落来源；
4. 通过数据校验；
5. 增加装卸、减伤、耐久和存档测试。

### 新增属性

1. 在 `equipment.json.attributes` 注册；
2. 在 AttributeService 定义合理基础值和下限；
3. 由消费系统读取 snapshot；
4. 在角色面板提供可理解的格式；
5. 补充纯策略与运行时回归。

### 后续方向

- 装备维修；
- 稀有度与随机词条；
- 套装效果；
- 副手和饰品；
- 暴击、击退、元素与状态效果；
- 角色外观预览。

这些扩展不得把规则写回 Player 或 UI。

## 验收门禁

每次装备/战斗改动必须通过：

1. 数据注册表校验；
2. 装卸事务与数量守恒；
3. 属性 source 替换和存档；
4. 武器伤害、防具减伤和耐久；
5. 旧存档迁移；
6. `1024×576` 布局；
7. 真实鼠标装备/卸下；
8. 关闭面板后鼠标与 WASD 恢复；
9. 实际 Windows Release 启动与日志扫描。
