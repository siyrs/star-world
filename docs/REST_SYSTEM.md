# 睡眠、床与重生点系统

## 产品目标

床为《星的世界》补齐两个高频生存需求：

```text
建设安全住所
→ 制作并放置床
→ 设置持久重生点
→ 夜晚睡到清晨
→ 死亡后回到床边安全位置
```

设计重点不是“右键把时间改成早晨”，而是让床、昼夜、玩家重生、世界方块和存档形成可恢复的完整事务。

## 运行时结构

```text
CharacterProgressionServiceHub
├─ DayNightService
├─ RestService
│  └─ RestPolicy
├─ BlockInteractionService
│  └─ extensions[]
└─ CharacterProgressionPlayer
   └─ respawn contract
```

### `RestPolicy`

读取 `data/rest.json`，只负责静态规则：

- 哪些方块具有床能力；
- 允许睡眠的时间窗口；
- 起床时间；
- 床边重生候选偏移；
- 玩家身体需要的垂直净空。

平衡数值不散落在 Player、UI 或交互服务中。

### `RestService`

睡眠和自定义重生点的唯一状态所有者，负责：

- 解析床交互；
- 搜索床边安全出生位置；
- 白天设置重生点；
- 夜晚设置重生点并推进到清晨；
- 把重生点注入 Player 的稳定能力合同；
- 保存、恢复和校验床位置；
- 床被拆除或安全空间失效时回退到世界出生点；
- 发布领域事实和明确的失败原因。

### `DayNightService`

新增：

```gdscript
skip_to_time(hours: float) -> Dictionary
```

它负责日历语义：

- 晚上 21:00 睡到 06:30，会进入下一天；
- 凌晨 02:00 睡到 06:30，仍是当前天；
- 跳时后立即更新太阳、环境光、天空颜色和时间信号。

RestService 不直接写入 DayNightService 的内部字段。

### Player 重生合同

实际玩家公开：

```gdscript
set_respawn_position(position: Vector3) -> bool
reset_respawn_position() -> void
get_respawn_position() -> Vector3
```

Player 只保存当前可用重生坐标并执行 `respawn()`，不判断床是否存在，也不决定何时能睡觉。

## 玩家体验

### 制作与放置

橡木床通过工作台制作：

```text
木板 ×3
羊毛 ×3
→ 橡木床 ×1
```

床是普通可放置世界物品，当前采用稳定的单方块表示。以后可以增加朝向或双格视觉，但不能改变 RestService 的稳定位置合同。

### 白天交互

```text
右键床
→ 搜索安全位置
→ 设置重生点
→ 保持当前时间
```

提示：

```text
右键设置重生点（夜晚可睡）
```

### 夜晚交互

睡眠窗口默认为 19:00 至次日 06:00：

```text
右键床
→ 搜索安全位置
→ 设置重生点
→ 跳到 06:30
→ 更新天数与世界光照
```

提示：

```text
右键睡到清晨并设置重生点
```

睡眠不打开新面板，不释放鼠标，也不切换 InputContext。

## 安全出生解析

重生点不能直接使用床方块中心。服务按 `data/rest.json` 中的候选顺序检查：

1. 玩家脚部方块为空；
2. 玩家头部所需净空为空；
3. 脚下存在实体支撑；
4. 结果坐标为有限数值。

所有候选均无效时：

- 本次交互失败；
- 不替换已有重生点；
- 显示“床边没有足够的安全空间”；
- 不改变时间。

## 床移除与旧存档

世界存档增加：

```text
rest {
  version,
  has_custom_spawn,
  bed_position,
  respawn_position
}
```

加载顺序：

```text
反序列化 rest
→ 创建并启动世界
→ 挂载 Player 与 RestService
→ 检查床方块仍存在
→ 重新解析床边安全位置
→ 注入 Player
```

如果床不存在或周围被堵塞：

- 自定义重生点被清除；
- Player 恢复世界生成器提供的安全出生点；
- 玩家收到明确提示。

旧存档缺少 `rest` 字段时自动迁移为空状态，不需要删除世界。

## 交互扩展

RestService 通过通用扩展端口参与：

```text
try_interact
get_interaction_hint
can_break_block
on_block_removed
```

因此：

- Player 不包含 `oak_bed` 判断；
- BlockInteractionService 不拥有重生数据；
- UI 不直接修改时间或坐标；
- 以后增加睡袋、不同床型或旅店床时，可扩展 `data/rest.json` 和策略。

## 当前范围

当前版本：

- 一种床：橡木床；
- 单方块简化表示；
- 单人世界睡眠；
- 不播放躺下动画；
- 不处理附近敌人阻止睡眠；
- 不执行多人投票或同步。

这些是后续体验扩展，不应重新把睡眠规则塞入 Player 或 GameUI。

## 验收门禁

每次睡眠与重生改动必须通过：

1. `validate_rest.ps1` 数据合同；
2. `rest_respawn_regression.gd` 领域、存档、时间和失效回退；
3. 既有输入、采集、机器、装备、农业和生命周期回归；
4. `rest_desktop_acceptance.gd` 真实 Camera3D、RayCast3D 和鼠标右键；
5. 最终 Windows Release 导出、启动、180 帧 soak 与退出日志扫描。
