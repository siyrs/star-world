# 异常会话恢复与安全退出测试指南

## 静态架构合同

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\tests\developer_b\validate_crash_safe_session_recovery.ps1
```

验证纯恢复策略、primary-only marker、UI 意图边界、单一退出协调器、生产场景挂载、永久回归、文档和 CI Artifact。

## 模拟应用重启

```powershell
godot --headless --path . `
  --script res://tests/qa/world_session_recovery_regression.gd `
  -- --disable-update-check
```

覆盖真实世界创建、loading/active 标记、真实保存检查点、服务销毁与重建、忽略提示、损坏主标记、旧 backup 拒绝、世界删除和 `world.json` 瞬时边界。

## 安全应用退出

```powershell
godot --headless --path . `
  --script res://tests/qa/graceful_application_quit_regression.gd `
  -- --disable-update-check
```

覆盖主菜单退出、暂停菜单退出、Windows close notification、最终保存成功、最终保存失败取消退出、恢复后重试和 SceneTree 自动退出状态恢复。

## 真实桌面三阶段旅程

```powershell
.\tests\ci\run_godot_desktop_test.ps1 `
  -Godot C:\path\to\Godot_v4.7-stable_win64_console.exe `
  -ProjectRoot . `
  -ScriptPath res://tests/qa/world_session_recovery_desktop_acceptance.gd `
  -OutputPath build\session-recovery-candidate.png `
  -TimeoutMilliseconds 1200000
```

输出：

```text
build/session-recovery-candidate.png
build/session-recovery-safe-quit.png
build/session-recovery-clean-exit.png
build/session-recovery-report.json
build/session-recovery-candidate.stdout.log
build/session-recovery-candidate.stderr.log
```

该旅程创建第一份正式 Game、保存真实背包变化、直接销毁实例模拟中断，再创建第二份正式 Game 模拟重启。随后真实鼠标恢复世界，真实 Escape 打开暂停菜单，再真实鼠标执行“保存并退出游戏”。

三张截图分别证明：

1. 主菜单只为有效权威世界显示恢复卡片；
2. Pause 面板提供安全退出命令且处于 1280×720 安全区域；
3. 最终保存后恢复卡片消失并显示安全退出确认。

## 全量入口

`tests/run_all.ps1` 永久执行静态合同、模拟重启和安全退出回归。真实桌面、相邻领域与 Windows Release 由独立工作流和权威总门禁执行。
