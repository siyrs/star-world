# 简易探矿与探索发现合同

## 目标

把地图资源差异转化为玩家能够理解和行动的探索反馈，同时禁止直接暴露矿物精确坐标。

```text
制作简易探矿仪
→ 真实右键扫描当前区域
→ 有预算地采样附近岩层
→ 返回深度、密度与最强矿物类型
→ 保存当前区块的探索发现
```

探矿仪提供的是粗粒度趋势，不是透视工具。玩家仍需要进入洞穴、向下开采和承担地图风险。

## 产品闭环

配方：

```text
铁锭 ×2 + 煤炭 ×1 + 玻璃 ×1 + 木棍 ×1
→ 工作台
→ 简易探矿仪 ×1
```

使用：

1. 将简易探矿仪放入快捷栏；
2. 在 gameplay 输入上下文中按鼠标右键；
3. 系统扫描当前区块附近有限范围；
4. HUD 显示浅层/中层/下层/深层，以及贫瘠/普通/可观/富集；
5. 有矿物信号时只说明最强类型；
6. 发现记录随当前世界保存。

示例结果：

```text
中层岩层 · 可观：铁矿信号最强；仅显示当前区域的粗粒度趋势
```

结果不包含矿物坐标、方块位置数组或可用于透视的路径信息。

## 数据合同

`data/prospecting.json` 描述：

- 探矿物品 ID；
- 水平和垂直扫描半径；
- 采样步长；
- 单次最大采样数量；
- 最低有效岩层样本；
- 使用冷却；
- 最大持久记录数；
- 可识别岩层和矿物；
- 密度等级和深度区间。

当前理论采样上限为：

```text
7 × 7 × 13 = 637
```

同时受 `max_samples=700` 硬预算保护。不得改为遍历完整区块或为每次使用加载远距离区块。

## 领域边界

### ProspectingRegistry

负责：

- 加载和规范化 JSON；
- 校验扫描半径、步长、预算、记录上限；
- 校验矿物方块；
- 校验探矿物品能力。

### ProspectingPolicy

纯策略负责：

- 矿物密度等级；
- 深度区间；
- 最强矿物类型；
- 玩家可见摘要；
- 区块与深度组成的稳定记录 Key。

纯策略不访问世界、不读取背包、不保存数据。

### ProspectingService

唯一运行时状态所有者，负责：

- 真实世界采样；
- 采样数量预算；
- 冷却；
- 有效岩层保护；
- 发现记录去重；
- 最大 64 条记录；
- 序列化和恢复。

扫描使用 `VoxelWorld.get_initial_block()`，不会强制加载附近区块，也不会改变世界方块。

### ExplorationPlayer

Player 只提供薄适配：

```text
右键使用选中物品
→ ProspectingService.use_item
→ gameplay_action_reported(prospect)
```

Player 不包含矿物规则、密度公式或保存逻辑。

### ExplorationProgressionServiceHub

组合服务、世界生命周期、保存事务、HUD 消息和第一人称使用反馈。

## 存档合同

世界状态新增兼容字段：

```text
exploration {
  version,
  records [
    {
      record_key,
      chunk,
      profile_id,
      depth_band_id,
      depth_label,
      density_id,
      density_label,
      ore_ratio,
      dominant_block_id,
      dominant_label,
      message,
      scanned_at_msec
    }
  ],
  last_result
}
```

旧世界缺少该字段时迁移为空探索状态。加载超过当前预算的旧数据时只保留最新 64 条。

## 安全与失败反馈

- 非探矿物品不会被拦截；
- 世界或玩家未准备好时拒绝；
- 冷却中拒绝重复扫描；
- 空中或岩层样本不足时提示靠近地面、洞穴或更低深度；
- 失败不新增记录；
- 探矿仪不消耗、不损坏；
- 打开阻塞 UI 时玩家输入关闭，不能触发扫描；
- 不返回精确矿物坐标。

## 测试门禁

### 静态合同

`validate_prospecting.ps1` 验证物品、配方、半径、步长、理论采样量、硬预算、矿物、密度和深度区间。

### 领域回归

`prospecting_regression.gd` 覆盖：

- 配置与物品能力；
- 密度和深度边界；
- 同数量时稀有矿物优先级；
- 有预算真实扫描；
- 无精确坐标；
- 冷却与失败保护；
- 区块记录；
- 存档迁移和 64 条上限；
- UI 提示与第一人称动作；
- 生产 Player 和 ServiceHub 组合。

### 真实桌面验收

`exploration_iteration_desktop_acceptance.gd` 使用生产 Game、VoxelWorld、Player、Inventory、ServiceHub、HUD、Camera3D 和真实鼠标右键，验证扫描、冷却、提示、动画、保存重载和 UI 输入阻断。
