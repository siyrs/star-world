# Architecture Audit · Iteration 46

## 范围

本轮基于 PR #79 合入后的 `master`，审计 UI、设置、输入模式与真实桌面门禁。目标不是继续增加页面，而是补齐高 DPI 和控制器焦点这一条路线图中已经明确、但此前没有状态所有者的能力。

## 发现

### P0：UI 比例依赖外部环境

现有设计系统只覆盖 1024×576 与 1280×720。高 DPI 显示器只能依赖系统缩放，玩家不能在游戏内选择阅读比例；同时各页面若自行增加字体和尺寸会形成第二套主题。

处理：增加四档严格 `ui_scale`，统一投影到 `ThemeDB.fallback_base_scale`，不修改页面各自的设计令牌。

### P0：输入设备与焦点没有唯一状态所有者

主菜单会主动聚焦，但无法知道玩家当前使用鼠标还是手柄；游戏内 Overlay 也没有在控制器输入后恢复焦点。结果可能是鼠标操作时残留焦点环，或手柄打开页面后没有可操作控件。

处理：新增会话级 `UiAccessibilityService`，只拥有输入模式与 UI 比例；主菜单和游戏内 UI 只消费事实，不反向改变服务状态。

### P1：摇杆漂移可能错误切换输入模式

直接把任意 `InputEventJoypadMotion` 当作手柄意图，会让轻微摇杆漂移持续抢回焦点。

处理：增加 0.55 硬阈值。低于阈值保持原模式，并形成纯策略回归。

### P1：焦点逻辑容易复制到每个页面

如果地图、设置、存档、背包、合成和机器页面分别处理手柄焦点，会形成大量重复和不一致的退出清理。

处理：主菜单组合层和最终 GameUI 组合层各拥有一个递归的“首个可见可交互控件”恢复入口；具体页面不感知输入设备。

### P1：设计坐标与物理像素容易混淆

PR #79 已暴露一次 1024×576 物理窗口与 1280×720 逻辑坐标混用。本轮高 DPI 测试必须同时记录物理窗口、逻辑 viewport 与面板矩形，避免再次把正确渲染误判为越界。

处理：2560×1440 真实桌面旅程输出两套尺寸和两张截图，并保留 JSON 报告。

## 架构选择

```text
GameSettingsPolicy
        │ ui_scale whitelist
        ▼
UiAccessibilityService
   ├─ ThemeDB fallback scale
   ├─ current input mode
   ├─ bounded counters
   └─ read-only snapshot
        │
        ├───────────────┐
        ▼               ▼
Accessible Main Menu   Accessible Game UI
focus ownership        overlay focus ownership
```

## 非目标

本轮不实现完整手柄玩法映射。移动、视角、战斗、快捷栏和震动反馈需要单独的数据注册表、冲突策略与真实设备验收，不能与 UI 焦点混在一个提交中快速堆叠。

## 验收矩阵

- 纯策略：比例归一化、输入事件分类、漂移阈值；
- 组合回归：设置持久化、ThemeDB 投影、主菜单焦点、Overlay 焦点、鼠标释放；
- 相邻回归：Settings、Keyboard Navigation、UI Design、Desktop Input、Experience Hardening；
- 真实桌面：2560×1440、150% UI、真实鼠标、真实 Joypad D-Pad/A/B、两张截图、JSON；
- 权威门禁：完整 Runtime、桌面矩阵、Windows Release。
