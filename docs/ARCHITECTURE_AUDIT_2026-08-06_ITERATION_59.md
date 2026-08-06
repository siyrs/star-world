# Architecture Audit · Iteration 59 · 2026-08-06

## Finding 1: trash manifest validity was mistaken for world validity

The previous restore path validated only `trash.json` and renamed the directory directly. A syntactically valid manifest could therefore promote a corrupted or identity-mismatched world. The correction reuses `AtomicJsonStore` candidate ordering and `SaveService._is_valid_world_payload`, repairs inside the isolated directory, verifies the repaired primary, then promotes.

## Finding 2: release timing existed only as fragmented evidence

Startup, save and quit paths already had authoritative production boundaries, but no single Release report tied them together. The correction observes existing signals and coordinators rather than owning game state. The report is an atomic diagnostic projection under `user://diagnostics`.

## Finding 3: long tests were adjacent rather than one campaign

Hostile economy, pickups, cached Chunk return, connected shapes and structural cleanup were independently covered. The new campaign keeps all corresponding production services alive under one SceneTree and checks exact totals and final zero residue.

## Finding 4: the task status board contradicted the branch

The July board still claimed zero completed map journeys and unresolved early defects after dozens of merged, green iterations. It is replaced with an evidence-graded reconciliation that keeps external release blockers explicit.

## Non-expansion decision

Iteration 59 adds no new gameplay system, save schema, timer, thread or state owner. It closes integrity and evidence gaps around existing authorities. Independent E4-H, real target hardware and the 7,200-second soak remain external HOLD gates.
