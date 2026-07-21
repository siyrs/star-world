# Architecture Audit · 2026-07-21 · Iteration 20

## 范围

本轮审计连接型建筑下一阶段：木门的方向、双格状态、开关碰撞、放置、交互、采集、掉落和保存。

## 审计发现

### 单格静态门不符合产品语义

`oak_door` 原本只是一个透明完整方块。它没有上下半、没有打开状态、没有右键交互，也无法在打开后释放通行空间。

### 双格结构缺少事务边界

普通方块放置流程只提交一个体素并消费一个物品。直接连续调用两次 `set_block` 会暴露：

- 下半成功、上半失败；
- 世界成功、物品消费失败；
- 命中上半只拆掉上半；
- 两个半部各掉落一件；
- 开关时上下半状态不一致。

### 新建平行门存档会产生双重事实来源

如果世界既保存门方块，又保存 `doors` Dictionary，崩溃或迁移后可能出现位置、朝向和开关状态不一致。门状态应直接存在于稀疏方块修改中。

### 预览只检查单格

普通放置预览只知道下半目标格。双格门需要同时检查上半占用、下方支撑以及玩家身体与两格薄几何的相交。

### 变体采集规则容易重复维护

16 个门状态若分别写入采集表，会复制相同斧类、硬度与掉落规则。变体应继承 canonical 门规则。

## 决策

### 状态编码

保留旧 `oak_door` 为南向、关闭、下半，并只在目录末尾追加其他 15 个状态。这样保持所有旧 numeric ID 和世界 Seed 兼容。

### 状态所有权

- `BlockDoorPolicy`：纯状态和几何策略；
- `BlockDoorInteractionService`：放置、开关、拆除事务；
- `BlockHarvestService`：继续拥有采集进度，但将结构删除委托给门服务；
- `VoxelWorld`：继续只保存稀疏方块修改。

### 失败语义

所有双格操作必须是“全部成功或恢复原状态”：

```text
放置下半失败 → 零写入
放置上半失败 → 恢复下半
消费物品失败 → 恢复上下半
切换上半失败 → 恢复下半
拆除上半失败 → 恢复下半
```

### 兼容孤立门

旧世界可能已有单格 `oak_door`。这种孤立门不会被自动猜测扩展；玩家可以采集残片并重新放置，以避免改变旧建筑周围方块。

## 实现结果

新增：

```text
BlockDoorPolicy
BlockDoorInteractionService
```

升级：

```text
BlockRegistry
BlockOrientationPolicy
BlockShapeGeometry
PlacementPreviewPolicy
PrecisionInteractionPlayer
BlockHarvestRegistry
BlockHarvestService
ToolProgressionServiceHub
```

## 永久门禁

新增：

```text
tests/developer_b/validate_double_doors.ps1
tests/qa/double_door_regression.gd
tests/qa/double_door_desktop_acceptance.gd
.github/workflows/double-door-tests.yml
```

并接入 `tests/run_all.ps1`。

## 下一阶段

完成木门后，连接型建筑剩余优先级：

```text
梯子贴面方向与真实攀爬
→ 大量门/栅栏/玻璃板 Chunk 重建压力
→ 存档体积与加载时间报告
→ GitHub Actions reusable workflow
```

梯子必须复用同样原则：方向和贴面由方块状态唯一表示，视觉、碰撞、预览和玩家攀爬读取同一个合同，不在 Player 中复制方向规则。
