# 连接型方块形状合同

## 目标

玻璃板和木栅栏不再使用与邻居无关的静态整块/单轴模型。视觉、碰撞、放置预览、玩家重叠判断、Chunk 重建和世界重载都从同一个四方向邻接掩码派生形状。

本阶段只处理水平四方向：

```text
EAST = 1
WEST = 2
SOUTH = 4
NORTH = 8
```

掩码是运行时派生值，不是新的世界状态。存档继续只保存原方块 ID 和位置。

## 生产结构

```text
BlockRegistry
└─ connection_family / shape

BlockConnectionPolicy
├─ 读取 east / west / south / north 邻居
├─ 判断同族或完整方块锚点
├─ 生成四位掩码
└─ 为旧玻璃板提供孤立方向兼容

BlockShapeGeometry
├─ pane: 中心柱 + 最多四条连接臂
├─ fence: 中心柱 + 每方向两条横杆
└─ 删除盒子之间完全重合的内部面

PlacementPreviewPolicy
├─ 目标邻接掩码
├─ 将要放置位置的邻接掩码
├─ 同一组连接盒预览
└─ 同一组连接盒玩家重叠判断

VoxelChunk
├─ 从当前世界邻居读取掩码
├─ 生成视觉网格
├─ 生成碰撞网格
├─ 消除相邻方块连接端面
└─ 邻居改变后重建当前/跨 Chunk 网格
```

## 连接规则

### 玻璃板

玻璃板连接到：

- `glass_pane` 与 `glass_pane_ns`；
- 完整、实体立方体，例如石头、木板和玻璃；
- 显式声明 `connection_anchor` 的未来建筑。

玻璃板不连接到：

- 空气；
- 作物、火把、梯子等非实体；
- 台阶、楼梯、床等部分形状；
- 木栅栏等其他连接族。

为了兼容旧世界，完全孤立的玻璃板继续根据原保存方块 ID 保持原轴向：

```text
glass_pane    → east + west
glass_pane_ns → north + south
```

一旦存在真实邻居，形状完全由邻接掩码决定，不再依赖玩家最初朝向。

### 木栅栏

木栅栏连接到：

- 其他木栅栏；
- 完整、实体立方体；
- 显式连接锚点。

孤立栅栏只显示中心柱。每个方向增加两条横杆，因此：

```text
孤立：1 个盒
一侧：3 个盒
两侧：5 个盒
四侧：9 个盒
```

栅栏不再以完整一米立方体阻挡玩家。

## 几何预算

| 形状 | 最大盒数量 | 说明 |
|---|---:|---|
| 玻璃板 | 5 | 中心柱 + 四条臂 |
| 木栅栏 | 9 | 中心柱 + 每方向两条横杆 |

每个盒最多六个面。被相邻盒完整覆盖的内部面在提交网格前删除；跨方块连接端面也会在双方真正连接时删除。

没有为 16 种邻接组合注册 16 个方块 ID。这样可以避免：

- 破坏旧 numeric ID；
- 放大 BlockRegistry、视觉目录和采集目录；
- 邻居改变时重写世界存档；
- 保存冗余派生状态。

## 放置预览

放置预览在玩家点击前读取目标格四个邻居，并输出：

```text
target_connection_mask
placement_connection_mask
target_boxes
placement_boxes
```

玩家看到的绿色线框和半透明填充，与提交后 VoxelChunk 使用的连接盒来自同一个 `BlockShapeGeometry`。

玩家身体重叠检测也使用最终连接盒，不使用整格 AABB 或旧单轴玻璃板盒。

## 世界与 Chunk 重建

`VoxelWorld.set_block()` 仍只保存方块 ID。每次修改会重建：

- 当前 Chunk；
- 当方块位于 Chunk 边缘时，相邻 Chunk。

因此以下操作会立即更新双方形状：

```text
放置相邻玻璃板
拆除中间玻璃板
栅栏连接到石墙
跨 Chunk 边界延伸栅栏/玻璃板
```

加载旧世界或完整重载时，Chunk 根据当前邻居重新派生掩码。不存在 `connection_mask`、`connected_shapes` 或独立连接状态存档。

## 兼容性

保持不变：

- `glass_pane` 和 `glass_pane_ns` numeric ID；
- `oak_fence` numeric ID；
- 玻璃板掉落 `glass_pane`；
- 木栅栏掉落 `oak_fence`；
- 既有方块视觉像素；
- 既有玻璃板孤立方向；
- 世界 `block_overrides` Schema；
- 玩家右键放置和左键采集；
- 原放置预览、背包消耗和保存事务。

## 测试合同

### 静态合同

```text
tests/developer_b/validate_connected_block_shapes.ps1
```

验证：

- 两个连接族及四位掩码；
- 不允许每种掩码新增方块 ID；
- 形状盒数量上限；
- live neighbor 驱动 Chunk 网格；
- 掩码不进入世界存档；
- 预览和重叠检测使用同一掩码；
- 新测试永久接入全量入口和 CI。

### 领域回归

```text
tests/qa/connected_block_shapes_regression.gd
```

覆盖：

- 同族、完整方块和部分形状连接规则；
- 孤立方向兼容；
- 单侧、直线、转角、四向几何；
- 内部面删除；
- 连接感知预览；
- 玩家身体与连接臂碰撞；
- Chunk 边缘读取外部邻居；
- 邻居移除后的网格/碰撞重建。

### 真实桌面验收

```text
tests/qa/connected_block_shapes_desktop_acceptance.gd
```

真实执行：

- GameScene 与 VoxelWorld；
- 真实快捷栏选择；
- 真实中心射线；
- 真实鼠标右键连续放置玻璃板和木栅栏；
- 连接形状预览；
- 拆邻居后即时恢复孤立形状；
- 1024×576 截图；
- 正式保存、返回菜单和完整重载；
- 验证掩码不存档、方块与物品不重复。
