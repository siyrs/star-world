# 精确瞄准与方块放置预览合同

## 目标

方块建造必须满足一个可验证的玩家合同：

```text
玩家看到的准星目标
= HUD 描述的目标
= 白色目标框
= 左键采集目标
= 右键交互目标
= 右键放置所依附的表面
```

当玩家手持可放置方块时，右键提交之前必须能够看见最终格子：

```text
绿色幽灵格  可放置
红色幽灵格  不可放置
```

颜色只用于快速识别，HUD 必须同时给出文字原因，不能让关键结果只依赖颜色视觉。

## 模块边界

```text
VoxelTargetResolver
        │
        ▼
PlayerFocusResolver
        │
        ├─ hit_position
        ├─ hit_block_id
        ├─ placement_position
        ├─ placement_target_block_id
        └─ face_normal
        │
        ▼
PrecisionInteractionPlayer
        │
        ├─ PlacementPreviewPolicy
        ├─ interaction_focus_changed
        └─ actual placement commit
        │
        ├───────────────┐
        ▼               ▼
WorldInteractionPreview   InteractionPromptResolver
3D 展示                    文字与操作提示
```

### `VoxelTargetResolver`

统一解析真实 `RayCast3D`：

- 玩家真正看见的命中体素；
- 标准六轴表面法线；
- 唯一的相邻放置体素；
- 相邻格当前方块。

采集、交互、焦点和放置不能各自重新计算碰撞点。

### `PlacementPreviewPolicy`

纯策略模块，只接收：

```text
当前 focus
选中的 block_id
玩家 AABB
```

输出标准快照：

```text
target_visible
target_position
placement_visible
placement_position
selected_block_id
valid
reason
occupied_block_id
```

当前拒绝原因：

```text
no_focus
no_block_selected
placement_unavailable
occupied
player_overlap
```

策略不访问 SceneTree、Inventory、UI、World 或存档。

### `PrecisionInteractionPlayer`

Player 只承担适配职责：

- 把当前选中的方块和玩家边界交给策略；
- 将预览快照附加到 `interaction_focus_changed`；
- 快捷栏变化后刷新预览；
- 实际放置提交再次调用同一策略。

预览允许而提交拒绝，或预览拒绝而提交成功，均属于合同错误。

### `WorldInteractionPreview`

纯世界展示节点：

- 白色线框：真实命中体素；
- 绿色线框与半透明填充：有效放置格；
- 红色线框与半透明填充：无效放置格；
- 不创建 `CollisionObject3D`；
- 不修改世界；
- 不修改背包；
- 不保存状态；
- 不拦截输入。

预览由焦点事件驱动，不执行每帧世界扫描。

### `InteractionPromptResolver`

有效放置示例：

```text
绿色预览格  -2, 24, -4 · 可以放置
[鼠标右键] 放置木板
```

无效放置示例：

```text
目标格已被木板占用
无法放置：目标格已被木板占用
```

或：

```text
不能放在角色身体内
```

## 输入生命周期

```text
Gameplay
→ 显示目标和放置预览

Inventory / Crafting / Machine / Container / Pause / Death
→ Player input disabled
→ 预览立即隐藏

关闭覆盖层
→ gameplay context
→ 鼠标重新捕获
→ Player input enabled
→ 根据当前焦点重新显示预览
```

预览自身不得改变 `InputContext`、鼠标模式或 `SceneTree.paused`。

## 放置事务

```text
真实射线解析
→ 预览策略评估
→ valid=true
→ world.set_block
→ 精确消费当前选中槽位一份物品
→ 消费失败则回滚世界方块
→ 发布 place 事件
→ 重新解析焦点
```

普通方块不能：

- 覆盖已有体素；
- 放入玩家身体；
- 使用与预览不同的坐标；
- 因靠近边缘而漂移到上方；
- 在失败时消耗物品。

## 扩展规则

增加门、台阶、半砖或多方块结构时，不应绕过预览合同。

建议扩展方式：

```text
PlacementShapePolicy
→ 接收统一命中合同
→ 输出一个或多个候选格
→ 预演碰撞与占用
→ WorldInteractionPreview 渲染对应形状
→ 提交服务原子写入
```

禁止在 UI 或具体方块脚本中自行读取碰撞点并计算放置格。

## 最低质量门禁

### 领域与场景回归

`placement_preview_regression.gd` 覆盖：

- 空相邻格可放置；
- 已占用格拒绝；
- 玩家身体重叠拒绝；
- 空手只显示目标框；
- 有效与无效文字提示；
- 生产 Player 挂载预览；
- 预览树不含碰撞对象；
- gameplay input 关闭时预览隐藏。

### 真实桌面验收

`placement_preview_desktop_acceptance.gd` 必须在真实生产场景中验证：

```text
Camera3D 中心射线
→ 石块侧面白色目标框
→ 同高度相邻绿色幽灵格
→ 真实右键
→ 木板写入绿色格
→ 上方格保持为空
→ 同一表面立即变成红色已占用预览
→ 再次右键不覆盖、不扣物品
→ E 打开界面后预览隐藏
→ E 关闭后鼠标与输入恢复
```

同时保存有效和无效两张截图。

### 完整发行门禁

合入 `master` 前仍必须通过：

- 完整 Runtime 与领域回归；
- 全部既有真实桌面矩阵；
- 完整新手教程真实流程；
- Husbandry、Ranch、Repair 专项；
- Windows Release 实际导出、启动和 180 帧 soak；
- 日志无脚本错误、解析错误、ObjectDB 或退出资源泄漏。
