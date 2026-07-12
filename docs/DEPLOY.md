# Windows 部署

发行目标为 Windows x86_64，使用 Godot 4.7 stable 的匹配 Export Templates。

```powershell
godot --headless --path . --export-release "Windows Desktop" .\build\StarWorld.exe
```

交付目录必须同时包含：

- `StarWorld.exe`
- `StarWorld.pck`

构建后从发行包本身执行：

```powershell
.\build\StarWorld.exe --headless --quit-after 120
```

正式发布前要求导出日志无 `ERROR`、无 `SCRIPT ERROR`、无 `Parse Error`，且目录中没有 `*.TMP` 或 `*~*` 残留。完整环境说明见 [BUILD.md](../BUILD.md)。
