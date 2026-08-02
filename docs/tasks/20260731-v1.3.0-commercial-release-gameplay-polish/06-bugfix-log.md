# Bugfix Log

## Bugfix Summary
- 已登记 9 个产品/工具问题 (P1×6, P2×2, 外部工具边界×1)
- 已修复并 QA 通过：BUG-QA-002
- 已修复并 QA 失败返回：BUG-UI-002 (首轮)
- 正在修复：BUG-SPAWN-001, BUG-UI-002 (二轮)
- 待修复：BUG-REL-001, BUG-UI-001, BUG-PERF-001, BUG-OBS-001, BUG-VERSION-001, BUG-PACK-001

## Bugfix Records
| Bug ID | Root Cause | Fix Summary | Files Changed | Self-test | Status |
|---|---|---|---|---|---|
| BUG-QA-002 | Desktop acceptance 只写命名截图，未兑现 runner 要求的精确主截图路径 | 在 `_capture("main-menu", true)` 同时写 primary 和 named 截图 | `tests/qa/ui_visual_refresh_desktop_acceptance.gd` | pass | qa-passed |
| BUG-UI-002 | Panel 按钮/标签继承 overlay shadow 和低对比配色；首轮仅修 normal 状态 | 移除 panel context shadow；flat button font_color 使用 context 参数；二轮 Ghost/Card hover&pressed fills 从深色→浅色 | `src/ui/design_tokens.gd`, `src/ui/theme_factory.gd`, `src/ui/map_selection_panel.gd`, `src/ui/settings_panel.gd`, `tests/qa/ui_design_system_regression.gd` | pass (首轮) / 待测 (二轮) | fixing |
| BUG-SPAWN-001 | 原生成器首个合格即返回，只检查 headroom，未评分近邻实体 | 数据驱动候选评分：净空/步行/视野/障碍物；有界预算；三级 fallback | `src/world/world_generator.gd`, `src/world/spawn_quality_registry.gd`, `data/spawn_quality_profiles.json`, `tests/qa/spawn_experience_regression.gd`, `tests/run_all.ps1` | 首轮 108 checks pass / 二轮待闭合 | fixing |
| BUG-VERSION-001 | 版本元数据未随后续功能提交同步 | `project.godot` config/version 1.1.0 → 1.3.0 | `project.godot` | 待 fresh export 验证 | fixing |

## Retest Notes
- BUG-QA-002: QA-002 独立 retest PASS
- BUG-UI-002: 首轮 retest FAIL → 二轮修复待 QA-003
- BUG-SPAWN-001: 首轮未通过 entry gate → 二轮修复中

## Developer Notes
- 75 个 editor-scan 生成的 .uid/.import 文件待清理
- 勿提交 build/ 目录下的 QA 证据文件

## Handoff Back to QA
- Ready for retest: partial (BUG-UI-002 二轮可测；SPAWN-001 不可测)
- Handoff time: 2026-08-01
- Notes: UI 对比度二轮修复 + 版本号 + 代码质量改进已自测；待同一 QA 执行 QA-003

## QA Retest Loop
- Retest completed: no
- Remaining open P0/P1 bugs: 7 (BUG-REL-001, BUG-UI-001, BUG-PERF-001, BUG-UI-002, BUG-SPAWN-001, BUG-VERSION-001, BUG-PACK-001)
- Returned to Developer: yes (BUG-UI-002; SPAWN-001 仍在 Developer 侧)
- Notes: BUG-UI-002 二轮待 QA-003，SPAWN-001 待闭合 input-contract + seed/leak 门禁
