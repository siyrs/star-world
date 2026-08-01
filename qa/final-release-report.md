# 《星的世界》最终发布质量报告

状态：**DRAFT — 代码工作完成，运行时验证待执行**

生成时间：2026-08-01
分支：`codex/commercial-release-gameplay-polish`
HEAD：`f06be2e`（10 commits）

## 执行摘要

- 项目是否达到发布标准：**否**，五 Profile 桌面验收旅程 0/5 完成，性能/长稳证据为空
- 测试地图总数：5（星辰大陆、荒漠遗迹、极寒冰原、天空群岛、深渊世界）
- 出生验证：5 Profile × 6 seeds 全矩阵 279 checks 通过（p50 0.809s / p95 2.766s）
- 修复 Bug 数：6/9 已闭合（REL-001, UI-001, PACK-001, VERSION-001, QA-002, OBS-001）
- 剩余 Bug 数：3（UI-002 待运行时验证, SPAWN-001 待运行时验证, PERF-001 open）
- 当前推荐：**不发布** — 等待全内容实测、性能对比长稳、独立 QA 重测

## 代码变更

10 个提交，均在独立分支 `codex/commercial-release-gameplay-polish`（已推送 origin）：

| 提交 | 说明 |
|---|---|
| `06cf1bf` | 初始提案 + 16 文档 + WIP spawn/UI |
| `6ec3545` | codex 审计修复：编译错误、hard_safe、fallback、版本、UI回归 |
| `078be45` | 发布工具链：PS5.1 检测、字体 preload、PCK 排除、.gitignore |
| `30a0260` | 树冠障碍物夹具 + openspec 进度更新 |
| `21c6b63` | codex 二轮审计：UI 语法错误、modify_resources、fallback X/Z、真 canopy fixture、validator 文案同步 |
| `be644b0` | codex 三轮审计：浮点截断→get_surface_height、fallback 双半径扫描、Toolbar 对比度、Card/Selected pressed font role、disabled 检查 |
| `ef2e438` | codex 四轮审计：disabled 边界 `<=`、fallback origin column 扫描 |
| `4191114` | codex 五轮审计：alpha compositing `_effective_background()`、fallback range 含 y=0 + y+1.05 |
| `efc50cd` | ObjectDB 泄漏清理 + 外部内存 Working Set 采样 |
| `f06be2e` | 内部 MEMORY_STATIC 标记 -1.0 不可用 + health policy 跳过评估 |

## Bug 修复清单

| Bug | 严重度 | 状态 | 修复摘要 |
|---|---|---|---|
| BUG-REL-001 | P1 | **fixed** | PS5.1 前置版本检测，提前失败并提示 pwsh |
| BUG-UI-001 | P2 | **fixed** | `preload` 字体资源确保导出包含；stderr 无 warning |
| BUG-PACK-001 | P1 | **fixed** | `build/*` `qa/*` 加入 export_presets.cfg exclude_filter |
| BUG-VERSION-001 | P1 | **fixed** | project.godot 1.3.0 + export_presets 1.3.0.0 + app_version.gd 1.3.0；modify_resources=true 嵌入 EXE |
| BUG-QA-002 | P1 | **qa-passed** | desktop acceptance 主截图契约修复，QA-002 独立 PASS |
| BUG-OBS-001 | P2 | **fixed** | MEMORY_STATIC ≤0 返回 -1.0 标记不可用；health policy 跳过评估 |
| BUG-UI-002 | P1 | **fixing** | 面板按钮对比度修复（Toolbar/Card/Selected/Ghost）；alpha 融合背景计算；纹理按钮仅验证存在性 |
| BUG-SPAWN-001 | P1 | **fixing** | 数据驱动安全出生；5×6 矩阵 279 checks 通过；canopy fixture overhead 检查；ObjectDB 泄漏清理代码已加 |
| BUG-PERF-001 | P1 | **open** | chunk 队列收敛时间序列待采集 |

## 功能点状态

| FP | 描述 | 状态 |
|---|---|---|
| FP-001 | Git/构建/运行/自动化入口 | in-progress（fresh export PASS） |
| FP-002 | 地图与内容发现 | implemented（5 profiles + 内容边界） |
| FP-003 | 可重复构建/启动/退出 | in-progress（fresh export PASS；PS5.1 已处理） |
| FP-004 | 全部地图正常路径与通关 | not-started（0/5 profile journeys） |
| FP-005 | 碰撞/边界/恢复 | not-started |
| FP-006 | 水域/水下系统 | not-started |
| FP-007 | 存读档/死亡复活/切换 | not-started |
| FP-008 | UI/输入/设置体验 | in-progress（对比度代码已修，待运行时验证） |
| FP-009 | 性能基线/长稳 | not-started |
| FP-010 | QA 自动化/修复/回归闭环 | in-progress（spawn 矩阵 + UI 回归已有） |
| FP-011 | 提交/覆盖矩阵/最终报告 | in-progress（10 commits；矩阵已更新） |

## 自动化能力

- `tests/run_all.ps1`：全量回归入口（含 spawn_experience_regression）
- `tests/release/run_windows_export_smoke.ps1`：fresh export + smoke + 外部内存采样
- `tests/qa/spawn_experience_regression.gd`：5×6 seeds 出生矩阵（279 checks）
- `tests/qa/ui_design_system_regression.gd`：107 checks 覆盖 overlay + panel 按钮对比度
- `tests/qa/ui_visual_refresh_desktop_acceptance.gd`：桌面 UI 自动化（主截图 + 命名截图）
- PS5.1 检测 + pwsh 前置提示
- ObjectDB 泄漏自动检测（CI runner Assert-NoFatalGodotLog）

## 剩余风险

- 五 Profile 桌面验收旅程 0/5 完成 — 无法证明正常玩家路径可游玩
- 性能基线/长稳证据为空 — 无法证明无内存泄漏或长时退化
- 存读档/死亡复活/地图切换/水域/熔岩/碰撞边界均未实测
- UI 纹理按钮（Button/Primary/Secondary/Danger/MenuPrimary）各状态对比度未量化
- 27 ObjectDB 泄漏 + 8 未释放资源（代码修复已加，待运行时验证）
- OpenSpec 13/47 完成；34 项待执行（其中 24 项需 Godot 运行时）

## 发布建议

**不发布。** 代码和文档侧工作已完成，但运行体验证侧几乎空白。需要：
1. 五 Profile 完整桌面验收旅程
2. 性能基线 + 120min 长稳
3. 全量 `tests/run_all.ps1` 通过（0 P0/P1 failures, 0 ObjectDB leaks）
4. 独立 QA 重测 UI 和 spawn 修复
5. 最终 fresh export 全项通过
