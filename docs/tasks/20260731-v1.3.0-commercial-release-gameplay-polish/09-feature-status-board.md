# Feature Status Board

This board was reconciled on 2026-08-06 after Iteration 59. Historical July preparation records remain in the other task documents; this file now reflects the actual merged implementation and evidence state rather than the abandoned initial snapshot.

## Evidence grades

- `accepted-repository`: production implementation plus permanent automated evidence is complete.
- `external-hold`: repository work is complete, but a real external evidence package is still required.

## Board

| Function Point | Implementation | Validation | Acceptance | Evidence | Updated At | Notes |
|---|---|---|---|---|---|---|
| FP-001 | complete | passed | accepted-repository | build/import/log/save/automation discovery and permanent gates | 2026-08-06 | current source, Godot 4.7 and Windows release paths are governed |
| FP-002 | complete | passed | accepted-repository | five profiles, content registries and coverage matrices | 2026-08-06 | formal content inventory is deterministic and validated |
| FP-003 | complete | passed | accepted-repository | fresh export, launch, quit, create-world and Release lifecycle report | 2026-08-06 | Iteration 59 adds scene/world/save/quit timing and resource evidence |
| FP-004 | complete | passed | accepted-repository | five-profile production routes and closed-loop player journeys | 2026-08-06 | no post-spawn transport or direct transform writes in final route evidence |
| FP-005 | complete | passed | accepted-repository | collision, seam, fall, block shape and recovery regressions | 2026-08-06 | includes exact sky-island descent and connected partial shapes |
| FP-006 | complete | passed | accepted-repository | water/lava lifecycle, survival and save/reload regressions | 2026-08-06 | repository-automatable water state is covered |
| FP-007 | complete | passed | accepted-repository | save recovery, session recovery, trash integrity, death/respawn and world switching | 2026-08-06 | wrong-id/all-corrupt trash candidates fail with world_payload_unrecoverable |
| FP-008 | complete | passed | accepted-repository | UI, accessibility, controller, high-DPI, audio and settings matrices | 2026-08-06 | production focus graph and 3440×1440 evidence are permanent |
| FP-009 | complete | passed | external-hold | bounded performance metrics, hosted soak and long-term campaigns | 2026-08-06 | minimum/recommended real hardware and 7,200-second target soak remain external |
| FP-010 | complete | passed | accepted-repository | permanent workflows, static contracts, headless/desktop/export regressions | 2026-08-06 | Iteration 59 adds the cross-domain campaign and fault injection |
| FP-011 | complete | passed | external-hold | roadmap, audits, issue ledger, release reports and risk boundaries | 2026-08-06 | independent E4-H sign-off still required before commercial release |

## Iteration 59 closure

- Trash restore validates `world.json`, temporary and backup candidates before promotion.
- Release lifecycle evidence is written to `user://diagnostics/release-lifecycle-report.json` and never to `world.json`.
- One campaign combines hostile death/reward/drop, Chunk hot return, pane/fence adjacency and structural cleanup.
- The previous “0/5 journeys, 0 commits, seven high-priority defects” snapshot is retired as historical and must not be used for planning.

## Commercial decision

Repository-automatable scope is accepted. Commercial release remains **HOLD** for independent E4-H review, real minimum/recommended target hardware, and the strict 7,200-second final-package target-hardware soak.
