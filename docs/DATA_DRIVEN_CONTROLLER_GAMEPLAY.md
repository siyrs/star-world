# 数据驱动手柄玩法合同

## 目标

《星的世界》的手柄支持由两层组成：

1. `UiAccessibilityService` 拥有输入模式、UI 比例和焦点恢复；
2. `GameplayInputService` 拥有游戏内连续轴、动作、快捷栏和输入上下文。

两者共享同一个物理设备事件，但不共享状态职责。菜单焦点不会修改玩家移动，玩家输入也不会反向决定当前 Overlay。

## 标准控制布局

| 控件 | 游戏内功能 |
|---|---|
| 左摇杆 | 前后左右移动 |
| 右摇杆 | 水平/垂直视角 |
| A | 跳跃 |
| 左摇杆按压 | 冲刺 |
| RT | 攻击或持续采集 |
| LT | 交互、使用物品或放置方块 |
| D-Pad 左/右 | 上一个/下一个快捷栏槽位 |
| Y | 背包 |
| X | 随身合成 |
| Back | 探索日志 |
| Start | 暂停、关闭或返回 |
| RB | 快速保存 |
| D-Pad 上 | 显示/隐藏引导 |
| D-Pad 下 | 显示/隐藏 F3 诊断 |

## 唯一映射来源

`data/gameplay_controller_profile.json` 是物理控制映射和连续轴参数的唯一来源。当前 Schema 固定为版本 1，Profile 最多 32 条绑定，生产配置使用 21 条。

每条规则只允许：

- `button`：一个 Joypad 按钮；
- `axis`：一个 Joypad 轴的正向或负向。

加载时严格验证：

- 所有必需逻辑动作必须出现且恰好一次；
- 物理按钮和轴方向不能冲突；
- 轴方向只能是 `-1` 或 `1`；
- 死区、响应指数、视角速度和扳机阈值必须为有限且位于固定范围内的数值；
- 未知动作、未知类型和超出预算的配置全部拒绝。

生产代码加载失败时使用同内容的内置安全回退，但 Snapshot 会明确显示 `loaded_from_file=false`，测试不会把回退视为生产数据成功。

## InputMap 安装

`GameplayInputActions.ensure_default_bindings()` 同时修复键盘和手柄事件：

- 不清除玩家或平台已有绑定；
- 只补充缺失事件；
- 重复调用保持幂等；
- 每个动作的 Deadzone 来自 Profile；
- `has_required_bindings()` 同时验证键鼠和手柄合同。

## 连续动作所有权

### 移动

左摇杆进入已有 `get_movement_vector()`，继续由 `PlayerMovementController` 处理地面、空中、游泳和梯子移动。手柄没有第二套移动控制器。

### 视角

右摇杆经过径向死区与指数响应后，由最终 Player 组合层应用到现有 Yaw 和 CameraPivot Pitch。Pitch 继续限制在 ±89°。

### 主动作

RT 复用现有 `_primary_action_held`：

- 对方块：推进正式 HarvestService；
- 对生物：进入正式 CombatService；
- 松开或输入上下文禁用：调用同一个取消路径；
- 不创建 Timer、不复制进度、不绕过耐久。

### 次动作

LT 复用 `interact_or_use_selected_item()`，因此箱子、机器、床、动物、食物和方块放置仍由现有领域服务决定优先级与原子事务。

## 输入上下文

`InputContextService` 继续决定 `GameplayInputService.active`：

- Gameplay：移动、视角、扳机和快捷栏有效；
- Inventory/Crafting/Machine/Journal/Pause：连续玩法输入立即归零；
- Overlay 关闭后恢复 Gameplay；
- 应用失焦时释放键盘原始状态和连续轴 Snapshot。

## 可观察性

`GameplayInputService.get_binding_status()` 暴露：

- Profile 和绑定数量；
- 当前移动/视角向量；
- 最近非零移动；
- 最近键盘和手柄事件；
- 手柄事件累计；
- 当前 active 状态和完整绑定有效性。

`ControllerExplorationPlayer.get_controller_gameplay_snapshot()` 暴露主动作按下/释放、次动作、快捷栏循环和视角帧计数。所有信息都是有界标量，不进入存档。

## 永久验收

```text
tests/developer_b/validate_controller_gameplay.ps1
tests/qa/controller_gameplay_regression.gd
tests/qa/controller_gameplay_desktop_acceptance.gd
.github/workflows/controller-gameplay-tests.yml
```

真实桌面旅程注入正式 `InputEventJoypadMotion` 和 `InputEventJoypadButton`，验证左/右摇杆、A、RT、D-Pad、Y、B 和 Start，并保留背包、暂停截图以及 JSON、stdout、stderr 证据。
