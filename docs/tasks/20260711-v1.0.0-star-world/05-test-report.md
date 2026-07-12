# Test Report

## Test Summary
- Tester: independent QA agent, then Root fallback after PM/QA usage interruption
- Test time: 2026-07-11
- Environment: Windows x64, Godot 4.7 stable official, OpenGL Compatibility, NVIDIA RTX 3090
- Branch / Commit: uncommitted initial repository (user did not request Git publish)
- Result: pass

## Test Results
| Case ID | Related AC | Scenario | Result | Evidence Link | Screenshot | Log | Command | Notes |
|---|---|---|---|---|---|---|---|---|
| TC-001 | AC-001 | Project scan, boot and visible main menu | pass | `project.godot`, final EXE | visible final package window | clean | editor scan; EXE boot | usable menu rendered |
| TC-002 | AC-002 | Five deterministic profiles boot distinct terrain | pass | `core_smoke_test.gd` | visual capture | 100-check suite | `tests/run_all.ps1` | all profiles render and camera spawn is clear |
| TC-003 | AC-003 | Chunk collision, player APIs, add/remove, combat | pass | core + integration suites | gameplay capture | clean | `tests/run_all.ps1` | mine/place/attack paths exercised |
| TC-004 | AC-004 | Inventory, stacking and 42 recipes | pass | gameplay suite | HUD/hotbar capture | 50-check suite | `tests/run_all.ps1` | 62 registered items |
| TC-005 | AC-005 | Survival, time, food and four creatures | pass | gameplay + integration suites | gameplay capture | clean | `tests/run_all.ps1` | death/drop and hurt/creature audio exercised |
| TC-006 | AC-006 | Save round-trip and sparse building restore | pass | core + gameplay + integration suites | n/a | clean | `tests/run_all.ps1` | multiple IDs and closure routing verified |
| TC-007 | AC-007 | UI/settings/audio/docs/Windows package | pass | QA suites + quality gate + build hashes | menu/gameplay captures | clean | quality gate; export; EXE boot | no TMP or error markers |

## Bugs Found
| Bug ID | Severity | Description | Reproduction Steps | Status |
|---|---|---|---|---|
| BUG-001 | P0 | Variant pop-front parse failure | launch project | closed |
| BUG-QA-001 | P1 | PowerShell 5.1 UTF-8 validation | run data validator | closed |
| BUG-QA-002 | P0 | concurrent Windows export/TMP residue | export from two processes | closed |
| BUG-PM-003 | P1 | settings and chunk distance invariant | apply render distance | closed |
| BUG-PM-004 | P1 | missing live attack/eat/audio/lifecycle | use player interactions | closed |
| BUG-ROOT-005 | P0 | camera spawned inside leaves | real OpenGL capture | closed |

## Retest Results
| Bug ID | Retest Case ID | Related AC | Result | Evidence Link | Screenshot | Log | Command | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG-001..BUG-ROOT-005 | RTC-001..006 | AC-001..007 | pass | bugfix log and suites | corrected captures | clean | one-command regression + final export | all fixes independently or root-fallback retested |

## Regression Result
- Data registry passed: 62 items, 42 recipes, 5 maps, 4 creatures.
- Godot runtime passed: 193/193 checks (100 core + 50 gameplay + 34 integration + 9 settings).
- Editor scan, project boot, real OpenGL visual capture, Windows release export and exported EXE boot all passed.
- Dev Baseline quality gate passed all documentation, sync and secret checks.

## QA Decision
- Passed QA: yes
- Needs bugfix: no
- Retest required after bugfix: no
- Notes: no open P0/P1 defects; simplified-v1 limitations are documented product boundaries.
