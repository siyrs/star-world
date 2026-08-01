# Test Report

## Test Summary
- Tester: QA Tester (QA-001 strategy) + Developer (self-test) + QA Tester (QA-002 independent retest)
- Test time: 2026-07-31
- Environment: Windows x64, Godot 4.7, GL Compatibility
- Branch / Commit: `codex/commercial-release-gameplay-polish` / working tree (no commits yet)
- Result: blocked (P0/P1 bugs still open; SPAWN-001 and BUG-UI-002 not yet passed)

## Test Results
| Case ID | Related AC | Scenario | Result | Evidence Link | Notes |
|---|---|---|---|---|---|
| TC-001 | AC-001 | Fresh export/smoke | partial | `build/release-readiness-fresh-pwsh7` | pwsh7 通过；PS5.1 失败 (BUG-REL-001)；字体 warning (BUG-UI-001)；chunk warning (BUG-PERF-001)；memory 0.0 (BUG-OBS-001) |
| TC-002 | AC-002,AC-003 | Map/content discovery | pass | `qa/map-coverage-matrix.md` | 5 正式 Profile 已发现；无传统通关 |
| TC-003 | AC-002,AC-003 | Star Continent journey | in-progress | production-scene desktop | 仅 smoke/desktop 测试直达，非完整旅程 |
| TC-004..TC-020 | AC-002..AC-010 | Remaining cases | not-started | - | 等待 spawn 和 UI 修复闭合 |

## Bugs Found
| Bug ID | Severity | Description | Status |
|---|---|---|---|
| BUG-REL-001 | P1 | PS5.1 release smoke 兼容 | open |
| BUG-UI-001 | P2 | 像素字体缺失 warning | open |
| BUG-PERF-001 | P1 | chunk 队列健康 warning | open |
| BUG-OBS-001 | P2 | 内存指标 0.0 不可信 | open |
| BUG-QA-002 | P1 | Desktop acceptance runner 契约 | qa-passed |
| BUG-UI-002 | P1 | UI 按钮交互状态对比度 | fixing (二轮) |
| BUG-SPAWN-001 | P1 | 出生体验 | fixing |
| BUG-VERSION-001 | P1 | 版本身份不一致 | fixing (project.godot 已更新为 1.3.0) |
| BUG-PACK-001 | P1 | QA 资源误入 PCK | open |

## Retest Results
| Bug ID | Retest Case ID | Result | Evidence Link | Notes |
|---|---|---|---|---|
| BUG-QA-002 | RTC-QA-002 | pass | `build/qa-independent-qa002-20260731-1057` | QA-002 独立 PASS |
| BUG-UI-002 | RTC-UI-002 | fail | `build/qa-independent-qa002-20260731-1057` | 二轮修复待 QA-003 |

## Regression Result
- 全量发布回归 checklist 仍未启动 (0/10)

## QA Decision
- Passed QA: no
- Needs bugfix: yes (SPAWN-001, BUG-UI-002, + 6 open bugs)
- Retest required after bugfix: yes (QA-003 for UI, separate for spawn)
- Notes: 当前不满足发布条件；需闭合所有 P0/P1 后方可 QA 通过
