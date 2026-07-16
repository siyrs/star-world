# 第一人称手持物品与动作反馈合同

## 目标

第一人称体验必须让玩家在不打开背包的情况下确认当前持有物，并通过动作反馈理解采集、攻击、放置、食用和切换是否生效。

本模块只负责表现，不拥有背包、耐久、采集、战斗、世界或存档状态。

```text
InventoryService / BlockHarvestService / Player gameplay events
                         ↓
                FirstPersonItemView
                         ↓
           HeldItemVisualPolicy + MeshFactory
                         ↓
                Camera3D presentation
```

## 领域边界

### `HeldItemVisualPolicy`

纯策略模块，负责：

- 将物品定义分类为方块、工具、食物、工具物或普通物品；
- 将 gameplay action 映射为 swing 或 use 动画；
- 计算移动摇摆、连续采集、攻击挥动、使用抬手与切换下沉的姿态偏移。

禁止访问：

- SceneTree；
- Inventory；
- World；
- Combat；
- Save；
- UI 输入状态。

### `HeldItemMeshFactory`

只生成低成本、无碰撞的表现节点：

- 方块复用生产 `BlockTextureAtlas`；
- 镐、斧、铲、锄、剑使用手柄和头部组合模型；
- 食物、材料、工具物和防具使用低多边形像素化轮廓；
- 所有第一人称材质关闭深度遮挡，避免模型穿进附近方块；
- 不创建 CollisionObject3D、CollisionShape3D、Area3D 或物理节点。

### `FirstPersonItemView`

挂载在：

```text
Player/CameraPivot/Camera3D/HeldItemView
```

它订阅：

- `InventoryService.selected_slot_changed`；
- `BlockHarvestService.harvest_progress_changed`；
- `BlockHarvestService.harvest_cancelled`；
- `BlockHarvestService.harvest_completed`；
- `Player.gameplay_action_reported`。

它不得：

- 修改背包槽；
- 扣除物品或耐久；
- 修改方块；
- 计算伤害；
- 变更鼠标模式；
- 暂停 SceneTree；
- 写入世界存档。

## 玩家体验

### 热键切换

```text
数字键 / 滚轮切换快捷栏
→ 新物品从画面下方抬起
→ 方块显示真实像素纹理
→ 工具显示可辨识低多边形轮廓
```

### 按住采集

```text
真实左键按住
→ HarvestService 产生进度
→ 手持工具持续往复敲击
→ 松开、目标丢失或界面阻断后立即停止
```

### 攻击

成功的玩家攻击事件触发一次挥动。战斗冷却、伤害和耐久仍由 `CombatService` 负责。

### 放置和食用

成功的放置、食用或世界交互触发短促使用动作。失败事务不会伪造成功动作。

### 移动摇摆

仅当玩家在地面移动时启用，幅度由水平速度决定。静止、空中和阻断界面不应产生误导性的步行动画。

### 覆盖层生命周期

打开背包、合成、机器、容器、修理、暂停或死亡界面时：

```text
Player input_enabled = false
→ HeldItemView 隐藏
```

关闭界面并回到 gameplay 后：

```text
Player input_enabled = true
→ 当前物品重新显示
→ 鼠标和 WASD 由原有输入系统恢复
```

## 配置

`data/first_person_viewmodel.json` 控制：

- 基础位置、旋转和缩放；
- 方块、工具和普通物品的相对缩放；
- 切换、挥动和使用时长；
- 移动摇摆频率和幅度；
- 连续采集频率和幅度；
- 挥动与使用旋转；
- 切换下沉距离。

调整手感时优先修改数据，不应把数值散落到 Player 或 UI。

## 性能约束

- 同时只保留一个当前手持模型；
- 方块模型复用已缓存的运行时图集；
- 不创建独立 Viewport、光源、物理体或 Timer；
- 服务引用按低频预算刷新；
- 姿态更新只处理少量向量和一个模型根节点；
- 切换物品时旧模型延迟释放，不保留历史模型。

## 最低测试门禁

### 单元和领域

- 配置可解析且时长有效；
- 物品分类正确；
- action 映射稳定；
- 移动、采集、挥动、使用和切换曲线有可见差异；
- 方块模型复用生产图集和最近邻过滤；
- 五类工具均有多个可辨识部件；
- 全部模型树无碰撞；
- 生产 Player 场景挂载 HeldItemView；
- 采集进度、动作事件、快捷栏切换和输入阻断均能驱动状态。

### 真实桌面

必须使用生产 GameScene、VoxelWorld、Player、Camera3D、RayCast3D 和真实输入事件验证：

```text
选择镐
→ 按住左键采集并观察连续动作
→ 松开停止
→ 数字键切换方块
→ 真实右键放置并观察使用动作
→ 数字键切换剑
→ 真实左键攻击并观察挥动
→ W 移动并观察摇摆
→ E 打开背包后隐藏
→ E 关闭后恢复鼠标、WASD 与手持物
→ 保存世界
```

### 完整发行

最终候选必须继续通过：

1. Runtime 与领域回归；
2. 全部既有真实桌面流程；
3. Windows Release 导出、启动与 180 帧 soak；
4. 日志无脚本错误、解析错误和资源泄漏。
