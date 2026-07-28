# Architecture Audit · Iteration 48

## 范围

本轮基于 `master` 的高 DPI、控制器 UI 焦点和数据驱动世界 POI 能力，审计游戏内输入、Player 组合层、Overlay 输入上下文和真实桌面门禁。

目标不是简单增加几个 Joypad 判断，而是让手柄从“只能操作菜单”推进为可完成基础生存建造循环的正式输入设备，同时继续保留键盘、鼠标、存档和玩法领域的单一权威路径。

## 发现

### P0：控制器 UI 与游戏玩法被割裂

`UiAccessibilityService` 已能识别手柄、恢复菜单焦点并处理 A/B，但 `GameplayInputActions` 只安装键盘事件，`GameplayInputService` 只维护键盘原始状态。玩家进入世界后，左/右摇杆、扳机和快捷栏均没有正式合同。

这会形成一种危险的“半支持”状态：菜单看起来支持手柄，但无法完成移动、视角、攻击、交互和快捷栏选择。

处理：所有 Gameplay Joypad 映射进入唯一数据 Profile，由现有 `GameplayInputService` 安装、读取和诊断。UI Accessibility 继续只拥有输入模式与焦点，不复制玩法输入状态。

### P0：物理映射不能散落在 Player 与 UI

如果 Player 直接判断 `JOY_BUTTON_*`，GameUI 再维护另一张按钮表，未来改键、设备差异和测试会产生漂移。

处理：Player 只消费 `is_primary_action_pressed()`、`get_look_vector()`、`get_hotbar_cycle_just_pressed()` 等逻辑事实。静态门禁禁止生产 Player 和基础 Player 出现 Joypad 物理常量。

### P1：右摇杆漂移与视角手感需要纯策略

直接使用原始右摇杆值会产生漂移；单纯线性死区又会让微调与快速转向难以兼顾。

处理：Profile 固定拥有 0.18 视角死区、1.55 响应指数和 2.8 rad/s 最大速度。曲线作为纯函数回归，不创建 Timer、不采样设备列表。

### P1：扳机不能创建第二个采集状态机

现有鼠标左键通过 `_primary_action_held` 驱动连续采集，并在实体目标时复用 Combat。手柄若另建 Timer 或独立攻击方法，会绕过采集进度、取消、耐久和战斗冷却。

处理：RT 只改变同一个 `_primary_action_held`，复用 `_start_primary_action()`、`_advance_harvest()`、`_cancel_harvest()` 和正式 Combat；LT 复用 `interact_or_use_selected_item()`。

### P1：Overlay 必须权威阻止玩法输入

打开背包或暂停后，摇杆、扳机和快捷栏不能继续驱动玩家。不能靠 Player 自己猜测 Overlay 状态。

处理：沿用 `InputContextService → GameplayInputService.set_active()`。连续轴与扳机查询都受 `active` 限制，关闭 Overlay 后由同一上下文恢复。

## 架构选择

```text
data/gameplay_controller_profile.json
              │ strict schema / 21 bindings / bounded tuning
              ▼
GameplayControllerProfile
              │ normalized profile
              ▼
GameplayInputActions ── installs keyboard + joypad into InputMap
              │
              ▼
GameplayInputService  ← InputContextService owns active/inactive
   ├─ movement vector
   ├─ shaped look vector
   ├─ held primary / just-pressed secondary
   ├─ hotbar cycle / overlay actions
   └─ bounded diagnostics
              │ logical facts only
              ├──────────────────────┐
              ▼                      ▼
ControllerExplorationPlayer      Existing GameUI
movement/look/actions            inventory/crafting/journal/pause
```

## 固定控制闭环

- 左摇杆：移动；
- 右摇杆：视角；
- A：跳跃；
- 左摇杆按压：冲刺；
- RT：攻击或持续采集；
- LT：交互、使用或放置；
- D-Pad 左/右：快捷栏循环；
- Y：背包；
- X：随身合成；
- Back：探索日志；
- Start：暂停/返回；
- RB：快速保存；
- D-Pad 上/下：引导/F3。

## 预算与非目标

- Profile 最多 32 条绑定，当前固定 21 条；
- 每个逻辑动作恰好一个物理绑定，每个物理方向/按钮恰好一个用途；
- 不轮询设备列表；
- 不创建控制器 Timer；
- 不保存摇杆、按钮或输入模式到 `world.json`；
- 本轮不实现震动、自定义改键和多玩家；这些能力必须另有设备生命周期与设置迁移合同。

## 验收矩阵

- 静态：Schema、动作完整性、物理冲突、设备无关 Player、生产场景挂载；
- 纯策略：死区、响应曲线、非法 Profile 拒绝；
- Headless：InputMap 修复、移动/视角/扳机/快捷栏、生产 Player 组合；
- 相邻：键鼠输入、移动生命周期、桌面输入、UI Accessibility、Combat Cadence；
- 真实桌面：真实 Joypad 轴和按钮、背包/暂停双截图、上下文阻断和 JSON；
- 权威门禁：完整 Runtime、桌面矩阵和 Windows Release。
