# 方块采集裂纹反馈合同

## 目标

让按住鼠标左键采集方块时拥有清晰、连续、与真实采集进度一致的世界反馈，同时保持 Harvest 领域仍是进度和提交的唯一所有者。

```text
BlockHarvestService.harvest_progress_changed
                ↓
       MiningFeedbackPolicy
                ↓
       MiningCrackOverlay
                ↓
   目标体素六面程序化裂纹纹理
```

裂纹只表达现有采集事务状态，不修改方块、背包、工具耐久、输入上下文或存档。

## 玩家体验

- 按住左键开始有效采集后，目标方块六个表面出现裂纹；
- 裂纹按实际 `ratio` 分为十个阶段；
- 采集越接近完成，裂纹覆盖越密集；
- 松开左键后立即消失；
- 换目标时复用同一个 Overlay 并移动到新体素；
- 目标丢失、受保护、背包已满等拒绝结果会清理裂纹；
- 采集完成后裂纹消失，正常掉落、耐久和教程事件保持不变；
- 打开背包、机器、修理、暂停或死亡界面时，Player 输入被关闭，裂纹同步隐藏；
- 返回 gameplay 后不会恢复旧裂纹，必须重新开始一次合法采集。

## 模块边界

### `MiningFeedbackPolicy`

纯策略输入：

```text
progress_snapshot
input_enabled
```

输出：

```text
visible
reason
ratio
stage
block_id
block_position
target_key
```

规则：

```text
stage = clamp(floor(ratio × 10), 0, 9)
```

策略不访问 SceneTree、World、Inventory、Player 或材质。

### `MiningCrackTextureFactory`

- 程序化生成十张 16×16 RGBA 裂纹纹理；
- 每一阶段只增加裂纹路径，不减少已有覆盖；
- 使用固定路径和颜色，不依赖随机数；
- 缓存 `Image` 与 `ImageTexture`；
- 测试中可以清理缓存并验证重新构建结果一致；
- 不引入外部纹理或第三方资源。

### `MiningCrackOverlay`

- 生产 Player 根节点下唯一的世界空间表现节点；
- 使用稍微放大的 `BoxMesh` 避免与方块表面 Z-fighting；
- 纹理过滤为最近邻；
- 使用透明材质和无光照裂纹；
- 深度测试保持开启，裂纹不会穿透其他方块显示；
- 无 `CollisionObject3D`，不会改变 RayCast、移动或放置；
- 只订阅 HarvestService 的 progress/cancel/completed/rejected 信号；
- 每次目标变化复用已有 MeshInstance，不创建持续增长的节点。

## 事务约束

裂纹反馈永远不能成为采集事务参与者：

```text
世界移除失败
背包空间不足
目标改变
工具资格不足
输入上下文关闭
```

这些情况由 `BlockHarvestService` 决定结果。Overlay 只根据结果显示或清理。

## 存档兼容

本系统没有持久状态：

- 不新增世界顶层字段；
- 不修改方块 ID；
- 不修改背包 metadata；
- 不修改 Player 序列化；
- 旧世界与新世界行为一致。

## 自动化测试

### `mining_crack_feedback_regression.gd`

覆盖：

- 十阶段比例映射；
- 无进度、无输入和非法坐标拒绝；
- 十张 16×16 纹理；
- 裂纹覆盖单调增长；
- 最终阶段明显密于初始阶段；
- 缓存重建确定性；
- Overlay 信号生命周期；
- 负坐标目标；
- 换目标复用；
- UI 阻断；
- cancel/completed/rejected 清理；
- 无碰撞合同；
- 生产 Player 场景挂载。

### `mining_crack_feedback_desktop_acceptance.gd`

真实使用：

```text
生产 GameScene
生产 VoxelWorld
生产 Player / Camera3D / RayCast3D
生产 Inventory / HarvestService / InputContext / GameUI
真实鼠标左键按住和释放
真实滚轮切换工具
真实 E 覆盖层
真实保存事务
```

验收流程：

```text
木镐采集钻石矿
→ 捕获中途裂纹和手持工具动画
→ 松开后裂纹消失
→ 滚轮切换木铲
→ 按住采集泥土直到真实完成
→ 方块移除、掉落正常、裂纹清理
→ 再次开始采集
→ E 打开背包中断采集
→ 裂纹和手持物隐藏
→ 关闭背包后输入恢复且旧裂纹不回流
→ 保存世界
```

## 后续扩展

当前合同可以继续支持：

- 不同材质的裂纹颜色；
- 采集碎屑粒子；
- 工具命中音节奏；
- 服务端权威采集进度；
- 辅助功能中的裂纹对比度选项。

这些扩展不应把事务职责移入表现层。
