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

成功标准：命令退出码为 `0`，输出包含 `PASS: data registry + Godot runtime checks`，且没有 `SCRIPT ERROR`、`Parse Error` 或泄漏警告。测试套件包含输入上下文、UI 覆盖层、快捷栏装备和选中物品使用的专项回归检查。

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

该场景实例化主菜单、Game UI 以及 InputContext、Inventory、Crafting、Save、Survival、DayNight、Audio 和 CreatureSpawner 服务。

## 常见问题

- **黑屏或显卡启动失败**：确认 `project.godot` 使用 `gl_compatibility`，更新显卡驱动。
- **中文路径导出失败**：将临时构建输出改为英文绝对路径，但不要改动 `res://` 内资源路径。
- **存档无法创建**：检查 `%APPDATA%\Godot\app_userdata\星的世界` 的写权限。
- **首次进入卡顿**：降低设置中的区块视距，并等待附近区块分帧生成。
