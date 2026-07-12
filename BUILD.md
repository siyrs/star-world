# 构建与运行

## 环境

- Windows 10/11 x64
- Godot 4.3 或更高版本，推荐 4.7 stable
- 渲染器：OpenGL `gl_compatibility`
- 项目不需要 .NET、JDK、Gradle 或第三方 Godot 插件

## 编辑器运行

1. 启动 Godot Project Manager。
2. 选择 **Import**，指向本目录的 `project.godot`。
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

成功标准：命令退出码为 `0`，输出包含 `PASS: data registry + Godot runtime checks`，且没有 `SCRIPT ERROR`、`Parse Error` 或泄漏警告。测试套件包含 WASD/方向键绑定修复、真实角色移动、窗口与 UI 输入生命周期、物理层隔离、掉落物拾取、覆盖层互斥、快捷栏装备和选中物品使用的专项回归检查。

只运行移动与输入生命周期专项测试：

```powershell
godot --headless --path . --script res://tests/qa/movement_lifecycle_regression.gd
```

只运行物理交互与掉落物专项测试：

```powershell
godot --headless --path . --script res://tests/qa/physics_interaction_regression.gd
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

服务和 UI 可独立运行，用于排除世界渲染干扰：

```powershell
godot --path . res://scenes/ui/service_hub.tscn
```

该场景实例化主菜单、Game UI 以及 GameplayInput、InputContext、Inventory、Crafting、Save、Survival、DayNight、Audio 和 CreatureSpawner 服务。

## 常见问题

- **WASD 无响应**：先运行 `movement_lifecycle_regression.gd`。默认映射会自动修复 W/A/S/D 的物理键位与逻辑键码，并提供方向键后备。
- **从背包或暂停返回后不能移动**：确认专项测试中的 “closing the overlay restores WASD movement” 通过；输入启用只应由 `InputContextService` 管理。
- **掉落物未按预期拾取**：运行 `physics_interaction_regression.gd`，确认玩家、实体、掉落物使用 2/3/4 层，掉落物掩码只包含 Player。
- **黑屏或显卡启动失败**：确认 `project.godot` 使用 `gl_compatibility`，更新显卡驱动。
- **中文路径导出失败**：将临时构建输出改为英文绝对路径，但不要改动 `res://` 内资源路径。
- **存档无法创建**：检查 `%APPDATA%\Godot\app_userdata\星的世界` 的写权限。
- **首次进入卡顿**：降低设置中的区块视距，并等待附近区块分帧生成。
