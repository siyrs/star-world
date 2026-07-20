# 石材切割机与通用机器交互合同

## 目标

石材切割机是 Machine Base 上的第一种非 Furnace 生产机器。它不是独立复制的一套“简化熔炉”，而是用来验证以下共享合同可以被第二个真实领域复用：

```text
机器配方
→ 机器领域服务
→ MachineRuntimeScheduler
→ MachineRuntimeParticipant
→ 同一世界保存事务
```

同时，本轮将机器的世界交互从 Furnace 专用实现拆成通用路由：

```text
BlockInteractionService
→ MachineInteractionRouter
   ├─ furnace
   └─ stonecutter
```

## 玩家闭环

```text
工作台制作石材切割机
→ 放置到世界
→ 右键打开真实机器界面
→ 投入石材
→ 无燃料持续切割
→ 查看队列与 ETA
→ 取回建筑材料
→ 保存并完整重载
```

生产配方：

| 输入 | 输出 | 单次时间 |
|---|---|---:|
| 圆石 ×1 | 石砖 ×1 | 3.0 秒 |
| 石头 ×1 | 石台阶 ×2 | 2.5 秒 |
| 石砖 ×1 | 石台阶 ×2 | 2.0 秒 |

工作台制作成本：

```text
圆石 ×6
铁锭 ×2
```

该机器不引入电网、物流管道或新燃料系统。它只验证 Machine Base 的第二领域复用能力。

## 机器领域边界

### StonecutterRecipeRegistry

负责：

- 加载 `data/stonecutter_recipes.json`；
- 校验唯一配方 ID；
- 保证每种输入只有一个隐式配方；
- 规范化输入、输出、数量和加工时间；
- 向服务提供只读配方副本。

Registry 不读取世界、不修改背包，也不推进计时。

### StonecutterService

负责：

- 位置型机器 ID；
- 原料槽和产出槽；
- 输入、输出和背包转移；
- 进度与输出阻塞；
- 队列、剩余时间和整批 ETA；
- 实时与离线推进；
- 序列化和反序列化；
- 非空拆除保护；
- 领域完成信号。

它不创建独立 Timer，不直接写世界文件，也不播放玩家音效。

### MachineRuntimeScheduler

同一个可暂停 Scheduler 现在推进两个生产领域：

```text
furnace
stonecutter
```

一次 Scheduler Batch 会让每个注册领域最多推进一次。当前共享预算继续为：

```text
最大机器领域数          16
最大持久机器实例      4096
单次离线推进上限         4 小时
单次模拟迭代上限       512
```

### MachineRuntimeParticipant

参与者现在负责：

- 创建 StonecutterService；
- 注册 Furnace 和 Stonecutter 两个 Scheduler Domain；
- 注册两个机器交互类型；
- 恢复两个机器领域；
- 把两个领域写入同一个 `machines` Payload；
- 聚合跨领域完成反馈；
- 返回菜单和失败启动时统一清理；
- Shutdown 时确定性关闭两个领域、路由和 Scheduler。

## 通用机器交互

### MachineInteractionRouter

每种机器类型注册：

```text
machine_type
service
GameUI 打开方法
槽位合同
玩家可见名称
非空拆除提示
```

当前生产注册：

| 类型 | UI 端口 | 槽位 |
|---|---|---|
| `furnace` | `open_furnace` | input / fuel / output |
| `stonecutter` | `open_stonecutter` | input / output |

路由最多允许 16 种机器类型，并拒绝：

```text
空类型
重复类型
超过容量
无效服务
服务合同缺失
UI 端口缺失
空槽位合同
```

### BlockInteractionService

世界交互只知道：

```text
block_id
→ machine_type
→ stable machine id
→ MachineInteractionRouter
```

它不再假设所有机器都有 Furnace 的三个槽位。

为现有独立测试和外部薄适配保留兼容路径：直接注入 FurnaceService 时，Furnace 仍可打开和受拆除保护；生产 ServiceHub 使用通用路由。

## UI 合同

生产 `game_ui.tscn` 使用 MachineGameUI，并保留原 Repair 和 Exploration 扩展。

石材切割机使用：

```text
Overlay ID      9
Input Context   MACHINE
```

打开时：

- 释放鼠标；
- 阻断移动、攻击、采集和放置；
- 不停止世界，除非全局暂停；
- 展示输入、输出、进度、配方、队列和 ETA。

关闭时：

- 解除活动机器；
- 隐藏面板；
- 恢复 Gameplay 输入；
- 重新捕获鼠标。

扩展 Overlay ID 统一由 `GameUiExtensionOverlayIds` 管理：

```text
Repair               7
Exploration Journal  8
Stonecutter           9
```

## 存档兼容

Machine Root 保持版本一：

```json
{
  "machines": {
    "version": 1,
    "saved_at_unix": 0,
    "furnaces": {},
    "stonecutters": {}
  }
}
```

兼容规则：

- 旧世界没有 `stonecutters` 时补为空对象；
- `machines.furnaces` 路径不变；
- Furnace 的机器 ID、槽位和计时不变；
- Stonecutter 只增加可选字段；
- 所有旧方块 numeric ID 不移动；
- `stonecutter` 方块只追加到 `BLOCK_IDS` 末尾；
- 瞬时 UI、活动机器、Scheduler Batch 和完成反馈不进入存档。

## 方块与视觉合同

石材切割机完整进入：

```text
BlockRegistry
ItemRegistry
Crafting Registry
BlockInteractionRegistry
Harvest Registry
Block Visual Registry
```

视觉复用 `repair_station` 的已验证工业像素配置，不复制 Furnace 纹理，也不增加未经审计的新视觉生成模式。

采集规则要求木镐或更高，并继续受非空机器保护约束：机器中有原料、产出或未完成进度时，世界方块保持不变。

## 跨领域完成反馈

Furnace 与 Stonecutter 同帧完成时，领域信号仍逐项保留：

```text
item_smelted
item_processed
```

MachineRuntimeParticipant 在帧末合并玩家反馈：

```text
N 条领域完成事件
→ 一条“机器加工完成”消息
→ 一次 craft 音效
```

结构化摘要保留：

```text
completed_jobs
machine_count
machine_type_count
machine_types
recipe_count
item_total
output_counts
```

玩家可见消息最多展示三类产出，待处理完成事件最多 128 条。

## 测试门禁

### 静态合同

`validate_stonecutter_machine.ps1` 验证：

- 方块、物品、工作台配方和采集规则；
- 三条机器配方与输入唯一性；
- 方块 numeric ID 追加；
- 视觉继承；
- Stonecutter Machine Base 端口；
- 通用机器路由；
- UI Overlay 与队列/ETA；
- 存档白名单和运行预算；
- 永久测试接入。

### 领域回归

`stonecutter_machine_regression.gd` 覆盖：

- 配方注册表；
- 严格状态迁移；
- 输入、加工和输出；
- 输出阻塞和拆除保护；
- Furnace + Stonecutter 共享 Scheduler；
- 跨领域完成摘要；
- 通用机器交互路由；
- 生产 ServiceHub、保存和诊断。

### 真实桌面

`stonecutter_machine_desktop_acceptance.gd` 使用生产：

```text
GameScene
VoxelWorld
ExplorationPlayer
BlockInteractionService
MachineInteractionRouter
MachineRuntimeScheduler
FurnaceService
StonecutterService
MachineGameUI
InventoryService
SaveService
```

真实验证：

1. 世界放置后的石材切割机；
2. 中心射线与真实右键；
3. Overlay 输入隔离；
4. 鼠标点击投入石材；
5. Furnace 与 Stonecutter 同批加工；
6. 一条跨领域反馈和一次音效；
7. 非空拆除保护；
8. 鼠标点击取回产出；
9. 保存、菜单清理和完整重载；
10. 1024×576 截图和日志证据。
