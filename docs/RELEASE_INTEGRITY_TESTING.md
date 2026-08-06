# Release Integrity Testing

## Permanent gate

`.github/workflows/release-integrity-iteration-59-tests.yml` runs on pull requests and matching master pushes. It calls the shared Godot 4.7 quality gate and preserves captured stdout/stderr artifacts for 21 days.

## Primary fault-injection test

`trash_restore_integrity_regression.gd` uses an isolated `user://` directory and proves:

1. corrupted primary plus valid backup recovers after a service restart;
2. corrupted primary and backup plus valid temporary recovers after restart;
3. valid JSON with a different `metadata.id` is rejected;
4. all-corrupt candidates fail closed;
5. damaged slots never enter the active world directory;
6. damaged slots remain explicitly purgeable;
7. derived catalog state is rebuilt only after an authoritative repair.

## Production lifecycle test

`release_lifecycle_report_regression.gd` instantiates `scenes/game/game.tscn`, reaches a real playable world, performs a real manual save, uses the production application-quit coordinator and verifies the atomic report. A separate `world.json` sentinel proves reporting cannot mutate game state.

## Continuous campaign

`release_integrity_continuous_campaign_regression.gd` keeps reward, pickup, cached Chunk and structural runtimes alive across eight cycles. It verifies exact uniqueness and cleanup rather than running four unrelated snapshots.

## Adjacent regressions

The gate re-runs graceful quit, trash management, encounter economy, shared pickup runtime, connected block shapes, recent Chunk cache, structural batching and the 3,600-second mixed-combat fixture.

## Evidence interpretation

Hosted CI evidence closes repository-automatable contracts only. It does not close E4-H, real minimum/recommended target-hardware qualification or the 7,200-second final-package target-hardware soak.
