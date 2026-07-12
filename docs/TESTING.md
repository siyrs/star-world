# 测试说明

一键回归：

```powershell
.\tests\run_all.ps1 -Godot C:\path\to\godot.exe
```

当前自动化覆盖：

- 数据：62 物品、42 配方、5 地图、4 生物，ID 唯一且配方引用有效。
- Core：100 项，覆盖方块、五类 Seed、出生净空、Chunk 网格/碰撞/装卸、修改保存、玩家与服务集成。
- Gameplay：50 项，覆盖背包、合成、存档、生存、昼夜、生物与设置。
- QA Integration：34 项，覆盖菜单命中区域、多存档按钮闭包、战斗、食用、死亡掉落、音效与退出清理。
- Settings Retest：9 项，覆盖设置加载、应用、持久化、视距与卸载半径。

可视化检查：

```powershell
godot --path . --script res://tests/qa/visual_capture.gd
```

该命令使用真实 OpenGL 渲染启动世界并生成 `tests/qa/artifacts/world-gameplay.png`。Windows 发行包还需执行导出后启动测试，步骤见 [DEPLOY.md](DEPLOY.md)。
