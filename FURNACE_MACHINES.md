# 熔炉机器架构

## 目标

熔炉不是另一种“点击即完成”的合成配方，而是拥有位置、库存、燃料、时间和持久状态的世界机器。

实现必须同时满足：

- 玩家能够理解原料、燃料、进度和产出的关系；
- 关闭界面后机器继续运行；
- 暂停游戏时机器与世界同步停止；
- 保存、加载和离线恢复不复制或丢失物品；
- 产出槽满时不误耗原料和燃料；
- 非空机器不能被静默拆除；
- UI 不直接修改机器内部状态；
- 普通合成、机器加工和方块交互保持独立领域边界；
- 新增配方与燃料优先修改数据，不扩张 Player 或 GameUI。

## 运行结构

```text
GameplayServiceHub
├─ CraftingService
│  └─ hand / workbench recipes
├─ FurnaceService
│  ├─ FurnaceRecipeRegistry
│  └─ FurnaceFuelRegistry
├─ BlockInteractionService
└─ GameUI
   └─ FurnacePanel
```

数据源：

```text
data/recipes.json            普通随身与工作台配方
data/furnace_recipes.json    熔炉加工配方
data/fuels.json              燃料与燃烧时长
```

普通合成与熔炉加工不能共用同一条执行路径：

- `CraftingService` 执行离散、原子的材料交换；
- `FurnaceService` 拥有持续时间、燃料和机器库存；
- `BlockInteractionService` 只负责从世界方块路由到对应领域；
- `FurnacePanel` 只发布转移意图并展示快照。

## 稳定机器 ID

每个熔炉通过世界坐标获得稳定 ID：

```text
furnace@x,y,z
```

例如：

```text
furnace@12,24,-8
```

ID 由 `BlockInteractionService.get_machine_id()` 生成。UI 不自行拼接 ID，避免未来世界坐标规则改变时出现两套标识合同。

## 机器状态

单个熔炉状态：

```text
{
  type: "furnace",
  input:  { item_id, count, metadata },
  fuel:   { item_id, count, metadata },
  output: { item_id, count, metadata },
  active_recipe_id,
  progress_seconds,
  burn_remaining_seconds,
  burn_total_seconds
}
```

三个物品槽位的职责固定：

- `input`：只接受 `FurnaceRecipeRegistry` 中存在的输入物品；
- `fuel`：只接受 `FurnaceFuelRegistry` 中存在的燃料；
- `output`：只由机器写入，玩家可以取回。

所有写入必须经过 `ItemRegistry` 和最大堆叠限制。

## 加工状态机

```text
等待原料
  ↓ 有有效配方
检查产出容量
  ↓ 有空间
检查当前燃烧余量
  ↓ 没有余火时消费一个燃料
推进 progress_seconds
  ↓ 达到配方时长
原子消费输入
写入产出
清零本轮进度
  ↓ 仍有输入、燃料时间和产出空间
继续下一轮
```

关键不变量：

1. 产出槽不兼容或已满时，输入、燃料和进度保持不变；
2. 一个燃料物品只在机器确实能够开始工作时消费；
3. 完成一次加工时，输入减少量和产出增加量严格等于配方定义；
4. 机器切换到不同输入配方时，旧进度不能错误继承；
5. 所有计时都有非负下限；
6. 单次离线模拟有迭代和时长上限，不能因恶意存档阻塞主线程。

## 燃料模型

当前燃料：

| 物品 | 燃烧时间 |
|---|---:|
| 煤炭 | 48 秒 |
| 原木 | 9 秒 |
| 木板 | 6 秒 |
| 木棍 | 2 秒 |

燃烧时间是机器领域数据，不写入物品定义，也不硬编码在 UI 中。

增加燃料时只需：

1. 在 `data/fuels.json` 增加合法物品 ID 和正数 `burn_seconds`；
2. 运行数据校验；
3. 补充机器回归中的代表性测试。

## 烧制配方

当前支持：

```text
粗铁    → 铁锭
粗金    → 金锭
沙子    → 玻璃
圆石    → 石头
生鸡肉  → 熟鸡肉
生牛肉  → 牛排
生猪肉  → 熟猪排
```

增加配方时只需扩展 `data/furnace_recipes.json`：

```json
{
  "id": "smelt_example",
  "name": "示例加工",
  "input": {"id": "input_item", "count": 1},
  "output": {"id": "output_item", "count": 1},
  "duration_seconds": 6.0
}
```

输入和输出 ID 必须存在于 `items.json`。一个输入物品当前只对应一个熔炉配方。

## 背包转移合同

`FurnacePanel` 不直接访问机器内部 Dictionary。它调用：

```text
transfer_from_inventory_auto
transfer_from_inventory
transfer_to_inventory
```

自动路由规则：

```text
可烧制物品 → input
合法燃料   → fuel
其他物品   → 拒绝并显示原因
```

转移保证：

- 先计算机器槽位容量；
- 只从背包移除机器能够接受的数量；
- 槽位物品或 metadata 不兼容时拒绝；
- 取回时如果背包空间不足，只转移能够容纳的数量；
- 总物品数量守恒。

## UI 与输入上下文

`GameUI` 增加独立状态：

```text
Overlay.FURNACE
```

对应：

```text
InputContextService.CONTEXT_MACHINE
```

打开熔炉时：

- Player 输入关闭；
- 鼠标可见；
- 世界、生物、昼夜和熔炉继续运行；
- 世界提示和新手引导隐藏；
- 机器界面实时显示进度。

关闭时：

- 释放 active machine 引用；
- 恢复 gameplay context；
- 重新捕获鼠标；
- 不停止机器加工。

暂停菜单和死亡界面通过 `SimulationPauseService` 暂停整个 SceneTree，因此熔炉同步停止。

## 拆除策略

有任一物品槽非空时，熔炉拒绝拆除并提示玩家先清空：

```text
input / fuel / output 任一非空 → 拒绝
三个槽全部为空              → 允许
```

已消费燃料产生的剩余热量是瞬态状态。玩家清空三个槽后拆除熔炉，剩余热量会随机器状态一起丢弃，但不会丢失物品。

这比强制玩家等待余火归零更符合建造体验，同时保持内容安全。

## 保存与离线恢复

世界存档字段：

```text
machines {
  version,
  saved_at_unix,
  furnaces {
    stable_id → machine_state
  }
}
```

保存时，机器状态与以下内容处于同一个原子事务：

- 世界方块修改；
- 玩家位置；
- 玩家背包；
- 箱子；
- 熔炉；
- 生存状态；
- 昼夜；
- 玩家体验状态。

加载时：

1. 校验机器 ID 和槽位物品；
2. 规范化负数或异常计时；
3. 计算 `now - saved_at_unix`；
4. 最多模拟 4 小时离线时间；
5. 最多执行固定次数的加工循环；
6. 产出满、燃料不足或配方无效时立即停止。

旧存档缺失 `machines` 字段时迁移为空机器状态。

## 玩家反馈

机器完成加工会发布领域事件：

```text
item_smelted(machine_id, recipe_id, output)
```

`PlayerExperienceCoordinator` 将其转换为去重 Toast，`AudioService` 播放完成音效。机器领域不直接访问 HUD 或音频播放器。

## 扩展路线

后续机器能力应在现有边界上扩展，而不是扩大 `FurnaceService` 为通用万能类。

建议顺序：

1. 抽象通用 `MachineInventoryPolicy`；
2. 增加机器升级或速度模块；
3. 增加配方队列；
4. 增加输入/输出自动化端口；
5. 增加世界可视状态，如点燃材质或粒子；
6. 对新机器创建独立领域服务或共享明确的 Machine 基础合同。

不建议：

- 在 Player 中判断燃料或配方；
- 在 FurnacePanel 中直接修改机器 Dictionary；
- 把持续加工重新塞进 CraftingService；
- 使用 UI 可见性决定机器是否运行；
- 保存完整区块快照来存储机器内容。

## 验收

最低门禁：

- 数据注册表校验；
- 原料与燃料自动路由；
- 物品数量守恒；
- 多轮燃料加工；
- 产出满时不消费；
- 保存、重载和离线进度；
- 非空拆除保护；
- `machine` 输入上下文；
- 关闭界面后鼠标恢复；
- `1024×576` 界面完整显示；
- 真实桌面鼠标点击原料、燃料、产出和关闭按钮；
- 实际 Windows Release 导出和启动；
- 日志无脚本错误、解析错误和资源泄漏。
