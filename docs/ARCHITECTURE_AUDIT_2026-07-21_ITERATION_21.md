# Architecture Audit · 2026-07-21 · Iteration 21

## 范围

本轮通读并交叉检查：

```text
BlockRegistry
BlockOrientationPolicy
BlockShapeGeometry
VoxelChunk
VoxelTargetResolver
PlacementPreviewPolicy
WorldInteractionPreview
PrecisionInteractionPlayer
PlayerMovementController
FirstPersonPlayer / ExplorationPlayer
BlockHarvestRegistry / BlockHarvestService
SaveService / Player serialization
GitHub Actions Godot invocation
```

## 审计结论

### 1. 梯子只有目录，没有领域语义

旧 `ladder` 是 `solid=false` 的透明、可收集方块，没有 `shape`、`orientation_family`、`targetable` 或 `climbable`。

结果：

- 世界把梯子渲染为默认完整方块；
- Chunk 不生成碰撞，但射线也无法命中；
- 玩家不能攀爬；
- 方向与墙面无关；
- 存在“物品和纹理已完成，但玩法未完成”的假闭环。

### 2. 玩家朝向不是梯子放置朝向

楼梯和门可以按玩家前向解析，但梯子必须依赖点击墙面的法线。继续复用玩家 yaw 会让梯子在同一面墙上出现错误方向，甚至把几何放到没有支撑的一侧。

### 3. 非实体形状缺少显式目标能力

`VoxelTargetResolver` 只接受 `solid`，导致没有碰撞的装饰或交互薄片无法瞄准。直接把梯子改为实体会重新造成整格阻挡。

解决：增加显式 `targetable` 能力，而不是改变 `solid` 含义。

### 4. 攀爬不能成为世界扫描

错误实现包括：

```text
每帧遍历所有 Chunk
每帧遍历 block_overrides
每个梯子创建 Area/Timer/Node
建立全局梯子目录
```

这些成本随世界或梯子数量增长。

解决：只扫描玩家 AABB 附近最多 18 个体素，成本与世界大小无关。

### 5. 攀爬需要独立移动边界

只在普通重力后强行修改 `velocity.y` 会出现：

- 每帧先坠落再抬升；
- 松手缓慢下滑；
- 跳跃立即重新吸附；
- 水和梯子状态冲突；
- UI 禁用输入后仍保持接触。

解决：将梯子作为 `PlayerMovementController.step()` 的显式模式，并提供纯策略 `resolve_ladder_velocity()`。

### 6. 瞬时攀爬状态不能持久化

方向型梯子属于世界方块状态；当前接触、W/S 输入、扫描预算和重吸附冷却属于运行状态。建立 `ladders` 或 `ladder_runtime` 存档会制造第二事实来源并在重载时错误恢复移动状态。

### 7. 新工作流仍存在 CI 假绿缺口

PR #48 已将旧工作流迁移到 `Invoke-Godot.ps1`，解决 Windows GUI 子系统 Godot 不被 PowerShell 等待的问题。随后合入的双门工作流仍直接调用 `godot --headless`，可能在真实回归尚未结束时退出步骤。

本轮同时把双门专项迁移到可靠等待包装器，并让梯子静态合同永久检查该规则。

## 最终结构

```text
BlockRegistry
├─ ladder (legacy ID 25)
├─ ladder_east
├─ ladder_north
└─ ladder_west

BlockLadderPolicy
├─ face normal → orientation
├─ support validation
├─ partial local box
├─ climb zone
└─ bounded 18-cell contact

ExplorationPlayer
└─ LadderClimbingPlayer
   ├─ Precision Interaction
   ├─ Placement support context
   ├─ Ladder contact lifecycle
   └─ PlayerMovementController ladder mode
```

## 兼容性

保持不变：

- `ladder` numeric ID 25；
- `ladder` item ID；
- 工作台梯子配方；
- canonical 视觉纹理；
- 世界 sparse block override Schema；
- 玩家存档 Schema；
- 既有地面、空中、游泳和输入上下文；
- 旧楼梯、门、玻璃板和栅栏方向合同。

只追加：

```text
ladder_east
ladder_north
ladder_west
```

## 预算

| 合同 | 上限 |
|---|---:|
| 每物理帧梯子候选体素 | 18 |
| 梯子几何盒 | 1 |
| 梯子厚度 | 0.125 格 |
| 重吸附冷却 | 0.22 秒 |
| 每梯子 Node / Timer | 0 |
| 世界级梯子扫描 | 0 |
| 新持久领域 | 0 |

## 验收策略

### 静态

- numeric ID；
- 四状态；
- 支撑规则；
- 几何和 targetable；
- 移动参数和纯策略；
- 瞬时状态不保存；
- 新旧工作流都必须使用可靠等待包装器。

### 领域

- 四面墙方向；
- 完整方块支撑；
- 部分形状拒绝；
- 非实体射线目标；
- 18 格接触预算；
- W/S/悬停/跳离；
- 生产玩家继承和保存边界。

### 真实桌面

- 真实中心射线；
- 真实绿色预览；
- 真实鼠标右键连续放置；
- 真实 W/S/Space 输入；
- 可视化截图；
- 正式保存、菜单清理和完整重载。

## 下一阶段

优先级调整为：

```text
连接型方块大规模 Chunk 重建压力
→ 1,000+ 门/栅栏/玻璃板/梯子混合边界
→ 存档体积、保存时间、加载时间和首帧可玩时间报告
→ Geometry / Preview 连接状态缓存只在证据需要时引入
→ GitHub Actions reusable workflow
→ 再评估更复杂的建筑形状
```
