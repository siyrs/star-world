# Feature Status Board

Track each function point across PM, active specialist agents, validation, and acceptance.

## Status Flow

```text
not-started -> in-progress -> implemented -> self-tested -> qa-testing -> qa-passed -> accepted
```

Rejected items move to `bugfixing` before returning to self-test and QA test.

## Board

| Function Point | Requirement | Specialist Review | Implementation | Validation | Acceptance | Owner | Updated At | Notes |
|---|---|---|---|---|---|---|---|---|
| FP-001 | confirmed | reviewed | in-progress | in-progress | not-started | Developer + QA | 2026-08-01 +08:00 | fresh build/smoke pwsh7 passed; PS5.1/font/chunk/memory issues open |
| FP-002 | confirmed | reviewed | implemented | in-progress | not-started | PM + QA | 2026-08-01 +08:00 | 5 profiles + content boundary discovered; no complete journeys |
| FP-003 | confirmed | reviewed | in-progress | not-started | not-started | Developer | 2026-08-01 +08:00 | version 1.3.0 set in project.godot; PACK-001 still open |
| FP-004 | confirmed | pending | not-started | not-started | not-started | Developer + QA | 2026-08-01 +08:00 | 0/5 profile journeys completed |
| FP-005 | confirmed | pending | not-started | not-started | not-started | Developer + QA | 2026-08-01 +08:00 | collision/boundary/fall-through |
| FP-006 | confirmed | pending | not-started | not-started | not-started | Developer + QA | 2026-08-01 +08:00 | water/underwater |
| FP-007 | confirmed | pending | not-started | not-started | not-started | Developer + QA | 2026-08-01 +08:00 | save/task/death-respawn/switch |
| FP-008 | confirmed | reviewed | bugfixing | qa-failed | not-started | Developer | 2026-08-01 +08:00 | BUG-UI-002 round 2: Ghost/Card hover&pressed fills fixed; pending QA-003 |
| FP-009 | confirmed | pending | not-started | not-started | not-started | Developer + QA | 2026-08-01 +08:00 | perf/long-run/logs |
| FP-010 | confirmed | reviewed | in-progress | qa-testing | not-started | Developer + QA | 2026-08-01 +08:00 | BUG-QA-002 qa-passed; SPAWN-001 bugfixing |
| FP-011 | confirmed | reviewed | in-progress | in-progress | not-started | PM | 2026-08-01 +08:00 | core files tracked; all template docs filled; commit gate still blocked |

## Status Event Log

| Time | Function Point | From | To | Owner | Note |
|---|---|---|---|---|---|
| 2026-07-31 10:08 +08:00 | FP-001,FP-002 | not-started | in-progress | Analyst | Packet A-001 discovery |
| 2026-07-31 10:27 +08:00 | FP-001,FP-002,FP-008,FP-010,FP-011 | readiness | in-progress | PM | validator exit 0; Developer authorized |
| 2026-07-31 10:52 +08:00 | FP-008 | in-progress | qa-testing | Developer + QA | UI self-test handoff to QA-002 |
| 2026-07-31 10:52 +08:00 | FP-010 | self-tested | bugfixing | Developer | spawn adjacent input-contract red light |
| 2026-07-31 11:03 +08:00 | FP-010 | qa-testing | qa-passed | QA | BUG-QA-002 independent PASS |
| 2026-07-31 11:03 +08:00 | FP-008 | qa-testing | bugfixing | Developer | BUG-UI-002 independent FAIL |
| 2026-08-01 +08:00 | FP-003 | not-started | in-progress | Developer | version 1.3.0 set in project.godot |
| 2026-08-01 +08:00 | FP-008 | bugfixing | bugfixing | Developer | round 2 WCAG fix (Ghost/Card light fills); pending QA-003 |
| 2026-08-01 +08:00 | FP-011 | in-progress | in-progress | Developer | core files tracked; template docs populated |

## Agent Notes

Record which specialist agents are active in `10-collaboration-log.md`. Use `not-needed` when PM intentionally skips a specialist role.
