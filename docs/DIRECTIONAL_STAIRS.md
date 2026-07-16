# 四方向楼梯放置合同

## 目标

让玩家持有同一个“木楼梯”物品时，根据自身面向自动得到正确朝向，并保证预览、世界网格、斜坡碰撞、采集掉落和存档完全一致。

```text
玩家面向
→ BlockOrientationPolicy
→ 内部方向方块 ID
→ BlockShapeGeometry
→ VoxelChunk visual/collision
→ PlacementPreviewPolicy
→ 真实右键提交
```

## 兼容策略

本轮不修改世界存档结构，也不改变现有方块的数值 ID。

现有 `oak_stairs` 保留为南向（沿 `+Z` 升高），并在 `BLOCK_IDS` 尾部追加三个内部变体：

| 内部 ID | 升高方向 | rotation_quarters |
|---|---|---:|
| `oak_stairs` | 南 / `+Z` | 0 |
| `oak_stairs_east` | 东 / `+X` | 1 |
| `oak_stairs_north` | 北 / `-Z` | 2 |
| `oak_stairs_west` | 西 / `-X` | 3 |

玩家背包、工作台配方和掉落仍然只使用 `oak_stairs` 物品。三个方向变体都声明：

```text
item_id = oak_stairs
visual_parent = oak_stairs
orientation_family = oak_stairs
```

因此玩家不会看到四种楼梯物品，也不需要迁移已有背包。

## 面向解析

`BlockOrientationPolicy` 使用玩家水平 forward 向量的主轴：

```text
+Z → oak_stairs
+X → oak_stairs_east
-Z → oak_stairs_north
-X → oak_stairs_west
```

斜向观察时选择绝对值更大的水平轴，避免临界方向抖动。

## 几何合同

`BlockShapeGeometry` 先定义南向基础几何，再绕单元格中心按 90° 步长旋转：

- 下半块始终占满 `1 × 0.5 × 1`；
- 上半块移动到升高方向一侧；
- 视觉仍为两个清晰台阶盒；
- 碰撞仍为连续斜坡；
- 所有旋转后顶点保持在 `0..1` 单元格内。

`get_stair_ramp_collision_faces()` 是斜坡碰撞的唯一来源，Chunk 不再复制固定 `+Z` 顶点。

## 放置与预览

`PrecisionInteractionPlayer` 在每次焦点刷新和右键提交前，都通过同一个朝向策略解析实际方块 ID：

```text
快捷栏：oak_stairs
玩家向东
→ 预览 selected_block_id = oak_stairs_east
→ 绿色幽灵格显示东向上半块
→ 右键写入 oak_stairs_east
```

预览与提交之间不存在第二套方向计算，因此不会出现“预览朝东、实际朝北”。

## 视觉继承

方向变体不复制 `block_visuals.json` 条目。`BlockVisualRegistry` 读取 `visual_parent`，让三个变体继承 `oak_stairs` 的原创木板像素纹理。

PowerShell 静态验证同样解析 `visual_parent`，确保别名目标存在且引用的 tile 合法。

## 存档与掉落

世界仍然保存字符串 `block_overrides`：

```json
{
  "12,49,-8": "oak_stairs_east"
}
```

旧世界中的 `oak_stairs` 自动保持南向；新方向变体通过现有字符串存档自然持久化，不增加顶层字段。

采集任意方向楼梯时：

```text
world variant → BlockRegistry.get_item_id() → oak_stairs
```

因此背包永远只得到一个统一的木楼梯物品。

## 测试门禁

### 领域回归

`tests/qa/directional_stair_regression.gd` 覆盖：

- 四个内部 ID 和旧数值 ID 稳定性；
- 玩家 forward 到方向变体映射；
- 旋转后的上半块位置和尺寸；
- 五面斜坡碰撞与唯一向上斜面；
- 像素纹理继承；
- 绿色预览盒；
- 生产 VoxelChunk 网格、顶点和双面碰撞。

### 真实桌面

`tests/qa/directional_stair_desktop_acceptance.gd` 使用生产 Game、VoxelWorld、Player、Camera3D、RayCast3D、Inventory 和 SaveService：

1. 从南、东、北、西四个方位真实右键放置；
2. 验证预览 ID 与实际世界 ID 一致；
3. 对每个斜坡前后端进行真实物理射线测量；
4. 精确消费四份统一楼梯物品；
5. 保存后创建新的生产 VoxelWorld 并重新加载四个方向；
6. 验证旋转楼梯仍掉落统一 `oak_stairs`；
7. 验证 UI 阻断与输入恢复；
8. 输出真实桌面截图。

独立工作流：

```text
Directional stair quality gates
```

同时保留 Godot 全量桌面矩阵与 Windows Release smoke 作为最终合并门禁。
