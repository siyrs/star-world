# 非整块方块几何合同

## 目标

让方块的视觉、碰撞、放置校验、世界预览和第一人称手持模型使用同一份形状定义，避免“看起来是台阶，碰撞却还是整块方块”的体验断裂。

```text
BlockRegistry.shape
→ BlockShapeGeometry
→ VoxelChunk visual/collision mesh
→ PlacementPreviewPolicy
→ WorldInteractionPreview
→ HeldItemMeshFactory
```

## 当前形状

| 方块 | 视觉几何 | 世界碰撞 |
|---|---|---|
| 普通方块 | 1×1×1 | 1×1×1 |
| 石台阶 | 1×0.5×1 | 1×0.5×1 |
| 木楼梯 | 下半块 + 后半块上层 | 前低后高斜坡 |
| 耕地 | 1×0.9375×1 | 1×0.9375×1 |
| 床 | 1×0.5625×1 | 1×0.5625×1 |

楼梯视觉保持清晰的两级轮廓；玩家碰撞使用同方向斜坡，使 CharacterBody3D 可以连续走上楼梯，而不是被半格垂直面卡住。

## 统一形状来源

`BlockShapeGeometry` 是局部几何的唯一来源：

- `get_local_boxes(block_id)`：返回 0～1 单元格内的 AABB 列表；
- `get_bounds(block_id)`：返回组合包围盒；
- `boxes_as_snapshot(block_id)`：提供给预览层的纯数据；
- `world_boxes(block_id, position)`：用于玩家身体重叠校验；
- `face_vertices(...)`：提供世界区块与第一人称模型共用的面顶点；
- `face_enabled(...)`：清理完全位于形状内部的面。

任何新增 partial block 必须先进入该模块，禁止在 Chunk、Player 或 UI 中再复制尺寸常量。

## 世界网格与碰撞

`VoxelChunk` 对每个形状盒分别生成像素纹理面：

- 顶、侧、底继续使用正式纹理图集；
- 最近邻过滤和方向明暗不变；
- 只有完整不透明邻居才能保证覆盖任意 partial face；
- partial block 相邻时宁可保留内部面，也不能错误裁掉暴露表面形成可见孔洞。

楼梯碰撞使用封闭三角棱柱斜坡，视觉仍使用两个阶梯盒。表现和移动职责分离，但占用范围与高度保持一致。

区块碰撞合并为 `ConcavePolygonShape3D` 后必须显式开启 `backface_collision`。这样从上方进行的物理射线和角色地面接触不会因三角面绕序而穿过台阶或楼梯，同时普通完整方块仍沿用原有零分配快速路径。

## 放置事务

`PlacementPreviewPolicy` 使用实际形状盒判断玩家重叠：

```text
石台阶只占下半格
→ 玩家位于上半格时允许放置
→ 玩家身体进入下半格时拒绝
```

策略输出：

```text
target_boxes
placement_boxes
```

`WorldInteractionPreview` 据此显示半高台阶或两段楼梯幽灵格。右键提交仍使用原来的单体素事务和背包回滚，不增加存档字段。

## 第一人称模型

手持石台阶和木楼梯复用相同形状盒与正式像素图集，不再显示成完整立方体。

## 存档兼容

本轮没有新增方块 ID、方向 metadata 或世界顶层字段。已有 `stone_slab`、`oak_stairs`、`farmland`、`farmland_wet` 和 `oak_bed` 存档会在加载后自动使用新几何。

当前楼梯固定为沿本地方块 `+Z` 方向升高。方向型方块状态将在后续独立版本中加入，避免本轮同时改变存档编码。

## 测试门禁

### 领域回归

`tests/qa/non_cube_block_geometry_regression.gd` 覆盖：

- 台阶、楼梯、床和耕地尺寸；
- partial/full cube 分类；
- 玩家重叠校验；
- 生产 VoxelChunk 顶点数量、视觉高度和碰撞网格；
- 第一人称模型形状；
- 世界预览多盒渲染；
- 表现树无碰撞。

### 真实桌面验收

`tests/qa/non_cube_block_geometry_desktop_acceptance.gd` 使用生产 Game、World、Player、Camera、RayCast、Inventory、PlacementPolicy 和 GameUI，验证：

1. 真实右键放置半高石台阶；
2. 真实右键放置两段木楼梯；
3. 台阶物理射线命中高度为半格；
4. 楼梯碰撞前低后高；
5. 生产角色沿楼梯方向走上斜坡；
6. 阻断 UI 隐藏预览，关闭后恢复鼠标和输入；
7. 世界保存事务正常。
