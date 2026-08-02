> Completion rule: this checklist is governed by the commercial release manual recorded in `proposal.md`. Checked items are completed current-cycle evidence only; the proposal and release remain incomplete while any release-gate item below is open.

## 1. Release baseline and durable records

- [x] 1.1 Protect the clean starting point and create `codex/commercial-release-gameplay-polish` without overwriting user work.
- [x] 1.2 Create and maintain the QA session state, map coverage matrix, issue register, performance baseline, regression results, and final-report placeholders.
- [x] 1.3 Discover the Godot 4.7 Windows runtime, main scene, export target, user-data location, log location, formal profile list, and existing QA/automation surface.
- [x] 1.4 Establish that the five formal maps are data-driven profiles and record that the product has no implemented traditional quest/map-ending completion condition.
- [x] 1.5 Capture this manual as the authoritative proposal completion baseline and preserve the distinction between designed completion and acceptance journeys.
- [x] 1.6 Fresh-export the current source under PowerShell 7 into an isolated directory and record EXE/PCK hashes, lifecycle, screenshots, and runtime logs.
- [x] 1.7 Correct the current PCK hash typo in session state and reconcile all current-cycle evidence paths after each fresh export.

## 2. Desktop acceptance and UI accessibility

- [x] 2.1 Reproduce the desktop runner evidence-contract failure and add the requested primary screenshot alongside the ten named captures and JSON report.
- [x] 2.2 Independently QA-retest the runner contract: 32 interaction checks, ten captures, exact output path, logs, and user-world manifest must pass.
- [x] 2.3 Rework map/settings geometry and obtain independent 1280x720 and 1024x576 non-overlap evidence.
- [x] 2.4 Repair enabled Button, SecondaryButton, PrimaryButton, MenuPrimaryButton, CardButton, SelectedCardButton, GhostButton, and DangerButton normal/hover/pressed/focus contrast to at least 4.5:1.
- [x] 2.5 Add parameterized effective-contrast regression coverage for every enabled variation/state and explicit disabled-state discernibility checks.
- [ ] 2.6 Have the same independent QA rerun the full UI matrix, real pointer hover/pressed/focus screenshots, 64-check design suite, 1280x720 desktop journey, and 1024x576 map/settings flows.

## 3. Safe spawn, collision, and recovery

- [x] 3.1 Reproduce the first-frame tree/canopy spawn defect and identify the first-fit single-column spawn logic and resolver height mismatch.
- [x] 3.2 Finish deterministic, data-driven, hard-safe spawn assessment with unconditional work budget, staged cheap gates, explicit scoring, and no terrain-seed mutation.
- [x] 3.3 Fix focused spawn-test filter parsing and script-error fast exit so profile/seed diagnostics cannot silently become a full matrix run.
- [x] 3.4 Close the focused `star_continent/24681357` regression with valid parsed filters, bounded wall time, scanned/evaluated/termination metrics, hard-safe result, and no ObjectDB/resource leaks.
- [x] 3.5 Add the synthetic canopy-obstruction fixture, preserve valid existing-save positions, and verify resolver/respawn height behavior.
- [x] 3.6 Run five profiles × six fixed seeds with p50/p95/max assessment cost, adjacent terrain checks, and three clean leak-free exits.
- [x] 3.7 Build and run systematic profile collision, seam, steep-slope, entrapment, fall-through-world, and safe-recovery checks without using artificial completion/state changes.

## 4. Release tooling, resources, and version identity

- [x] 4.1 Make the documented Windows PowerShell 5.1 release-smoke path compatible or fail before export with a precise PowerShell 7 prerequisite and safe replacement command.
- [x] 4.2 Load the pixel font from exported resources and prove fresh release stderr has no font-fallback warning.
- [x] 4.3 Exclude build/QA evidence resources from the Windows PCK and prove runtime assets and smoke remain healthy.
- [x] 4.4 Reconcile project, Windows export, and user-visible version metadata with the intended release version.
- [x] 4.5 Remove only the precisely identified editor-generated `.uid`/`.import` metadata after active development has stopped; verify no user source, QA document, or build evidence is removed.

## 5. Performance and observability

- [x] 5.1 Replace invalid release `0.0 MiB` memory interpretation with explicit availability semantics and launched-PID Working Set/Private Bytes sampling.
- [x] 5.2 Split static streaming convergence from movement pressure and fail health when pending/building chunks do not converge within the bounded rule.
- [ ] 5.3 Capture like-for-like baseline and optimized performance across menu, each profile spawn/complex area, water/high/underground areas, rapid movement/turning, repeated loads, and settings changes.
- [ ] 5.4 Record average FPS, 1% low, frame-time percentiles, load time, CPU/GPU/VRAM availability, memory trend, object/allocator evidence, and valid unavailable-counter boundaries.
- [ ] 5.5 Complete the fresh-EXE long-run soak covering all profiles, saves/loads/menu returns, with no crash, fatal log, sustained degradation, or unexplained memory growth.

## 6. Five-profile normal-entry release journeys

- [x] 6.1 Add isolated fixed-seed normal menu-entry journey infrastructure that records screenshots, logs, world state, QA-world cleanup, and pre/post user-data manifests.
- [ ] 6.2 Complete the Star Continent journey: forest/plain/river, water entry/exit, building/agriculture, night encounter, exploration milestone, persistence, death/recovery, and repeat entry.
- [ ] 6.3 Complete the Desert Ruins journey: normal entry, ruins/columns, surface-to-underground ore route, seam/boundary exploration, persistence, death/recovery, and repeat entry.
- [ ] 6.4 Complete the Frozen Wastes journey: normal entry, high/low terrain, ice-underwater entry/exit/recovery, hunger behavior, persistence, death/recovery, and repeat entry.
- [ ] 6.5 Complete the Sky Islands journey: normal entry, multiple islands, bridge/build route, edge fall/Y-limit recovery, high-area collision, persistence, death/recovery, and repeat entry.
- [ ] 6.6 Complete the Abyss journey: normal entry, caves/crystals, hostile encounters, lava behavior and death/recovery, underground seams, persistence, and repeat entry.
- [ ] 6.7 Complete the finite content matrix: tutorial beyond first screen, menus/settings, items/tools/weapons, recipes/machines, building/interactions, creatures/encounters, exploration rewards, and all applicable save states.

## 7. State, water, and stability regression

- [ ] 7.1 Verify new, manual, automatic, overwrite, and multi-world saves; exit/read, malformed `.tmp`/`.bak` recovery, old-schema migration, and user-data safety using isolated QA data.
- [ ] 7.2 Verify water and underwater lifecycle for every generated water profile: shore/deep/high entry, swim/up/down/exit, camera/audio/visual state, interaction, save/load, death/recovery, and rapid re-entry.
- [ ] 7.3 Establish intended lava behavior from runtime evidence and repair any generic-water-state, damage, recovery, or persistence defect before Abyss acceptance.
- [ ] 7.4 Run extreme-input, pause/focus, full-screen/window/UI-scale, rapid interaction, and long-session stability cases; triage all impactful warnings/errors rather than suppressing them.

## 8. Final quality gate and delivery

- [ ] 8.1 Run the full static/Godot regression suite and every affected focused suite from fresh source; triage and close all P0/P1 issues or document actual external blockers.
- [ ] 8.2 Fresh-export the final commit and independently validate EXE identity, package contents, lifecycle, UI font, logs, performance evidence, and all critical regressions.
- [x] 8.3 Update every profile row and finite-content row in `qa/map-coverage-matrix.md` with actual entry, exploration, acceptance-journey, water/boundary, save, death/recovery, task/content, issue, and regression evidence.
- [x] 8.4 Produce the complete final release report required by the manual: execution summary, map coverage, fix list, before/after performance, automation, code/commit list, and evidence-backed residual risks.
- [ ] 8.5 Create small, scoped commits on the independent branch, verify the final worktree excludes temporary/generated artifacts, and record the commit list without pushing or publishing.
- [ ] 8.6 Conduct the manual-governed final review: all 20 release acceptance conditions are evidenced, all designed completion conditions are exercised or accurately marked absent, and the recommendation is explicitly release/no-release.
