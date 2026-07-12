# Feature Status Board

Status flow: `not-started -> in-progress -> implemented -> self-tested -> qa-testing -> qa-passed -> accepted`; QA rejects to `bugfixing`.

| Function Point | Requirement | Specialist Review | Implementation | Validation | Acceptance | Owner | Updated At | Notes |
|---|---|---|---|---|---|---|---|---|
| FP-001 | confirmed | reviewed | self-tested | qa-passed | accepted | Team | 2026-07-11 | final EXE/PCK and visible main menu verified |
| FP-002 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-C/Root QA | 2026-07-11 | 30 blocks, mesh, collision, add/remove |
| FP-003 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-C/Root QA | 2026-07-11 | five seeded maps, safe spawn, dynamic chunks |
| FP-004 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-D/Root QA | 2026-07-11 | movement, mining, placement, combat, hotbar |
| FP-005 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-B/Root QA | 2026-07-11 | 62 items, 36 slots, stack/swap/persistence |
| FP-006 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-B/Root QA | 2026-07-11 | 42 real recipes across three stations |
| FP-007 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-B/DEV-D/Root QA | 2026-07-11 | health, hunger, food, death, respawn, day/night |
| FP-008 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-B/DEV-D/Root QA | 2026-07-11 | four creatures, AI, attack, death and drops |
| FP-009 | confirmed | reviewed | self-tested | qa-passed | accepted | DEV-B/DEV-C/Root QA | 2026-07-11 | multi-world JSON and sparse building restore |
| FP-010 | confirmed | reviewed | self-tested | qa-passed | accepted | Team | 2026-07-11 | HUD, menu, settings, audio and docs |

## Status Event Log

| Time | Function Point | From | To | Owner | Note |
|---|---|---|---|---|---|
| 2026-07-11 | FP-001..FP-010 | not-started | in-progress | DEV-A/DEV-B | readiness validated; scoped implementation started |
| 2026-07-11 | FP-001..FP-010 | in-progress/bugfixing | self-tested | Developers | implementation and focused bugfix loops completed |
| 2026-07-11 | FP-001..FP-010 | self-tested | qa-passed | QA/Root fallback | data validation + 193 runtime checks + visual/package QA passed |
| 2026-07-11 | FP-001..FP-010 | qa-passed | accepted | Root acting for interrupted PM | all AC covered; no open P0/P1 bugs |
