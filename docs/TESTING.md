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
- F3 运行与保存健康；
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
