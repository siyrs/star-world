# Bugfix Log

| Bug ID | Time | Severity | Function | Evidence | Owner | Status | Required retest |
|---|---|---|---|---|---|---|---|
| BUG-001 | 2026-07-11 | P0 | FP-003 world startup | earlier real headless launch reported Variant inference warning-as-error at `voxel_world.gd:77` | DEV-C | fixed-and-retested | PM independently verified exact explicit conversion and real `--headless --path . --quit-after 30`, exit 0/no errors |
| BUG-QA-001 | 2026-07-11 | P1 | FP-005/006 validation portability | Windows PowerShell 5.1 decodes UTF-8 JSON as ANSI in `tests/developer_b/validate_data.ps1`, causing `ConvertFrom-Json` failure | DEV-B | fixed-and-retested | four explicit `-Encoding UTF8` reads; independent QA Windows PowerShell 5.1 exit 0, 62/42/5/4 PASS |
| BUG-QA-002 | 2026-07-11 | P0 delivery | FP-001 Windows package | concurrent exports plus resource modification caused `_modify_template ERR_CANT_OPEN` and a `StarWorld.exe~*.TMP` artifact | DEV-C | fixed-and-retested | `modify_resources=false`; QA isolated serial export exit 0, exactly EXE+PCK/no TMP, isolated EXE exit 0 |
| BUG-PM-003 | 2026-07-11 | P1 | FP-010 settings | settings application was added, but render distance 4..6 could exceed fixed unload distance 3 and trigger chunk load/unload thrashing | DEV-D | fixed-and-retested | option 6 removed, clamp 1..5, unload distance = render distance + 1; 50 gameplay + 9 settings checks pass |
| BUG-QA-003 | 2026-07-11 | P2 docs | Delivery status | `00-index.md` retained stale `todo` rows after readiness/implementation/QA progress | PM | fixed-and-retested | QA marker/status rescan passed; all preparation gates done and live stages accurate |
| BUG-PM-004 | 2026-07-11 | P1 gameplay | FP-004/007/008/010 | player could not attack/eat; gameplay audio wiring was incomplete; creature spawner stayed active with old creatures across return/menu world changes | DEV-D | fixed-and-retested | 34 integration checks prove attack/death/drop, food, audio, spawner and world cleanup |
| BUG-ROOT-005 | 2026-07-11 | P0 visual | FP-003/004 | real OpenGL capture showed the first-person camera spawned inside a tree leaf cell | Root fallback | fixed-and-retested | spawn finder now requires three clear cells; five-map camera-clear assertions pass and recapture shows camera block `air` with visible terrain |

## Rules

- A code assertion does not close a bug. Developer fixes and self-tests, then independent PM/QA retest closes it.
- BUG-001 fix must use explicit `Vector2i(...)` conversion to remove the ambiguous Variant assignment.

## Retest evidence

- Source inspected: line 77 is `var next_coord := Vector2i(pending_chunks.pop_front())`.
- Command: official Godot 4.7 console, `--headless --path . --quit-after 30`.
- Result: exit 0 in 3.6s; banner only; no `SCRIPT ERROR` or `ERROR`.
