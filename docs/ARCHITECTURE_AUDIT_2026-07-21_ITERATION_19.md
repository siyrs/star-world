# Architecture Audit · 2026-07-21 · Iteration 19

## 范围

本轮通读并交叉检查：

```text
BlockRegistry
BlockOrientationPolicy
BlockShapeGeometry
VoxelChunk
VoxelWorld
VoxelTargetResolver
PlacementPreviewPolicy
PrecisionInteractionPlayer
WorldInteractionPreview
HeldItemMeshFactory
现有玻璃板/非整块/放置/Chunk 测试
```

目标是推进路线图中的连接型建筑，同时避免为每种邻接组合增加持久方块变体。

## 发现 1：玻璃板是静态方向，不是连接型建筑

现有玻璃板只有：

```text
glass_pane
glass_pane_ns
```

放置朝向决定永远使用哪一条轴。相邻玻璃板、石墙或邻居拆除都不会改变形状。

问题：

- 相邻玻璃板无法形成转角或十字；
- 玩家必须提前计算朝向；
- 邻居改变后视觉与碰撞不更新；
- 继续扩展会诱导注册 16 种掩码变体；
- 大量派生方块 ID 会污染数字 ID、采集、视觉和存档目录。

决策：保留两个旧 ID 作为孤立方向兼容，但非孤立状态从 live neighbor 派生四位掩码。

## 发现 2：木栅栏仍然是完整立方体

`oak_fence` 有透明木栅栏贴图，但没有 `shape`，因此被：

```text
BlockShapeGeometry.is_full_cube
VoxelChunk full cube mesh
VoxelChunk full cube collision
PlacementPreview full cell box
```

统一当成整块方块。

问题：

- 玩家无法贴近栅栏柱；
- 栅栏之间没有横杆连接；
- 预览显示整块绿色方盒，与最终美术语义不符；
- 所谓“栅栏”只有纹理，没有几何行为。

决策：使用中心柱 + 每方向两条横杆，并进入现有 partial geometry 管线。

## 发现 3：预览和最终网格缺少共同的世界上下文

原 `PlacementPreviewPolicy` 只接收：

```text
selected_block_id
placement_position
player_bounds
```

它不知道四周方块，因此只能调用静态 `get_local_boxes(block_id)`。

如果只在 VoxelChunk 内实现连接，玩家会看到旧形状预览，点击后突然变成另一形状；玩家身体重叠判定也可能允许连接臂生成在角色体内。

决策：Precision Player 将目标格和放置格四方向邻居加入 Focus Snapshot；预览和最终网格都使用同一 ConnectionPolicy + ShapeGeometry。

## 发现 4：连接状态不应成为新的持久领域

一种直接实现是保存：

```json
{
  "block_id": "glass_pane",
  "connection_mask": 9
}
```

这会引入冗余状态：邻居本身已经足以计算掩码。若方块和掩码在崩溃边界不同步，世界会出现永久错误形状。

决策：继续只保存方块 ID。连接掩码只在：

```text
预览
Chunk 网格
碰撞
运行诊断
```

中瞬时存在。

## 发现 5：组合盒会产生内部重叠面

中心柱 + 连接臂/横杆如果直接逐盒提交六个面，会在盒子接触处生成共面内部三角形：

- 增加顶点和碰撞面；
- 透明玻璃板可能产生视觉缝；
- Concave collision 包含无意义内部面；
- 四向组合会线性放大浪费。

决策：ShapeGeometry 在每个盒面提交前，检查是否被另一个盒在同一平面上完整覆盖。只删除可证明完全覆盖的面，不做高成本任意 CSG。

## 发现 6：跨 Chunk 邻接需要现有边界重建合同

VoxelChunk 能读取 Chunk 外邻居，VoxelWorld 也会在修改边界格时重建相邻 Chunk。这是可复用的正确基础。

需要确保连接实现：

- 使用 `_get_neighbor_block`，而不是只读本地数组；
- 不建立第二套邻居缓存；
- 不扫描全部已加载 Chunk；
- 沿用 `set_block → _rebuild_affected_chunks`。

决策：连接形状只在当前网格构建的单个方块周围读取四格邻居，成本严格有界。

## 实现结果

新增：

```text
BlockConnectionPolicy
CONNECTED_BLOCK_SHAPES.md
validate_connected_block_shapes.ps1
connected_block_shapes_regression.gd
connected_block_shapes_desktop_acceptance.gd
connected-block-shapes-tests.yml
```

修改：

```text
BlockRegistry
BlockShapeGeometry
VoxelChunk
PlacementPreviewPolicy
PrecisionInteractionPlayer
HeldItemMeshFactory
README / Roadmap / run_all
```

## 预算与边界

| 项目 | 上限 |
|---|---:|
| 每个方块读取水平邻居 | 4 |
| 玻璃板盒数 | 5 |
| 栅栏盒数 | 9 |
| 持久邻接字段 | 0 |
| 新增掩码方块 ID | 0 |
| 世界级连接扫描 | 0 |

连接计算只发生在：

- 玩家当前 Focus/Preview；
- 受影响 Chunk 网格重建；
- 测试和只读诊断。

## 兼容策略

- 不移动任何 numeric block ID；
- 不删除 `glass_pane_ns`；
- 孤立玻璃板继续根据旧 ID 保持原轴向；
- 两个 pane ID 均掉落 `glass_pane`；
- 木栅栏继续掉落 `oak_fence`；
- 世界 `block_overrides` 不变；
- 旧世界加载后自动派生新连接形状；
- 方块贴图不变。

## 测试验收要求

合并前必须全部通过：

```text
strict Godot import
static connected-shape contract
new domain regression
existing pane / non-cube / stair / preview regressions
real desktop pane and fence placement
neighbor removal rebuild
save / menu / full reload
full Runtime and desktop matrix
Windows Release export and launch
```

## 下一阶段

连接形状基础完成后，下一步优先级：

```text
双格木门与开关状态
→ 梯子贴面方向和真实攀爬
→ 连接形状大规模 Chunk 重建压测
→ 存档体积与加载时间报告
→ GitHub Actions reusable workflow
```

门是持久交互状态，不应直接复用纯派生邻接掩码；需要独立设计上下半一致性、开关原子提交、碰撞切换和破坏任一半的回收规则。
