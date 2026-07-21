# Directional Ladder Climbing

## 目标

梯子是贴墙的方向型世界方块，也是玩家移动状态的一部分。实现必须同时满足：

- 点击墙面的方向就是最终贴墙方向；
- 视觉、目标、放置预览和攀爬接触使用同一方向合同；
- 梯子不以完整方块碰撞阻塞玩家；
- 攀爬检测只读取玩家附近的少量体素；
- 接触、输入、扫描计数和重吸附冷却不进入存档；
- 旧 `ladder` numeric ID 和 canonical 物品继续兼容。

## 状态模型

世界只保存四个方块 ID：

```text
ladder
ladder_east
ladder_north
ladder_west
```

`ladder` 保留旧 numeric ID 25，解释为背后支撑位于南侧的 canonical 状态。其他三个方向只追加到 `BlockRegistry.BLOCK_IDS` 末尾。

全部变体：

```text
item_id       = ladder
visual_parent = ladder
harvest_parent = ladder
shape          = ladder
targetable     = true
climbable      = true
solid          = false
```

因此物品、配方和掉落仍然只有一个 `ladder`，不会出现四套背包物品。

## 朝向合同

`BlockLadderPolicy.resolve_for_face_normal()` 读取玩家点击墙面的外法线。

| 点击墙面外法线 | 放置格到支撑墙偏移 | 方块 ID |
|---|---|---|
| 北 / `FORWARD` | 南 / `BACK` | `ladder` |
| 西 / `LEFT` | 东 / `RIGHT` | `ladder_east` |
| 南 / `BACK` | 北 / `FORWARD` | `ladder_north` |
| 东 / `RIGHT` | 西 / `LEFT` | `ladder_west` |

顶部和底部法线不产生梯子方向。梯子不能放在地面或天花板上。

## 支撑规则

梯子背后的方块必须满足：

```text
显式 ladder_anchor
或
solid = true 且 shape = cube
```

默认不会把下列部分形状视为支撑：

- 台阶；
- 楼梯；
- 门；
- 栅栏；
- 玻璃板；
- 另一个梯子；
- 作物和火把。

放置预览还要求计算得到的支撑格等于玩家实际瞄准的墙格，避免射线、UI Focus 或坐标转换漂移后将梯子贴到另一面墙。

## 几何

梯子厚度固定为：

```text
0.125 格
```

每个方向只有一个 AABB：

```text
南侧支撑：z = 0.875 .. 1.000
东侧支撑：x = 0.875 .. 1.000
北侧支撑：z = 0.000 .. 0.125
西侧支撑：x = 0.000 .. 0.125
```

梯子进入 `BlockShapeGeometry` 的 Partial Geometry 管线，因此：

- 世界视觉网格使用薄片；
- 手持物模型使用同一薄片；
- 放置预览使用同一薄片；
- 玩家重叠检查使用同一薄片；
- `solid = false`，Chunk 不为梯子生成阻挡玩家的三角碰撞。

## 非实体目标

过去 `VoxelTargetResolver` 只把 `solid = true` 的体素作为网格目标。梯子没有实体碰撞，所以无法稳定瞄准、预览或采集。

现在方块可显式声明：

```text
targetable = true
```

网格目标规则为：

```text
solid
或
targetable
```

该变化不会把空气、水、作物或任意透明方块自动加入目标；只有目录明确声明的非实体形状进入该路径。

## 攀爬接触

`BlockLadderPolicy.resolve_contact()` 根据玩家 AABB 创建一个很小的扫描范围。

硬预算：

```text
MAX_CONTACT_CELLS = 18
```

每个候选梯子还必须：

1. 属于方向型梯子族；
2. 仍然拥有合法背后支撑；
3. 玩家身体与其 climb zone 相交。

返回 Snapshot 包含：

```text
active
scan_count
candidate_count
budget_exhausted
block_position
block_id
support_position
support_offset
outward_offset
support_direction
distance_squared
```

不会扫描：

- 全世界方块；
- 全部已加载 Chunk；
- 全部梯子目录；
- 存档中的 block overrides。

## 移动合同

`PlayerMovementController.resolve_ladder_velocity()` 是纯策略端口，生产 `step()` 与单元测试共用。

默认参数：

| 参数 | 值 |
|---|---:|
| 攀爬速度 | 3.2 m/s |
| 攀爬加速度 | 16.0 |
| 横向速度比例 | 0.35 |
| 跳离水平速度 | 2.4 m/s |
| 跳离向上速度 | 4.2 m/s |
| 防立即重吸附 | 0.22 秒 |

输入语义：

```text
W       向上攀爬
S       向下攀爬
松手    速度回到 0，保持位置
A / D   低速横向移动
Space   向上并远离墙面跳开
```

梯子优先级低于流体：玩家进入水中时继续使用流体移动，不同时进入梯子模式。

跳离后启动 0.22 秒重吸附冷却，防止下一物理帧仍与 climb zone 相交而立刻重新进入梯子。

## 生命周期与诊断

生产玩家继承链新增：

```text
ExplorationPlayer
└─ LadderClimbingPlayer
   └─ PrecisionInteractionPlayer
```

`LadderClimbingPlayer` 负责：

- 接触解析；
- 梯子状态进入和退出；
- W/S/Space 输入边界；
- 支撑方向放置上下文；
- 世界切换、输入禁用和 Motion Reset 清理；
- 有界运行诊断。

诊断字段：

```text
active
climbing
reattach_cooldown_seconds
enter_count
exit_count
climb_frame_count
contact_scan_count
contact_candidate_count
last_exit_reason
ladder_position
ladder_block_id
support_direction
budget_exhausted
```

世界切换后计数归零。输入被 Pause、菜单或 UI 阻断时立即离开梯子状态。

## 存档边界

世界继续只保存方向型方块 ID：

```text
world.block_overrides
```

明确不保存：

```text
ladder_runtime
ladder_contact
climb_input
contact_scan_count
reattach_cooldown
enter_count / exit_count
```

重载后梯子的方向自然恢复；玩家必须重新进入实际接触区才能开始攀爬。

## 测试

静态合同：

```text
tests/developer_b/validate_directional_ladders.ps1
```

领域回归：

```text
tests/qa/directional_ladder_regression.gd
```

真实桌面验收：

```text
tests/qa/directional_ladder_desktop_acceptance.gd
```

专项工作流：

```text
.github/workflows/directional-ladder-tests.yml
```

真实桌面流程覆盖：

1. 构建生产墙面与地面；
2. 中心射线瞄准墙面；
3. 绿色薄片预览；
4. 四次真实鼠标右键连续放置；
5. W 上升；
6. 松手悬停；
7. S 下降；
8. Space 向外跳离；
9. 1024×576 截图；
10. 正式保存、返回菜单与完整重载；
11. 方块不重复、物品不复制、瞬时攀爬状态不恢复。
