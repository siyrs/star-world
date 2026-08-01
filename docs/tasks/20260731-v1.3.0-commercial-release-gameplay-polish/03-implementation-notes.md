# Implementation Notes

## Implementation Summary
- 首批实施包：BUG-QA-002 (runner 契约)、BUG-UI-002 (可读性)、BUG-SPAWN-001 (出生体验)，随后 BUG-REL-001、BUG-PACK-001、BUG-UI-001、BUG-VERSION-001。

## Change Log by Step

### Step 1: BUG-QA-002 — Desktop acceptance runner contract
- Files changed: `tests/qa/ui_visual_refresh_desktop_acceptance.gd`
- What changed: `_capture()` 新增 `write_primary` 参数；首次 main-menu capture 同时写 primary 和 named 截图；JSON report 记录 primary_capture 路径
- Why: 外层 runner 要求精确 `-OutputPath` 主截图存在；原实现只写命名截图
- Self-check result: QA-002 独立 PASS — 32/10 checks，primary SHA-256 核验通过

### Step 2: BUG-UI-002 — UI 对比度与可读性（首轮）
- Files changed: `src/ui/design_tokens.gd`、`src/ui/theme_factory.gd`、`src/ui/map_selection_panel.gd`、`src/ui/settings_panel.gd`、`tests/qa/ui_design_system_regression.gd`
- What changed: Panel context 按钮/标签移除黑暗像素阴影；flat_button 字体颜色从 CONTEXT_OVERLAY 改为 context 参数；map/settings 面板 header spacing 从 XS 改为 SM；MC_PANEL_TEXT_MUTED 加深 (#5C5C5C → #525252)；新增 MC_PANEL_ACCENT/WARNING tokens；CardButton panel 背景色调整
- Why: 地图选择和设置面板文字在灰色背景上对比度不足
- Self-check result: 首轮 headless 64 checks + desktop 32/10 通过；QA-002 独立 FAIL — 多个按钮状态对比度 <4.5

### Step 2b: BUG-UI-002 — WCAG 对比度修复（二轮）
- Files changed: `src/ui/theme_factory.gd`
- What changed: GhostButton panel hover/pressed fills 改为浅色 (dark→light)；CardButton panel pressed fill 略提亮 (#A8A8A8 → #B7B7B7)；ToolbarButton panel fills 使用浅色
- Why: 面板上下文中半透明深色填充使有效背景过暗，深色文字对比度不足 4.5:1
- Self-check result: 待 QA-003 独立重测

### Step 3: BUG-SPAWN-001 — 出生体验（首轮 + 迭代）
- Files changed: `src/world/world_generator.gd`、`src/world/spawn_quality_registry.gd` (新增)、`data/spawn_quality_profiles.json` (新增)、`tests/qa/spawn_experience_regression.gd` (新增)、`tests/run_all.ps1`
- What changed: 数据驱动多维度评分出生选择 (净空/步行/视野/障碍物邻近度)；有界候选预算；三级 fallback；Registry 提供验证与内置回退；5 profiles × 6 固定 seeds 回归
- Why: 原逻辑首个合格即返回且只检查单列 headroom，未评分近邻实体/视野
- Self-check result: 首轮 5×3=108 checks 通过但缺关键 seed 24681357；相邻 input contract 红灯；leak 三轮未闭合；二轮 bugfixing

### Step 4: 版本号统一
- Files changed: `project.godot`
- What changed: `config/version` 从 "1.1.0" 更新为 "1.3.0"
- Why: 目标版本 v1.3.0 与源码中声明的 1.1.0 不一致；历史版本为 v1.2.0
- Self-check result: 待 fresh export 验证 EXE 属性和菜单显示

### Step 5: 代码质量改进
- Files changed: `src/world/world_generator.gd`、`src/world/spawn_quality_registry.gd`
- What changed: `_is_finite_spawn()` → `_is_valid_spawn_found()`；`_evaluate_spawn_candidate()` 拆分为 4 个子函数；`spawn_quality_registry._record_error` 中 `push_error` → `push_warning`
- Why: 命名不准确、函数过长、错误级别不当（registry 有内置回退，不应 push_error）
- Self-check result: 待 CI 回归

## Developer Self-test Evidence
| Check | Command / Method | Result | Notes |
|---|---|---|---|
| editor scan | Godot editor import scan | 无解析错误 | 75 个 .uid 文件待清理 |
| run_all regression | `tests/run_all.ps1` (pwsh) | 待执行 | spawn 测试已加入 suite |
| fresh release smoke | `pwsh tests/release/run_windows_export_smoke.ps1` | 待二轮 | 版本号已变更 |

## Known Limitations
- 纹理按钮 (Button/Primary/Danger 等) 在 Panel 上下文中仍使用 overlay 默认配色，context-panel 下不适用但 map/settings 面板未使用这些按钮类型
- export-EXE GUI 输入仍因 Computer Use `0x80070005` 阻塞，production-scene InputEvent 为当前桌面证据来源

## Handoff to QA
- Ready for QA: yes
- Handoff time: 2026-08-01
- Notes: BUG-UI-002 二轮修复、版本号、代码质量改进交付；待 QA-003 独立重测；SPAWN-001 仍在 bugfixing
