# 动物饲养与繁殖系统

## 产品目标

动物系统把农业产出、动物资源和长期基地经营连接成一个可持续循环：

```text
种植小麦 / 胡萝卜
→ 喂养鸡、牛、猪
→ 两只同类进入繁殖状态
→ 产生幼崽
→ 幼崽自然成长或继续喂食加速
→ 形成稳定的食物与材料来源
```

本阶段不追求复杂牧场 AI，而是先保证核心循环可理解、可保存、可恢复，并且不会重新把特殊物种判断堆入 Player 或 UI。

## 玩家规则

### 饲料

| 动物 | 饲料 | 来源 |
|---|---|---|
| 鸡 | 小麦种子 | 草方块筛选、小麦收获 |
| 牛 | 小麦 | 成熟小麦收获 |
| 猪 | 胡萝卜 | 野生获取、胡萝卜种植 |

### 成年动物

成年动物在繁殖冷却结束后，可以被正确饲料喂养并进入 30 秒繁殖准备状态。

当两只满足以下条件的同类距离不超过 6 格时，第二次喂养会完成配对：

- 都是成年动物；
- 都处于繁殖准备状态；
- 都不在繁殖冷却；
- 都是同一物种；
- 持久动物数量仍低于上限。

完成后：

- 生成一只幼崽；
- 两只亲本离开繁殖准备状态；
- 两只亲本进入物种对应的繁殖冷却；
- 第二份饲料只在幼崽成功生成后正式提交。

### 幼崽

幼崽使用较小模型比例，并显示剩余成长时间。幼崽会随世界模拟自然成长。

对幼崽使用正确饲料会减少其总成长时间的 20%。喂食不会绕过最大动物数量，也不会把敌对生物纳入饲养系统。

## 模块结构

```text
HusbandryProgressionServiceHub
├─ AnimalHusbandryService
│  ├─ HusbandryRegistry
│  └─ HusbandryPolicy
├─ HusbandryInteractionAdapter
├─ CreatureSpawner
├─ InventoryService
└─ PlayerExperienceCoordinator

HusbandryPlayer
└─ entity interaction capability
```

## 领域职责

### `HusbandryRegistry`

读取 `data/husbandry.json`，只管理静态能力：

- 支持的被动动物；
- 每种动物的饲料；
- 幼崽成长时间；
- 繁殖准备时间；
- 繁殖冷却时间；
- 喂养幼崽的成长缩减比例；
- 配对范围；
- 持久动物上限；
- 离线推进上限；
- 远距离模拟范围；
- 幼崽视觉比例。

注册表不访问场景树、背包、UI 或存档。

### `HusbandryPolicy`

纯策略模块负责：

- 正确饲料判断；
- 成年动物繁殖资格；
- 幼崽成长加速量；
- 冷却和准备状态拒绝原因；
- 配对条件；
- 面向玩家的时间格式。

策略不扣除物品、不生成生物，也不修改世界。

### `AnimalHusbandryService`

运行时状态的唯一所有者：

- 将第一次被正确喂养的野生动物收养为持久动物；
- 保存物种、位置、生命、成长、冷却和繁殖准备状态；
- 统一处理成年喂养、配对、幼崽生成和幼崽喂养；
- 控制最多 24 只持久动物；
- 统一更新幼崽成长和冷却，而不是每只动物创建独立 Timer；
- 在远离玩家时暂停持久动物物理，避免区块卸载后继续坠落；
- 动物死亡后删除对应持久记录；
- 世界重新进入时恢复持久动物；
- 最多推进 6 小时离线成长和冷却。

### `HusbandryInteractionAdapter`

将实体交互和提示能力暴露给 Player 与体验层：

```gdscript
interact_entity(entity, inventory)
get_entity_prompt(focus, selected_item_id)
```

Adapter 不拥有动物状态。

### `HusbandryPlayer`

Player 只负责：

- 从真实 RayCast 获取实体；
- 把右键意图交给实体交互能力；
- 在交互被处理后阻止方块放置或误食；
- 发布通用 gameplay action。

Player 不判断鸡、牛、猪，不扣饲料，不生成幼崽，也不保存动物。

### `HusbandryProgressionServiceHub`

组合根负责：

- 创建 HusbandryService 与 Adapter；
- 注入 ItemRegistry、Inventory、CreatureSpawner、World 和 Player；
- 将 Adapter 注入 PlayerExperienceCoordinator 与 Player；
- 在 gameplay 激活后恢复持久动物；
- 把动物状态加入世界保存事务；
- 将领域事件转换为 Toast 和音效；
- 世界失败、返回菜单和退出时清理引用。

## 自然动物与持久动物

自然生成动物默认仍是临时对象：

- 可以被种群维护系统移除；
- 不写入世界存档；
- 不增加持久状态成本。

只有第一次被玩家使用正确饲料喂养后，动物才进入：

```text
persistent_creatures
```

持久动物：

- 不被普通距离清理；
- 远距离时暂停物理模拟；
- 保存位置和生命周期；
- 死亡后明确移除记录。

这种边界避免把所有随机生成动物写入存档，同时保证玩家实际经营的牧场不会在重新进入世界后消失。

## 事务顺序

### 第一次喂养

```text
读取 RayCast 实体
→ 校验被动物种
→ 校验当前选中饲料
→ 校验动物上限与冷却
→ 从精确选中槽取出一份饲料
→ 收养动物并写入繁殖准备状态
→ 发布领域事件
```

### 完成配对

```text
校验第二只动物
→ 扣除第二份饲料
→ 收养第二只动物（如需要）
→ 查找附近已准备的同类
→ 预留幼崽记录
→ 通过 CreatureSpawner 创建幼崽
→ 成功后提交亲本冷却与幼崽状态
```

若幼崽创建失败：

- 第二份饲料退回；
- 第二只动物恢复交互前状态；
- 第一只动物继续保持原来的准备状态；
- 不产生半完成幼崽记录。

### 幼崽喂养

```text
校验幼崽和饲料
→ 扣除一份饲料
→ 减少成长剩余时间
→ 达到零时切换成年视觉与名称
→ 发布成长事件
```

## 存档合同

```text
husbandry {
  version,
  saved_at_unix,
  animals {
    husbandry_id {
      species_id,
      position [x, y, z],
      stage,
      growth_remaining_seconds,
      breed_cooldown_seconds,
      love_remaining_seconds,
      health
    }
  }
}
```

ID 形如：

```text
animal@<unix>-<counter>
```

旧世界缺少 `husbandry` 时迁移为空状态，不会自动创造动物。

加载时：

1. 校验物种和有限坐标；
2. 按离线时间减少成长、冷却和准备时间；
3. 将已完成成长的幼崽转换为成年；
4. 使用世界安全地面解析器修正位置；
5. 通过 CreatureSpawner 恢复真实生物节点。

## 视觉与交互

准星提示会根据动物状态变化：

```text
牛
生命 10 / 10 · 成年 · 可繁殖
[鼠标左键] 攻击
[鼠标右键] 喂食小麦，进入繁殖状态
```

```text
幼年牛
生命 10 / 10 · 幼年 · 约 6 分 20 秒后成年
[鼠标左键] 攻击
[鼠标右键] 喂食小麦，加速成长
```

没有拿正确饲料时只显示“喜欢：小麦”，避免玩家猜测。

动物交互不会：

- 打开覆盖层；
- 释放鼠标；
- 改变 InputContext；
- 暂停 SceneTree；
- 锁住 WASD。

## 性能边界

- 持久动物上限：24；
- 统一由一个 HusbandryService 更新；
- 不为每只动物创建 Timer；
- 超出 48 格时停止动物物理；
- 自然动物仍受原有种群上限与距离清理；
- 离线模拟最多 6 小时；
- 存档只包含被玩家管理的动物。

## 扩展新物种

1. 在 `data/creatures.json` 注册被动物种；
2. 在 `CreatureFactory` 提供生物脚本；
3. 在 `data/husbandry.json` 添加饲养配置；
4. 确保饲料物品存在；
5. 运行 `validate_husbandry.ps1`；
6. 增加领域、桌面和 Release 验收。

禁止在 Player、InteractionPromptResolver 或 UI 中写：

```gdscript
if species_id == "cow":
    ...
```

物种差异必须留在注册表和领域服务中。

## 质量门禁

最低门禁：

- 数据注册表校验；
- 正确/错误饲料；
- 第一次喂养收养；
- 两只同类配对；
- 幼崽生成和视觉比例；
- 幼崽喂养加速；
- 亲本冷却；
- 动物死亡清理；
- 持久动物不被普通距离清理；
- 保存、迁移和离线成长；
- 真实 Camera3D、RayCast3D 与鼠标右键；
- 鼠标与玩家输入保持正常；
- 最终 Windows Release 导出与启动。
