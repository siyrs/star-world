# 有界远程战斗测试

## 静态合同

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\developer_b\validate_bounded_ranged_combat.ps1
```

验证独立数据扩展、原子注册表、单一 64 上限投射物运行时、CombatService 命中权威、玩家共享输入、瞬态边界、文档、统一入口和 CI Artifact。

## 注册表与配方

```powershell
godot --headless --path . --script res://tests/qa/ranged_combat_registry_regression.gd -- --disable-update-check
```

覆盖：

- bow / arrow item 扩展；
- bow / arrows 工作台配方；
- 真实原子制作；
- 现有 main_hand 装备事务；
- 蓄力插值；
- 重复 ID 整体拒绝；
- inventory / equipment 保存重载。

## 真实物理运行时

```powershell
godot --headless --path . --script res://tests/qa/ranged_combat_runtime_regression.gd -- --disable-update-check
```

覆盖：

- 真实 PhysicsRayQueryParameters3D 线段碰撞；
- CombatService 实时防御结算；
- 一箭一次伤害；
- 一箭与一点耐久；
- 蓄力不足、取消、无箭和容量拒绝零消耗；
- 64 支硬上限；
- 可暂停运行时；
- 世界切换清零；
- 投射物不进入保存状态。

## 正式桌面旅程

```powershell
.\tests\ci\run_godot_desktop_test.ps1 `
  -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe `
  -ProjectRoot . `
  -ScriptPath res://tests/qa/ranged_combat_desktop_acceptance.gd `
  -OutputPath build\ranged-combat-charge.png `
  -TimeoutMilliseconds 1200000
```

旅程使用正式 `game.tscn`：

1. 创建并启动真实体素世界；
2. 真实背包装入猎弓与箭矢并装备；
3. 鼠标左键长按，截图蓄力 HUD；
4. 松开发射，真实箭命中真实生物，截图命中反馈；
5. 手柄右扳机长按和松开，复用同一状态机；
6. 验证两支箭、两点耐久和两个输入计数；
7. 权威保存、返回菜单、重新加载；
8. 验证弹药与耐久持久，飞行中箭为零。

Artifact：

```text
build/ranged-combat-charge.png
build/ranged-combat-hit.png
build/ranged-combat-report.json
build/ranged-combat-charge.stdout.log
build/ranged-combat-charge.stderr.log
```

专项通过后仍必须通过仓库权威 Runtime、完整真实桌面矩阵和 Windows Release 实际导出启动。
