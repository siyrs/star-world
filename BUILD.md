# 构建与运行

## 环境

- Windows 10/11 x64
- Godot 4.3 或更高版本，推荐 4.7 stable
- 渲染器：OpenGL `gl_compatibility`
- 项目不需要 .NET、JDK、Gradle 或第三方 Godot 插件

## 编辑器运行

1. 启动 Godot Project Manager。
2. 选择 **Import**，指向本目录下的 `project.godot`。
3. 等待首次资源扫描完成。
4. 按 `F6/F5` 运行主场景。

## 命令行检查

如果 `godot` 已在 `PATH` 中：

```powershell
godot --headless --path . --editor --quit
powershell -ExecutionPolicy Bypass -File .\tests\run_all.ps1 -Godot C:\path\to\godot.exe
```

本开发环境的已验证引擎命令为：

```powershell
& .\tests\run_all.ps1 `
  -Godot 'C:\Users\sirius\.codex\toolchains\godot\4.7\Godot_v4.7-stable_win64_console.exe'
```

成功标准：命令退出码为 `0`，输出包含 `PASS: data registry + Godot runtime checks`，且没有 `SCRIPT ERROR`、`Parse Error` 或泄漏警告。完整套件覆盖移动、输入生命周期、物理层、方块交互、容器持久化、暂停、存档恢复、渐进区块构建、种群回收、快捷栏和设置。

只运行移动与输入生命周期：

```powershell
godot --headless --path . --script res://tests/qa/movement_lifecycle_regression.gd
```

只运行物理交互与掉落物：

```powershell
godot --headless --path . --script res://tests/qa/physics_interaction_regression.gd
```

只运行工作台、熔炉与箱子交互：

```powershell
godot --headless --path . --script res://tests/qa/block_interaction_regression.gd
```

只运行稳定性与性能基线：

```powershell
godot --headless --path . --script res://tests/qa/runtime_stability_regression.gd
```

## Windows 发行构建

Godot 编辑器首次导出时，如有提示请先安装与引擎版本一致的 Export Templates。导出预设名为 `Windows Desktop`。

```powershell
New-Item -ItemType Directory -Force .\build | Out-Null
godot --headless --path . --export-release "Windows Desktop" .\build\StarWorld.exe
```

交付时应保留同目录下的 `.pck` 文件（如果导出配置选择了分离 PCK）。构建后检查：

```powershell
Get-Item .\build\StarWorld.exe
& .\build\StarWorld.exe
```

## 快速场景检查

服务与 UI 可独立运行，用于排除世界渲染干扰：

```powershell
godot --path . res://scenes/ui/service_hub.tscn
```

该场景实例化主菜单、Game UI 以及 GameplayInput、InputContext、SimulationPause、Inventory、ContainerStorage、Crafting、BlockInteraction、Save、Survival、DayNight、Audio 和 CreatureSpawner 服务。

## 方块交互验收

进入世界后至少检查：

1. `C` 只能打开随身合成，不能手动切换到工作台或熔炉。
2. 右键工作台打开工作台配方。
3. 右键熔炉只打开熔炉配方。
4. 右键箱子打开 27 格容器。
5. 箱子与玩家背包之间转移后总数量不变。
6. 非空箱子不能拆除；清空后可以拆除。
7. 保存、返回菜单并重新进入后，箱子内容仍存在。
8. 关闭容器后，鼠标重新捕获且 WASD 恢复。

## 常见问题

- **WASD 无响应**：运行 `movement_lifecycle_regression.gd`。默认映射会修复 W/A/S/D 的物理键位和逻辑键码，并提供方向键后备。
- **从背包、容器或暂停返回后不能移动**：输入启用只能由 `InputContextService` 管理；先运行移动和方块交互专项测试。
- **工作台或熔炉配方无法使用**：高级工位必须右键世界中的对应方块；`C` 只提供随身合成。
- **箱子无法拆除**：这是内容保护策略。先把箱子中的物品全部转回背包。
- **箱子内容重载后消失**：运行 `block_interaction_regression.gd`，并确认保存文件包含顶层 `containers` 字段。
- **暂停后世界仍在运行**：运行 `runtime_stability_regression.gd`，确认暂停由 `SimulationPauseService` 写入并恢复 `SceneTree.paused`。
- **存档损坏或无法读取**：不要删除同目录下的 `.bak`；加载会尝试有效临时文件和上一版本备份。
- **掉落物未按预期拾取**：运行 `physics_interaction_regression.gd`，确认玩家、实体和掉落物分别使用 2/3/4 层。
- **黑屏或显卡启动失败**：确认项目使用 `gl_compatibility`，并更新显卡驱动。
- **中文路径导出失败**：将临时输出目录改为英文绝对路径，但不要修改 `res://` 资源路径。
- **存档无法创建**：检查 `%APPDATA%\Godot\app_userdata\星的世界` 的写权限。
- **首次进入卡顿**：默认视距为 3，周边区块按预算渐进构建；低配设备可在设置中降为 1–2。
