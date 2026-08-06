# Release Integrity and Lifecycle Contract

## Scope

Iteration 59 closes the repository-automatable residuals left after the long-term scale qualification. It does not introduce another save format, another runtime scheduler, or a second release coordinator.

## Trash restore integrity

A trash manifest is not sufficient evidence that a world can be restored. `ProtectedSaveService` now validates `world.json`, `world.json.tmp`, and `world.json.bak` with the same authoritative payload contract used by normal recovery:

- `save_version` must be supported;
- `metadata.id` must equal the manifest world ID;
- candidate order remains primary, temporary, backup;
- a temporary or backup candidate is repaired inside the isolated trash directory before promotion;
- repair is re-read and must be the validated primary before the directory can enter `user://worlds`;
- repaired restores invalidate the derived catalog family so the first bounded listing rebuilds it from the authoritative world;
- unrecoverable or identity-mismatched slots remain purgeable but not restorable;
- an existing active world is never overwritten.

The player-visible failure reason is `world_payload_unrecoverable`; repair and integrity outcomes are exposed through bounded trash diagnostics.

## Release lifecycle report

Release builds mount `ReleaseLifecycleReportService` at the production composition root. The report path is independent from game saves:

`user://diagnostics/release-lifecycle-report.json`

The report uses engine monotonic uptime and records:

- production scene ready;
- first playable world;
- first successful save, including reason, bytes and elapsed duration;
- accepted quit source;
- quit preparation result;
- node, resource, orphan-node and static-memory snapshots before and after the authoritative quit path;
- exact resource deltas;
- bounded runtime-health and quit-coordinator projections.

It deliberately excludes inventory contents, transforms, block overrides and world serialization. Persistence uses `AtomicJsonStore`, so a report never mutates `world.json` and never leaves a successful `.tmp` file.

## Continuous cross-domain campaign

The permanent campaign runs eight cycles. Each cycle combines, under one SceneTree lifetime:

- three hostile death signals;
- one authoritative encounter reward and duplicate-completion rejection;
- one physical drop per death through the shared bounded pickup runtime;
- two recent-Chunk hot returns;
- glass-pane or fence cross-Chunk adjacency before and after neighbor mutation;
- one unsupported door and ladder cleanup through the event-driven structural queue.

The campaign finishes with 24 deaths, 24 expired drops, 8 unique formal rewards, 16 hot returns, 8 door cleanups, 8 ladder cleanups and zero residual runtime nodes.

## Release boundary

Repository automation can prove deterministic correctness, bounded resources and Windows hosted-runner behavior. It cannot impersonate independent E4-H experience review, minimum/recommended real target hardware or the strict 7,200-second final-package target-hardware soak. Commercial release remains **HOLD** until those external evidence packages exist.
