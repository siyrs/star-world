# 工具、方块硬度与采集架构

## 目标

采集系统把“玩家按住左键”转换为一笔可验证的世界事务，而不是由 Player 直接删除方块并猜测掉落。

系统必须同时保证：

- 方块硬度真实影响采集时间；
- 合适工具更快；
- 高级资源需要正确工具等级才能掉落；
- 工具耐久可保存、可恢复；
- 背包已满时不先删除世界方块；
- 非空箱子和熔炉仍受原有拆除保护；
- UI 只展示领域快照，不修改背包或世界；
- 新工具和新方块优先通过数据扩展。

## 运行结构

```text
HarvestEnabledPlayer
├─ 读取真实左键按下/释放
├─ 解析 RayCast 目标
└─ 委托 BlockHarvestService

ToolProgressionServiceHub
├─ ToolService
├─ BlockHarvestService
│  ├─ BlockHarvestRegistry
│  └─ BlockHarvestPolicy
└─ HarvestProgressOverlay
```

职责边界：

- `HarvestEnabledPlayer`：输入与目标，不拥有采集规则；
- `BlockHarvestRegistry`：读取数据并生成方块采集配置；
- `BlockHarvestPolicy`：纯计算工具匹配、时间和掉落资格；
- `ToolService`：工具能力、剩余耐久和损坏；
- `BlockHarvestService`：进度状态、保护检查、世界提交、掉落和耐久事务；
- `HarvestProgressOverlay`：展示进度与失败原因；
- `InteractionPromptResolver`：在采集前解释推荐工具和最低等级。

## 数据合同

### 物品工具能力

工具定义位于 `data/items.json`：

```json
{
  "id": "iron_pickaxe",
  "category": "tool",
  "tool_type": "pickaxe",
  "power": 3,
  "mining_speed": 4.8,
  "durability": 251,
  "max_stack": 1
}
```

当前工具类型：

```text
pickaxe  镐
axe      斧
sword    剑
hand     空手（运行时默认能力，不是物品）
```

`power` 是工具等级合同：

```text
0 空手
1 木制
2 石制
3 铁制
4 钻石
```

### 方块采集规则

特殊规则位于 `data/block_harvest.json`：

```json
{
  "block_id": "diamond_ore",
  "preferred_tool": "pickaxe",
  "required_tool": "pickaxe",
  "minimum_power": 3,
  "drop_requires_tool": true,
  "wrong_tool_speed_multiplier": 0.2
}
```

字段语义：

- `preferred_tool`：使用该工具类型时应用完整 `mining_speed`；
- `required_tool`：获得受保护掉落所需工具类型；
- `minimum_power`：获得掉落所需最低等级；
- `drop_requires_tool`：工具不足时方块可被破坏，但不产生掉落；
- `drop_item`：覆盖 BlockRegistry 的默认掉落，例如石头掉落圆石；
- `drop_count`：掉落数量；
- `wrong_tool_speed_multiplier`：非推荐工具的速度倍率；
- `breakable=false`：不可破坏，例如基岩、水和岩浆。

未配置特殊规则的方块仍使用 `BlockRegistry.hardness` 和默认物品映射。

## 时间模型

`BlockHarvestPolicy` 使用：

```text
采集时间 = hardness × 基础秒数 ÷ 有效速度
```

并应用上下限，防止：

- 零硬度导致除零或无限事件；
- 极端数据让玩家永久卡在采集状态；
- 错误工具倍率为零；
- 恶意数据产生异常长的主线程任务。

策略是纯 `RefCounted`，不访问 SceneTree、Player、Inventory 或 UI，因此可以单独测试。

## 按住采集状态机

```text
idle
  ↓ 左键按下且命中方块
validate target + interaction protection
  ↓
progress
  ├─ 左键释放 → cancel
  ├─ 目标变化 → cancel
  ├─ 输入上下文关闭 → cancel
  └─ ratio >= 1 → commit

commit
  ├─ 再次确认世界方块未变化
  ├─ 再次确认箱子/机器允许拆除
  ├─ 预检背包掉落容量
  ├─ 删除世界方块
  ├─ 清理位置型领域记录
  ├─ 写入掉落
  └─ 消耗工具耐久
```

活动目标键包含方块 ID、世界坐标和当前工具 ID。玩家切换工具时不会继承上一把工具的采集进度。

## 掉落与内容安全

### 工具等级

当前基础规则：

```text
木镐       石头、圆石、煤矿和基础石质设施
石镐       铁矿
铁镐       金矿和钻石矿
钻石镐     最高速度和耐久
斧         原木、木板、工作台、箱子和其他木质设施
```

错误等级不会复制高级材料。例如木镐可以缓慢破坏钻石矿，但不会获得钻石矿石掉落。

### 背包容量

对于有资格掉落的方块：

```text
背包容量不足 → 拒绝采集提交 → 世界方块保持原状
```

系统不会先删除方块，再把无法容纳的掉落静默丢弃。

### 容器与机器

`BlockHarvestService` 在开始和提交时都调用 `BlockInteractionService.can_break_block()`：

- 非空箱子拒绝拆除；
- 非空熔炉拒绝拆除；
- 状态在采集过程中发生变化时，最终提交仍会再次验证。

## 耐久与存档兼容

工具剩余耐久存放在已有物品槽 metadata：

```json
{
  "item_id": "iron_pickaxe",
  "count": 1,
  "metadata": {
    "durability": 184,
    "custom_name": "星星的镐"
  }
}
```

兼容规则：

- 旧存档缺少 `durability` 时按物品定义的满耐久处理；
- 更新耐久只修改 `metadata.durability`；
- 自定义名称等其他 metadata 保留；
- 耐久归零时只删除实际使用的槽位；
- 工具保持 `max_stack=1`，不同耐久不会错误堆叠；
- 不需要增加新的世界存档顶层字段。

## 玩家反馈

### 上下文提示

瞄准方块时展示：

- 按住左键采集；
- 推荐工具；
- 最低掉落等级；
- 当前预计耗时；
- 当前工具不足时的掉落警告。

### 采集进度

`HarvestProgressOverlay` 显示：

- 方块名称；
- 当前工具；
- 预计耗时；
- 实时进度条；
- 当前操作是否会产生掉落。

面板整棵 Control 树使用鼠标透传，不改变 InputContext、鼠标捕获或世界暂停。

### 耐久

- 快捷栏：显示耐久百分比；
- Tooltip：显示精确剩余值；
- 当前物品条：显示精确耐久；
- 工具损坏：通过玩家体验层显示去重警告。

## 扩展方式

### 增加工具

1. 在 `data/items.json` 增加工具定义；
2. 指定 `tool_type`、`power`、`mining_speed`、`durability` 和 `max_stack=1`；
3. 在普通配方中增加制作方式；
4. 运行数据、领域、桌面和 Release 门禁。

### 增加方块采集要求

1. 方块必须先存在于 `BlockRegistry`；
2. 仅在需要特殊工具、等级、速度或掉落时增加 `block_harvest.json` 规则；
3. 不要在 Player 中增加 `if block_id == ...`；
4. 为代表性工具等级增加回归测试。

### 增加新工具类型

铲、锄等新类型需要：

1. 扩展工具类型数据校验；
2. 扩展纯策略的显示名称；
3. 给相关方块增加数据规则；
4. 不修改采集事务结构。

## 明确禁止

- Player 直接删除方块或生成掉落；
- UI 直接写工具 metadata；
- 按方块 ID 在 Player 中硬编码工具判断；
- 背包满时先删除方块；
- 错误工具产生高级矿物掉落；
- 用 UI 可见性决定采集是否运行；
- 切换目标或工具后继承旧进度。

## 最低验收

每次修改工具或采集系统必须通过：

- 工具和采集数据校验；
- 工具类型、等级和速度策略；
- 方块硬度与按住进度；
- 高级矿物掉落门槛；
- 错误工具无受保护掉落；
- 背包满时世界不变；
- 耐久消耗、损坏和存档恢复；
- 箱子与熔炉拆除保护；
- 真实桌面左键按住与截图；
- 关闭 UI 后鼠标和 WASD 合同；
- 实际 Windows Release 导出和启动；
- 日志无脚本错误、解析错误或资源泄漏。
