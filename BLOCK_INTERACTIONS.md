# 方块交互、容器与机器架构

## 设计目标

方块交互采用“数据描述、服务协调、领域执行、UI 展示、存档持久化”分层结构。Player 只负责命中检测和发送交互请求，不直接知道工作台、熔炉或箱子的界面与数据细节。

```text
StarWorldPlayer
  └─ RayCast 命中方块
       └─ BlockInteractionService
            ├─ BlockInteractionRegistry  （方块 → 能力描述）
            ├─ CraftingService           （随身 / 工作台）
            ├─ FurnaceService            （燃料 / 时间 / 产出）
            ├─ ContainerStorageService    （容器数据与转移）
            └─ GameUI                    （互斥覆盖层与输入上下文）
```

该边界保证后续增加门、床、告示牌、机器或其他容器时，不需要继续扩大 Player 主脚本。

## 模块职责

### BlockInteractionRegistry

路径：`src/interaction/block_interaction_registry.gd`

注册表只描述静态能力，不保存运行时状态。当前定义：

| 方块 | 行为 | 参数 |
|---|---|---|
| `crafting_table` | `crafting` | `station=workbench` |
| `furnace` | `machine` | `machine_type=furnace` |
| `chest` | `container` | `type=chest`, `slot_count=27` |

新增交互方块时应优先扩展注册表；只有真正需要新行为类型时才扩展协调服务。

### BlockInteractionService

路径：`src/interaction/block_interaction_service.gd`

职责：

- 根据注册表路由交互；
- 打开工作台、熔炉或容器覆盖层；
- 为位置型容器和机器生成稳定 ID；
- 在拆除前执行内容安全策略；
- 方块拆除后清理对应领域记录；
- 向玩家体验层发布可理解的失败信息。

稳定位置 ID：

```text
<type>@<x>,<y>,<z>
```

例如：

```text
chest@12,24,-8
furnace@12,24,-7
```

世界坐标和稀疏方块修改一起持久化，因此重新载入同一世界时会命中同一容器或机器记录。

### CraftingService

工作台是离散的即时合成领域：

- `C` 只打开随身合成；
- 右键工作台授予 `workbench` 工位；
- 普通配方位于 `data/recipes.json`；
- 工位选择控件只读，不能通过 UI 绕过；
- 输出空间不足时回滚输入。

熔炉不再属于 CraftingService。

### FurnaceService

路径：`src/machine/furnace_service.gd`

熔炉是持续运行的世界机器，负责：

- 原料、燃料、产出三槽；
- 数据驱动的烧制配方和燃料；
- 燃烧余量与加工进度；
- 关闭 UI 后继续运行；
- 暂停时同步停止；
- 保存、加载和有界离线进度；
- 产出满时停止且不误耗物品；
- 非空拆除保护。

完整合同见 [FURNACE_MACHINES.md](FURNACE_MACHINES.md)。

### ContainerStorageService

路径：`src/inventory/container_storage_service.gd`

职责：

- 管理多个位置型容器；
- 使用物品注册表验证 ID 和最大堆叠；
- 在玩家背包与容器之间原子转移物品；
- 在目标空间不足时回滚剩余数量；
- 序列化和反序列化所有容器；
- 防止非空容器被静默删除。

公开合同：

```gdscript
ensure_container(container_id, type, slot_count)
open_container(container_id, type, slot_count)
close_container()
get_slot(container_id, index)
add_item(container_id, item_id, count, metadata)
remove_from_slot(container_id, index, count)
transfer_from_inventory(inventory, inventory_index, container_id)
transfer_to_inventory(inventory, container_index, container_id)
is_empty(container_id)
remove_container(container_id, require_empty)
serialize()
deserialize(data)
```

转移方法返回是否实际移动了至少一个物品。数量守恒由服务负责，UI 不直接修改槽位数组。

### ContainerPanel / FurnacePanel

UI 只负责：

- 展示领域快照与玩家背包；
- 将鼠标点击转换为转移请求；
- 显示成功、容量不足或无效物品提示；
- 关闭时释放活动容器或机器引用。

箱子当前为 27 格，采用整组尽可能多转移。熔炉使用固定三槽和 36 格玩家背包，自动把合法物品路由到原料或燃料槽。

## 输入与覆盖层

`GameUI` 覆盖层：

```text
NONE
INVENTORY
CRAFTING
FURNACE
CONTAINER
PAUSE
DEATH
```

对应非游戏输入上下文：

```text
inventory
crafting
machine
container
pause
death
```

背包、合成、熔炉和容器：

- 显示鼠标；
- 停止玩家 WASD 和世界交互；
- 不暂停昼夜、生物、世界或机器；
- `Esc` 关闭后恢复 `gameplay` 与鼠标捕获。

暂停和死亡仍由 `SimulationPauseService` 控制真实世界暂停，因此熔炉也会同步停止。

## 右键优先级

玩家右键统一执行：

```text
1. 命中可交互方块 → 打开对应交互
2. 否则选中物品可放置 → 放置方块
3. 否则选中物品为食物 → 食用
4. 否则无操作
```

这样选中可放置方块时仍可正常打开面前的箱子、工作台或熔炉；需要在相邻位置放置方块时，应瞄准非交互表面。

## 权限边界

工作台和熔炉能力都必须从真实世界方块获得，但执行模型不同：

```text
工作台 → 临时 crafting station → 立即合成
熔炉   → stable machine ID     → 持续加工
```

不能通过合成面板选择熔炉，也不能用 `C` 打开机器加工。

## 拆除策略

### 箱子

- 空箱子可以拆除；
- 非空箱子拒绝拆除；
- 成功拆除后删除容器记录。

### 熔炉

- 原料、燃料、产出任一槽非空时拒绝拆除；
- 三槽全部为空时允许拆除；
- 剩余热量是瞬态状态，拆除空熔炉时可以丢弃；
- 成功拆除后删除机器记录。

未来若改为“拆除后掉落全部内容”，应由独立掉落策略服务实现，而不是在 Player 或 UI 中循环生成物品。

## 存档合同

容器：

```text
containers {
  version,
  containers {
    "chest@x,y,z": {
      type,
      slot_count,
      slots[]
    }
  }
}
```

机器：

```text
machines {
  version,
  saved_at_unix,
  furnaces {
    "furnace@x,y,z": {
      input,
      fuel,
      output,
      active_recipe_id,
      progress_seconds,
      burn_remaining_seconds,
      burn_total_seconds
    }
  }
}
```

旧存档缺少 `containers` 或 `machines` 时，`SaveService` 会补齐空状态，不需要破坏性版本升级。

## 扩展准则

新增交互能力时遵循：

1. 在注册表声明方块能力；
2. 用独立领域服务保存状态；
3. 由 `BlockInteractionService` 协调行为；
4. 为 GameUI 增加互斥覆盖层或复用已有面板；
5. 将领域状态接入 ServiceHub 的世界事务；
6. 添加领域回归、最低分辨率布局和真实鼠标验收；
7. 通过实际 Windows Release 后才允许合入 `master`。

禁止：

- 在 Player 中直接实例化业务面板；
- 在 UI 中直接修改世界方块、容器数组或机器 Dictionary；
- 用节点路径作为唯一持久化 ID；
- 拆除时静默丢弃物品；
- 通过 UI 下拉框绕过世界工位或机器权限；
- 把持续加工重新塞入 CraftingService。
