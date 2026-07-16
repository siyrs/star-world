# 修理台与耐久恢复合同

## 产品目标

修理系统把耐久从单向消耗扩展为可规划的资源循环：

```text
制作修理台
→ 收集与装备材质匹配的维修材料
→ 修理背包或已装备的耐久物品
→ 保留名称和其他 metadata
→ 继续探索、战斗与采集
```

它解决三个玩家问题：

1. 高级工具损坏前只能被动替换；
2. 已装备防具维修必须经过不透明的临时操作；
3. 耐久、材料与 UI 如果分别修改，容易产生物品复制或丢失。

## 领域结构

```text
RepairProgressionServiceHub
├─ RepairService
│  ├─ RepairRegistry
│  ├─ RepairPolicy
│  └─ ToolService（只读耐久解释）
├─ RepairEquipmentAdapter
├─ RepairInteractionAdapter
└─ RepairGameUI
   └─ RepairPanel
```

### RepairRegistry

读取 `data/repair_profiles.json`，只负责静态能力：

- 修理台方块；
- 目标物品集合；
- 匹配材料；
- 单次材料数量；
- 单次恢复比例。

一个耐久物品只能属于一个维修方案。数据校验会拒绝重复映射、未知物品、非耐久目标和无效恢复比例。

### RepairPolicy

纯策略输入：

```text
维修方案
+ 物品定义
+ 当前耐久快照
+ 玩家持有材料数量
```

纯策略输出：

```text
是否允许修理
失败原因
当前 / 最大耐久
本次恢复量
目标耐久
材料与数量
```

策略不访问 SceneTree、背包、装备、UI 或存档。

### RepairService

修理事务的唯一协调者。它同时支持：

- 背包槽目标；
- 已装备槽目标；
- 预览；
- 精确材料消耗；
- 耐久 metadata 更新；
- 事务失败回滚；
- 成功与拒绝事件。

事务顺序：

```text
读取目标
→ 查询维修方案
→ 计算预览
→ 再次确认目标没有变化
→ 扣除维修材料
→ 写入目标耐久
→ 写入失败则退回材料
→ 发布 repair_completed
```

### RepairEquipmentAdapter

装备领域已经拥有自己的序列化和校验合同。修理系统不直接写入 `EquipmentService.slots`，而是通过 Adapter：

```text
读取装备快照
→ 只替换目标槽 metadata
→ 交回 EquipmentService.deserialize 校验并发布变化
```

这样 AttributeService 和角色面板仍然只订阅正式的装备变化事件。

### RepairInteractionAdapter

通过 `BlockInteractionService.register_extension()` 接入世界右键：

```text
repair_station
→ 打开 RepairPanel
```

Player 和基础交互服务都不包含修理台 ID、材料或耐久计算。

### RepairPanel

UI 只负责：

- 展示背包与已装备的可修物品；
- 展示当前耐久和进度条；
- 展示材料、持有数量和本次恢复量；
- 把按钮点击转换为 `RepairService.repair_target()`；
- 展示成功或失败原因。

UI 不直接调用 `update_slot_metadata`、`remove_item` 或修改装备字典。

## 内容合同

当前修理材料：

| 装备族 | 材料 | 单次恢复 |
|---|---|---:|
| 木制工具与武器 | 木板 | 最大耐久 25% |
| 石制工具与武器 | 圆石 | 最大耐久 25% |
| 铁制工具、武器与防具 | 铁锭 | 最大耐久 25% |
| 金剑 | 金锭 | 最大耐久 34% |
| 钻石工具与武器 | 钻石 | 最大耐久 20% |
| 皮革防具 | 皮革 | 最大耐久 25% |

恢复量向上取整，且不会超过缺失耐久。

修理台配方：

```text
木板 ×4
石砖 ×2
铁锭 ×2
→ 修理台 ×1
```

修理台需要木镐或更高等级镐才能正常掉落。

## metadata 合同

耐久继续保存在：

```json
{
  "item_id": "iron_pickaxe",
  "count": 1,
  "metadata": {
    "durability": 113,
    "custom_name": "星星的铁镐"
  }
}
```

修理只覆盖 `metadata.durability`，不得删除或改写：

- `custom_name`；
- 批次、来源或任务字段；
- 未来附魔、品质和随机词条。

## 输入与覆盖层

修理台使用独立输入上下文：

```text
repair
```

打开修理面板时：

- 鼠标可见；
- Player 输入关闭；
- 世界模拟继续；
- 不修改 `SceneTree.paused`；
- 与背包、合成、熔炉、箱子、暂停和死亡界面互斥。

关闭后必须恢复：

```text
InputContext = gameplay
MouseMode = captured
Player input = enabled
```

## 存档合同

修理台没有独立运行状态，因此不增加新的世界顶层字段：

- 修理台本身属于世界方块修改；
- 修理材料属于 Inventory；
- 背包目标耐久属于 Inventory metadata；
- 已装备目标耐久属于 Equipment metadata。

旧存档无需迁移。

## 扩展新维修方案

1. 在 `data/items.json` 增加耐久物品或材料；
2. 在 `data/repair_profiles.json` 将目标加入且只加入一个 profile；
3. 确认 `validate_repair.ps1` 通过；
4. 不修改 RepairService，除非事务合同本身发生变化；
5. 补充领域回归和真实桌面验收。

## 禁止实现

禁止：

- 在 Player 中判断修理台或材料；
- UI 直接扣材料或写耐久；
- 为背包和装备各写一套维修公式；
- 失败后吞掉材料；
- 修理时覆盖完整 metadata；
- 为每个装备族复制一个 RepairService；
- 仅通过 signal.emit 代替真实鼠标验收。

## 质量门禁

每次修理系统变更至少通过：

1. 修理数据合同校验；
2. RepairRegistry / RepairPolicy 回归；
3. 背包目标事务；
4. 已装备目标事务；
5. metadata 保留；
6. 满耐久和材料不足保护；
7. 写入失败材料回滚；
8. 组合根和交互扩展挂载；
9. 真实 Camera3D、RayCast3D 和右键打开修理台；
10. 真实按钮点击、鼠标释放与关闭恢复；
11. 完整 Godot 回归；
12. 实际 Windows Release 导出和运行 smoke。
