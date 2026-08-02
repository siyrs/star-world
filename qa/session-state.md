# QA Session State

更新时间：2026-08-02 +08:00

## 当前 Git

- 分支：`codex/commercial-release-gameplay-polish`
- 基线 HEAD：`7dba322f9f030672acdbd3621f5e0f80d6254ec8`（13 commits，已存在远端）
- 当前工作：本轮修复尚未提交；未推送任何本轮内容。

## 本轮已验证证据

- Godot：`build/tools/godot/Godot_v4.7-stable_win64_console.exe`（4.7）。
- UI 设计系统：`build/codex-fix-round7/ui.stdout.log`，137/137 PASS；纹理 Button、Primary、Secondary、Danger、MenuPrimary 在 normal/hover/pressed/focus 的实际内容区最小对比度均 >= 4.5。
- 出生：`build/codex-fix-round7/spawn.stdout.log`，5 profiles × seed `24681357` 共 54 checks PASS；新增注入式树冠阻挡夹具和有效旧档位置保留验证。
- 五地图基础旅程：`build/codex-fix-round7/profile-journey-main.png`、`profile-journey-*.png`、`profile-release-journey-report.json`；58 checks PASS。每个 Profile 均通过真实鼠标菜单选择、固定 Seed `112358` 创建、进入可玩世界、核对持久化元数据、返回菜单、删除隔离 QA 世界及 pre/post world manifest 对比。
- fresh Windows export/smoke：`build/codex-fix-round7/release-smoke-final/`，16/16 PASS。`release-smoke.memory.json` 含 7 个带时间戳的 Working Set/Private Bytes 样本：Working Set p95 322.4 MiB，Private Bytes p95 375.2 MiB；没有将不可用内部计数误报为 0。
- 全量：`build/codex-fix-round7/run-all.log`，脚本 exit 0；但日志仍有 ObjectDB/Resource 泄漏，见下方，不能作为发布通过。
- 诊断修复回归：ecology danger、ranged runtime、abyss elite、runtime diagnostics 分别 PASS；修掉了 6 个测试将 `global_position` 写入未入树 Node3D 而触发的 Transform3D 错误。

## 已完成地图与未完成范围

- 基础进入（五张）：星辰大陆、荒漠遗迹、极寒冰原、天空群岛、深渊世界，均已桌面实测进入/返回/保存元数据/清理。
- 未完成：五 Profile 的水域、死亡/复活、探索边界与接缝、交互/战斗/建造、读档重入及正常内容旅程；这些仍是 OpenSpec 6.2--6.7、7.x 的发布阻塞项。
- 传统“通关”条件：当前项目没有已实现的任务/地图结局；不得伪造通关状态，按完整验收旅程替代。

## 当前问题

| ID | 等级 | 状态 | 证据 / 下一步 |
|---|---|---|---|
| BUG-UI-002 | P1 | fixed，待独立 QA-003 | 137/137 本轮工程回归通过；仍需独立同案例桌面复测。 |
| BUG-SPAWN-001 | P1 | fixed，待碰撞专项 | 真实树冠夹具与 focused matrix 通过；尚未完成坡面/接缝/陷阱/掉出世界 3.7。 |
| BUG-OBS-001 | P1 | fixed | fresh export 产出可审计的原始外部内存样本和正确 p95。 |
| BUG-LEAK-001 | P1 | open | 全量日志仍报告 ObjectDB 2+13+8+6=29，Resource 3+3+2=8；需对 core smoke、tool harvest、agriculture、irrigation 的 verbose 泄漏明细逐项修复。 |
| BUG-PERF-001 | P1 | open | 没有按发布手册完成跨区域 FPS/1% low/CPU/GPU/VRAM/120min 数据。 |

## 最近命令

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\run_all.ps1 -Godot .\build\tools\godot\Godot_v4.7-stable_win64_console.exe
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\release\run_windows_export_smoke.ps1 -Godot .\build\tools\godot\Godot_v4.7-stable_win64_console.exe -OutputDirectory build/codex-fix-round7/release-smoke-final
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\ci\run_godot_desktop_test.ps1 -Godot .\build\tools\godot\Godot_v4.7-stable_win64_console.exe -ProjectRoot . -ScriptPath res://tests/qa/profile_release_journey_regression.gd -OutputPath build/codex-fix-round7/profile-journey-main.png
```

## 下一步

1. 用 verbose 定位并修复 `BUG-LEAK-001` 的四个测试出口；全量 runner 需将其视为阻塞，不能仅看 exit 0。
2. 建立/运行 3.7 碰撞、边界、接缝和恢复巡检。
3. 完成 6.2--6.7 与 7.1--7.4 的真实玩法/水域/存读档/极端输入旅程。
4. 采集 5.2--5.5 性能与 120 分钟长稳证据。
5. 独立 QA-003、最终 fresh export、OpenSpec final review 后才决定发布。
