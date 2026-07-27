# 测试说明

## 一键完整回归

```powershell
.\tests\run_all.ps1 -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe
```

该入口依次执行：

1. 数据、架构和 CI 静态合同；
2. Godot 领域与策略测试；
3. 生产 ServiceHub、保存、输入、UI 和生命周期集成测试；
4. Runtime、三轮 soak 和资源释放回归。

任何 `SCRIPT ERROR`、`Parse Error`、ObjectDB 泄漏或退出时仍在使用的资源都会被 CI Runner 判为失败，不能只依赖进程退出码 0。

## 统一专业 UI

### 静态设计合同

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\tests\developer_b\validate_ui_design_system.ps1
```

覆盖：

- “星际远征”语义颜色、8pt 间距、字体、圆角和控件高度；
- Primary、Secondary、Ghost、Danger、Selected 和 Focus 状态；
- 主菜单 Hero + Command Deck；
- 地图、设置、存档、HUD、引导、工作区、弹窗和 F3 的统一结构；
- 1024×576 与 1280×720 响应式边界；
- 设计合同、路线图、测试、工作流和 Artifact 声明。

### Theme 与布局回归

```powershell
godot --headless --path . `
  --script res://tests/qa/ui_design_system_regression.gd `
  -- --disable-update-check
```

该脚本验证：

- Theme 变体的继承关系和高对比键盘焦点；
- 主文字与表面的可读性；
- 主菜单六个命令及主/危险层级；
- Hero、Command Deck、地图、设置和存档在 1280×720 与 1024×576 下不越界；
- 设置四张分组卡、固定操作区和单一滚动区；
- 阻塞界面共享暗幕；
- 暂停菜单主次操作；
- F3 双卡布局与完整鼠标穿透。

### 十屏真实桌面验收

```powershell
.\tests\ci\run_godot_desktop_test.ps1 `
  -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe `
  -ProjectRoot . `
  -ScriptPath res://tests/qa/ui_visual_refresh_desktop_acceptance.gd `
  -OutputPath build\ui-visual-refresh-main-menu.png `
  -TimeoutMilliseconds 1200000
```

真实旅程使用鼠标点击主菜单、地图、设置、存档和开始按钮，并使用真实 `Escape`、`E`、`C`、`J`、`F3` 打开游戏内界面。输出：

```text
build/ui-visual-refresh-main-menu.png
build/ui-visual-refresh-map-selection.png
build/ui-visual-refresh-settings.png
build/ui-visual-refresh-save-browser.png
build/ui-visual-refresh-gameplay-hud.png
build/ui-visual-refresh-pause.png
build/ui-visual-refresh-inventory.png
build/ui-visual-refresh-crafting.png
build/ui-visual-refresh-exploration-journal.png
build/ui-visual-refresh-diagnostics.png
build/ui-visual-refresh-report.json
build/ui-visual-refresh-main-menu.stdout.log
build/ui-visual-refresh-main-menu.stderr.log
```

十张截图必须来自同一正式生产旅程，JSON 必须保留各页面的布局矩形、Theme 状态、截图路径和世界 ID。该专项不能替代已有熔炉、容器、农业、装备、更新和 Windows Release 的真实桌面门禁，而是与它们共同证明整套 UI 的一致性。

## 有界自动保存

### 静态合同

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\tests\developer_b\validate_bounded_autosave.ps1
```

覆盖：

- 0/2/5/10/15 分钟设置白名单；
- 单一 `save_current()` 权威保存入口；
- Pause 感知活动时间；
- 单 pending / 单 saving；
- 15/60/300 秒失败退避；
- 七参与者依赖与反向清理；
- 自动保存状态不进入世界 payload；
- 领域事实与 UI 展示分离；
- 工作流、文档与 Artifact 合同。

### 领域与生产集成

```powershell
godot --headless --path . `
  --script res://tests/qa/bounded_autosave_runtime_regression.gd `
  -- --disable-update-check
```

该脚本使用 Fake Hub 验证精确计时、手动保存去重、暂停、设置热更新和分级退避，并使用正式 `service_hub.tscn` 创建真实世界、写入背包变化、触发真实自动保存，再从 `world.json` 重新读取。

### 最终保存失败的健康报告

```powershell
godot --headless --path . `
  --script res://tests/qa/runtime_health_failed_return_regression.gd `
  -- --disable-update-check
```

该脚本验证最终保存失败时：

- 玩家仍留在原世界；
- `current_world_id` 不被清空；
- F3 Runtime Health 仍保持 world attached；
- 保存失败继续作为严重运营证据；
- 后续成功返回菜单后才解除世界引用。

### 真实桌面与可视化证据

```powershell
.\tests\ci\run_godot_desktop_test.ps1 `
  -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe `
  -ProjectRoot . `
  -ScriptPath res://tests/qa/bounded_autosave_desktop_acceptance.gd `
  -OutputPath build\bounded-autosave-desktop.png `
  -TimeoutMilliseconds 900000
```

输出：

```text
build/bounded-autosave-desktop.png
build/bounded-autosave-desktop-settings.png
build/bounded-autosave-desktop.json
build/bounded-autosave-desktop.stdout.log
build/bounded-autosave-desktop.stderr.log
```

真实桌面旅程必须验证设置页、真实 Pause/Resume、未保存背包变化、一次生产自动保存、重新加载完整性和 HUD 成功提示。

## 保存检查点时间线

### 静态合同

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\tests\developer_b\validate_save_checkpoint_timeline.ps1
```

覆盖：

- `manual`、`autosave`、`return_to_menu`、`system` 四类严格来源；
- 未知来源确定性归一化为 `system`；
- 最近 12 条有界历史、精确来源累计和淘汰计数；
- 当前世界过滤、成功结束世界身份和失败返回保留身份；
- 自动保存来源通过真实 `saving` 窗口推断；
- F3 只读格式化与自动保存倒计时；
- 时间线不进入 `world.json`；
- 独立 CI、截图、JSON 与日志 Artifact 合同。

### 领域与生产集成

```powershell
godot --headless --path . `
  --script res://tests/qa/save_checkpoint_timeline_regression.gd `
  -- --disable-update-check
```

该脚本验证 20 条事件收敛为最近 12 条、淘汰后四类累计仍精确、任意事件 payload 被白名单剔除、会话结束仅清理当前世界身份，并使用正式 ServiceHub 验证 manual/system/return-to-menu 三种来源和权威存档的完全瞬态边界。

### 真实桌面与可视化证据

```powershell
.\tests\ci\run_godot_desktop_test.ps1 `
  -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe `
  -ProjectRoot . `
  -ScriptPath res://tests/qa/save_checkpoint_timeline_desktop_acceptance.gd `
  -OutputPath build\save-checkpoint-timeline-desktop.png `
  -TimeoutMilliseconds 900000
```

输出：

```text
build/save-checkpoint-timeline-desktop.png
build/save-checkpoint-timeline-desktop.json
build/save-checkpoint-timeline-desktop.stdout.log
build/save-checkpoint-timeline-desktop.stderr.log
```

真实桌面旅程必须使用真实 Escape、暂停菜单鼠标按钮、未暂停自动保存和 F3 输入，验证手动与自动检查点关联、背包变化持久化、时间线不写入存档、1280×720 安全区域与可视化文本。

## 存档与恢复

关键专项：

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\developer_b\validate_save_recovery.ps1
powershell -ExecutionPolicy Bypass -File .\tests\developer_b\validate_world_catalog.ps1
powershell -ExecutionPolicy Bypass -File .\tests\developer_b\validate_bounded_trash_manager.ps1

godot --headless --path . --script res://tests/qa/save_recovery_regression.gd -- --disable-update-check
godot --headless --path . --script res://tests/qa/world_catalog_regression.gd -- --disable-update-check
godot --headless --path . --script res://tests/qa/trash_manager_service_regression.gd -- --disable-update-check
```

## 运行时、规模与 UI

完整回归还永久覆盖：

- Chunk 流式、自适应预算与最近快照；
- 机器、自动化和 512 台规模；
- 农业 2,048 株、畜牧和牧场生命周期；
- 敌对前摇、危险事件批处理与物理掉落共享运行时；
- 结构完整性、单 flush 和跨 Chunk 建筑；
- 存档浏览器索引、虚拟化、回收站管理；
- 1024×576 与 1280×720 UI 安全区域；
- F3 运行与保存健康、保存来源和检查点时间线；
- 多轮进入/退出与 ObjectDB 资源释放。

## 合入门禁

新增或修改功能至少需要：

1. 静态架构合同；
2. 纯策略或领域回归；
3. 生产组合集成；
4. 涉及 UI 时的真实桌面鼠标/键盘旅程；
5. 截图、JSON 和 stdout/stderr Artifact；
6. 相邻领域回归；
7. 权威全量 Runtime；
8. 实际 Windows Release 导出、启动与退出资源检查。
