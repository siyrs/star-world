# QA Session State

更新时间：2026-08-01 +08:00（第四轮审计后）

## 当前 Git

- 分支：`codex/commercial-release-gameplay-polish`
- 起点提交：`c1054d8`
- 最新提交：`be644b0`（已推送 origin）
- 提交链：6 commits（`06cf1bf` → `6ec3545` → `078be45` → `30a0260` → `21c6b63` → `be644b0`）
- 工作树：干净

## 当前构建状态

- 第四轮 fresh export/smoke PASS（16/16；EXE 版本 1.3.0.0）
- BUG-REL-001 ✓ | BUG-UI-001 ✓ | BUG-PACK-001 ✓ | BUG-VERSION-001 ✓
- BUG-SPAWN-001: 树冠夹具通过（18/18）；5×6 矩阵通过
- BUG-UI-002: Toolbar/Card/Selected 对比度通过；GhostButton disabled 边界待修复

## 第四轮审计已知问题

- UI 回归：GhostButton disabled 边界检查 `< 0.5` → `<= 0.5`（1 项）
- 最终 fallback：从 WORLD_HEIGHT-3 改为 origin column 顶块扫描
- 全量测试：27 ObjectDB leaks、8 未释放资源、6 Transform3D 错误
- session-state 更新延迟（本轮修复）
- OpenSpec：13/47 完成
- 当前工程：Godot 4.7、GDScript、GL Compatibility；主场景 `res://scenes/game/game.tscn`；唯一导出预设 `Windows Desktop`。
- 本机引擎：`C:\Users\sirius\.codex\toolchains\godot\4.7\Godot_v4.7-stable_win64_console.exe`，文件版本 4.7。
- Windows PowerShell 5.1 调用在导出前失败，证据为 `build/release-readiness-fresh/release-smoke.driver.log`；已登记 `BUG-REL-001`。
- PowerShell 7 fresh export/smoke 通过：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\release\run_windows_export_smoke.ps1 `
  -Godot 'C:\Users\sirius\.codex\toolchains\godot\4.7\Godot_v4.7-stable_win64_console.exe' `
  -OutputDirectory .\build\release-readiness-fresh-pwsh7
```

- 结果：export exit 0；runner exit 0；checks=16；soak=180 帧；进程已退出。
- 产物：EXE SHA-256 `C42EB5D17F683EB8BCD52C19A9F36EBF811B1788623878D5276A7D9FFC09F95C`；PCK SHA-256 `38B6E33400D1E0A3C0E2D8BB72EE6AD664603AADD9A19B58286ADDEF9F90C305`。
- 基线未达到发布通过：字体缺失 warning、chunk 队列健康 warning、memory 指标 0.0 已登记。
- PM readiness validator 已于 10:27 exit 0；进入实施阶段。
- Developer 首批自测：
  - `BUG-QA-002`：`build/developer-selftest-qa002`，production-scene desktop 内层 32 checks/10 captures、外层 exact OutputPath 均 exit 0；待独立 QA。
  - `BUG-UI-002`：`build/developer-selftest-ui002`，headless 64 checks、desktop 32 checks/10 captures exit 0；待独立 QA。
  - `BUG-SPAWN-001`：第一轮 5 profiles×3 seeds/108 checks 与 core smoke rerun 100 checks 通过，但 `desktop-input-contract` 仍有 1 项失败；关键复现 Seed `24681357` 未纳入且 ObjectDB leak 三轮未闭合，修复包返回 Developer，不得提交。

## 覆盖状态

- 已测试地图：星辰大陆仅完成 fresh smoke 直达和 production-scene 菜单创建/HUD UI 旅程；未完成地图验收旅程。
- 已通关地图：无（本轮）。
- 未测试地图：荒漠遗迹、极寒冰原、天空群岛、深渊世界；星辰大陆完整探索仍未完成。

## 当前问题

- 正在处理：Developer 修复 `BUG-SPAWN-001` 的 filter/有界扫描/desktop input contract/六 Seed×五 Profile/相邻地形/leak 三轮门禁，并按 QA-002 返回的完整按钮状态修复 `BUG-UI-002`。
- 已发现：`BUG-REL-001`、`BUG-UI-001`、`BUG-PERF-001`、`BUG-OBS-001`、`BUG-QA-002`、`BUG-UI-002`、`BUG-SPAWN-001`、`BUG-VERSION-001`、`BUG-PACK-001`。
- 已修复并独立 QA 通过：`BUG-QA-002`。
- 已修复但 QA 失败返回：`BUG-UI-002`（布局改善，但多个实际按钮 normal/hover/pressed/focus 对比度 <4.5）。
- 待回归：`BUG-UI-002` 待 Developer 二轮 self-test 后 QA-003；`BUG-SPAWN-001` 仍在 bugfixing。
- QA-002 用户数据保护：12 世界、31 个 world/settings 文件前后 added/removed/changed 均 0；清单摘要 `80A239102203D05878F50ED920D0D48078D5B4CE3B03751723D4AD40EE07DCB6`。

## 最近命令

```powershell
& 'C:\Program Files\Git\bin\bash.exe' 'C:\Users\sirius\.codex\skills\dev-baseline\shared\scripts\validate-task-readiness.sh' 'docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish'
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\ci\run_godot_desktop_test.ps1 -Godot <Godot-4.7-console> -ProjectRoot . -ScriptPath res://tests/qa/ui_visual_refresh_desktop_acceptance.gd -OutputPath build/developer-selftest-ui002/ui-visual-refresh-main.png
```

## 最近有效存档

- production-scene UI journey 创建并删除 4 个唯一 QA 世界；现有 12 个世界测试前后文件数和 SHA-256 全部一致。
- 用户数据保护备份：`C:\Users\sirius\AppData\Local\Temp\starworld-qa-backups\20260731-101853`。
- 仍未完成真实保存→退出→读档验收。

## GUI/桌面证据

- Computer Use fresh EXE：窗口唯一识别并运行 66.3 秒，`Responding=True`；因 `0x80070005` 无法激活/捕获，未发送盲输入；通过 `CloseMainWindow()` 正常退出。
- export-EXE 证据：`build/release-readiness-fresh-pwsh7`，仅 16-check release smoke。
- production-scene desktop InputEvent 证据：`build/release-readiness-ui-flow`，内层 32 checks / 10 captures 通过；外层 runner 因主截图契约不一致退出 1，见 `BUG-QA-002`。
- 现有用户数据：12 个世界、29 个世界文件、settings 与回收站测试前后 SHA-256/路径完全一致。

## 下一步

1. Developer 修复 `desktop_input_contract` 红灯并解释根因，不得只改断言。
2. 先修 spawn 单组合 filter 的 typed-array script error；用 ≤30 秒跑 `star_continent/24681357` 并输出 wall/termination/budget/scanned/evaluated/score/hard_safe/degraded，再扩 6×5。
3. `BUG-SPAWN-001` 完成合成遮挡/相邻地形/旧档/解析器、隔离无存档 input contract、三轮 ObjectDB leak 门禁并报告。
4. Developer 修 `BUG-UI-002` 全交互状态对比度并扩展测试；同一 QA 执行 QA-003。
5. 以上通过后再进入 REL/PACK/font，随后性能/遥测和五 Profile 正常入口发布旅程。
6. 75 个本轮 editor scan 生成的未跟踪 `.uid/.import` 元数据待 Developer 退出后精确清理；不得触碰用户源码/QA 文档。
