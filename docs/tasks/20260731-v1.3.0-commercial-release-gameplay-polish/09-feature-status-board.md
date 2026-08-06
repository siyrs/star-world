# Feature Status Board

This board was reconciled on 2026-08-06 after Iteration 61. Historical July preparation records remain in the other task documents; this file reflects the current implementation, repository evidence and external commercial-release state.

## Evidence grades

- `accepted-repository`: production implementation plus permanent automated evidence is complete.
- `qualification-kit-ready`: the repository-owned collector, schema, chain-of-custody and anti-forgery workflows are complete, but humans and physical machines must still produce the evidence.
- `external-hold`: a real external evidence package is still required before commercial release.

## Board

| Function Point | Implementation | Validation | Acceptance | Evidence | Updated At | Notes |
|---|---|---|---|---|---|---|
| FP-001 | complete | passed | accepted-repository | build/import/log/save/automation discovery and permanent gates | 2026-08-06 | current source, Godot 4.7 and Windows release paths are governed |
| FP-002 | complete | passed | accepted-repository | five profiles, content registries and coverage matrices | 2026-08-06 | formal content inventory is deterministic and validated |
| FP-003 | complete | passed | accepted-repository | fresh export, launch, quit, create-world and Release lifecycle report | 2026-08-06 | scene/world/save/quit timing and resource evidence are permanent |
| FP-004 | complete | passed | accepted-repository | five-profile production routes and closed-loop player journeys | 2026-08-06 | no post-spawn transport or direct transform writes in final route evidence |
| FP-005 | complete | passed | accepted-repository | collision, seam, fall, block shape and recovery regressions | 2026-08-06 | includes exact sky-island descent and connected partial shapes |
| FP-006 | complete | passed | accepted-repository | water/lava lifecycle, survival and save/reload regressions | 2026-08-06 | repository-automatable water state is covered |
| FP-007 | complete | passed | accepted-repository | save recovery, session recovery, trash integrity, death/respawn and world switching | 2026-08-06 | wrong-id/all-corrupt trash candidates fail with world_payload_unrecoverable |
| FP-008 | complete | passed | accepted-repository | UI, accessibility, controller, high-DPI, audio and settings matrices | 2026-08-06 | production focus graph and 3440×1440 evidence are permanent |
| FP-009 | complete | passed | qualification-kit-ready / external-hold | exact-package hardware collectors, strict soak harness, immutable candidate ID and complete 19-file evidence payload | 2026-08-06 | real minimum/recommended machines and real 7,200-second target soak remain external |
| FP-010 | complete | passed | accepted-repository | permanent workflows, static contracts, headless/desktop/export regressions | 2026-08-06 | includes cross-domain campaigns, qualification anti-forgery and visible/hidden transport-integrity gates |
| FP-011 | complete | passed | qualification-kit-ready / external-hold | E4-H recorder, fault-lab recorder, package assembler, supporting-report chain validator, audits and decision boundary | 2026-08-06 | independent human sign-off and real HDD/antivirus/power-loss evidence remain external |

## Iteration 59 closure

- Trash restore validates `world.json`, temporary and backup candidates before promotion.
- Release lifecycle evidence is written to `user://diagnostics/release-lifecycle-report.json` and never to `world.json`.
- One campaign combines hostile death/reward/drop, Chunk hot return, pane/fence adjacency and structural cleanup.

## Iteration 60 closure

- One machine-readable contract distinguishes fixtures, hosted references and target-hardware evidence.
- E4-H, minimum/recommended hardware, strict soak and fault-lab evidence are bound to one commit and one final EXE/PCK.
- The five-profile matrix can reuse the exact final package rather than export a different candidate per machine.
- Real soak shorter than 7,200 seconds and hosted-runner target claims fail closed.
- HDD, antivirus and power-loss records use prepare/complete phases so evidence survives a real restart.
- A retained fixture and end-to-end assembler regression prove that structurally valid reference evidence cannot close the gate.

## Iteration 61 closure

- One deterministic `candidate_id` binds commit, version, EXE, PCK and the governing repository contracts before external testing starts.
- Candidate identity excludes absolute paths, so the same bytes keep one identity after cross-machine transfer.
- A canonical directory bundles the final binary, candidate manifest, qualification package, seven summary records and eight supporting reports.
- The bundle rejects stale destinations, missing files, visible or hidden extra files, hash/length changes, reparse points and unsafe paths.
- The validator rechecks summary evidence against the Iteration 60 `artifact_manifest` and all supporting reports against their source-record hashes.
- The complete sorted 19-file payload derives one deterministic `bundle_id`.
- Retained tests deliberately modify summary evidence, supporting evidence, candidate identity, visible/hidden inventory and manifest paths; all six mutations fail closed.

## Commercial decision

Repository implementation, the external qualification kit and the release-candidate chain of custody are accepted. Commercial release remains **HOLD** until an actual package validates as `external_evidence_complete` after independent E4-H review, both real hardware tiers, the strict target-hardware soak and all three real fault experiments.
