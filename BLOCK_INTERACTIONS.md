# 方块交互与容器架构

## 设计目标

方块交互采用“数据描述、服务协调、UI 展示、存档持久化”四层结构。Player 只负责命中检测和发送交互请求，不直接知道工作台、熔炉或箱子的界面细节。

```text
StarWorldPlayer
  └─ RayCast 命中方块
       └─ BlockInteractionService
            ├─ BlockInteractionRegistry  （方块 → 行为描述）
            ├─ CraftingService           （工作台 / 熔炉能力）
            ├─ ContainerStorageService    （容器数据与转移）
            └─ GameUI                    （覆盖层与输入上下文）
```

该边界保证后续增加门、床、告示牌、机器或其他容器时，不需要继续扩大 Player 主脚本。

## 模块职责

### BlockInteractionRegistry

路径：`src/interaction/block_interaction_registry.gd`

注册表只描述静态能力，不保存运行时状态。当前定义：

| 方块 | 行为 | 参数 |
|---|---|---|
| `crafting_table` | `crafting` | `station=workbench` |
| `furnace` | `crafting` | `station=furnace` |
| `chest` | `container` | `type=chest`, `slot_count=27` |

新增交互方块时应优先扩展注册表；只有真正需要新行为类型时才扩展协调服务。

### BlockInteractionService

路径：`src/interaction/block_interaction_service.gd`

职责：

- 根据注册表路由交互；
- 打开工作台、熔炉或容器覆盖层；
- 为位置型容器生成稳定 ID；
- 在拆除容器前执行数据安全策略；
- 容器方块拆除后清理对应存储记录；
- 向 UI 发布用户可理解的失败信息。

稳定容器 ID 使用：

```text
<block-id>@<x>,<y>,<z>
```

例如：

```text
chest@12,24,-8
```

世界坐标和稀疏方块修改一起持久化，因此重新载入同一世界时会命中同一容器记录。

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

### ContainerPanel

路径：`src/ui/container_panel.gd`

UI 只负责：

- 展示容器与玩家背包；
- 将点击转换为转移意图；
- 显示成功或空间不足提示；
- 关闭时释放活动容器。

箱子当前为 27 格。单击某一组物品会在箱子和玩家背包之间移动尽可能多的数量；空间不足时剩余数量保留在源侧。

## 输入与覆盖层

`GameUI` 的覆盖层状态新增：

```text
NONE
INVENTORY
CRAFTING
CONTAINER
PAUSE
DEATH
```

容器使用独立 `container` 输入上下文：

- 显示鼠标；
- 停止玩家 WASD 和世界交互；
- 不暂停昼夜、生物或世界模拟；
- `Esc` 关闭后恢复 `gameplay` 上下文。

暂停和死亡仍由 `SimulationPauseService` 控制真实世界暂停。容器、背包和合成只阻断玩家输入。

## 右键优先级

玩家右键统一执行：

```text
1. 命中可交互方块 → 打开对应交互
2. 否则选中物品可放置 → 放置方块
3. 否则选中物品为食物 → 食用
4. 否则无操作
```

这样选中可放置方块时仍可正常打开面前的箱子或工作台；需要在相邻位置放置方块时，应瞄准非交互表面。

## 工位权限

`C` 只打开随身合成。工作台和熔炉能力只能通过右键对应世界方块获得。

合成面板中的工位选择控件为只读展示，避免绕过世界交互直接使用高级配方。工作台允许同时显示随身配方；熔炉只显示熔炉配方。

## 容器拆除策略

当前策略为数据安全优先：

- 空箱子可以拆除；
- 非空箱子拒绝拆除，并提示先清空；
- 成功拆除空箱子后删除对应容器记录；
- 世界存档与容器状态在同一次保存事务中写入。

未来若改为“拆除后掉落全部内容”，应由独立掉落策略服务实现，而不是在 Player 或 UI 中循环生成物品。

## 存档合同

世界存档新增兼容字段：

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

旧存档没有 `containers` 时，`SaveService` 会补齐空容器状态，不需要破坏性版本升级。

## 扩展准则

新增交互能力时遵循以下顺序：

1. 在注册表声明方块能力；
2. 用独立服务保存领域状态；
3. 由 `BlockInteractionService` 协调行为；
4. 为 GameUI 增加互斥覆盖层或复用已有面板；
5. 将领域状态接入 ServiceHub 的世界事务；
6. 添加真实 Godot 运行时回归，再允许合入 `master`。

禁止的实现方式：

- 在 Player 中直接实例化业务面板；
- 在 UI 中直接修改世界方块或存档字典；
- 用节点路径作为唯一持久化 ID；
- 容器拆除时静默丢弃内容；
- 通过 UI 下拉框绕过世界工位权限。
