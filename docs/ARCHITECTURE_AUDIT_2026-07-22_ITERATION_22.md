# Architecture Audit · 2026-07-22 · Iteration 22

## Baseline

This iteration starts from:

```text
master@0ad91ee2c5027c97732e5f14ded5fa4bd8e8fa9e
feat: add directional wall ladders and real climbing (#52)
```

The project now has shared partial geometry for panes, fences, doors, stairs, slabs, crops and directional ladders; real placement and climbing; six lifecycle participants; bounded machine automation; strict save migration; and Windows Release evidence.

The next roadmap item is no longer another isolated block type. It is evidence that the existing world architecture remains usable when thousands of real building mutations, cross-Chunk shapes, save writes and reloads happen together.

## Finding 1 · every `set_block` rebuilt a complete Chunk immediately

A production `VoxelChunk` contains:

```text
16×64×16 = 16,384 cells
```

The original path was:

```text
VoxelWorld.set_block
→ update sparse override
→ update loaded chunk cell
→ _rebuild_affected_chunks
→ VoxelChunk.rebuild_mesh
→ scan all 16,384 cells
→ rebuild visual mesh
→ rebuild collision mesh
```

This is appropriate for a single player placement because the next frame must show correct visuals and collision. It is not appropriate for a bounded operation that changes hundreds or thousands of cells in the same loaded Chunk.

For example, 512 crop stage changes or a 1,000-block structure import could execute hundreds of complete scans of the same Chunk even though only the final mesh is observable after the operation finishes.

## Finding 2 · boundary mutations multiplied rebuild work

The existing boundary correctness contract rebuilds both the current Chunk and the adjacent Chunk when a changed cell is at local X/Z 0 or 15. This is necessary for connected panes, fences, transparent face suppression and other neighbour-derived geometry.

Without deduplication, ten changes along one boundary can request:

```text
10 current-Chunk rebuilds
+
10 neighbour-Chunk rebuilds
=
20 complete rebuilds
```

The correct final result only requires one rebuild of each dirty loaded Chunk.

## Finding 3 · high-volume callers had no explicit mutation scope

The world API exposed only one-cell `set_block`. Callers that intentionally owned a bounded multi-cell operation had no way to say:

```text
these changes belong to one observable operation;
keep signals and sparse state per cell,
but publish visual/collision work once at the end.
```

Adding a hidden global delay would weaken immediate player feedback and make tests timing-dependent. A batch therefore needs to be explicit, nestable and synchronously flushed by the outer owner.

## Finding 4 · a deferred queue could leave stale building chunks

Chunk streaming may be generating or meshing a Chunk while another domain changes one of its cells. A batching implementation that only flushes `chunks` and ignores `_building_chunks` can miss a mutation that occurred behind the current mesh cursor.

The final Chunk could then be published with stale visual or collision data even though `get_block()` and the sparse override already contain the new value.

The flush contract must inspect both loaded and currently building chunks before completion.

## Finding 5 · batching must not pretend to provide transaction atomicity

World rebuild coalescing is not the same as domain rollback.

Examples:

- a two-cell door still owns paired placement/removal rollback;
- inventory consumption still uses inventory transactions;
- crop harvest still owns world/inventory competition rollback;
- machine transfers remain atomic through the capability contract.

The new bulk API may validate and bound entries, but it must continue to call authoritative `set_block()` and emit existing block signals. It does not roll back earlier changes when a later entry is invalid.

## Finding 6 · rebuild cost was invisible in existing diagnostics

Runtime telemetry already reported:

```text
loaded chunks
building chunks
pending chunks
streaming work time
```

It did not report the cost caused by world mutations:

```text
raw rebuild requests
actual rebuild executions
coalesced requests
pending dirty chunks
flush count and duration
```

Without these numbers, a scale test could only assert elapsed time on one runner. The more useful evidence is whether requested work collapses to the number of unique dirty chunks.

## Finding 7 · save size and first-playable reload lacked a real scale baseline

Existing save tests proved correctness for individual systems, but there was no production fixture combining thousands of real sparse block changes across:

- glass panes;
- fences;
- two-cell doors;
- all ladder orientations;
- multiple Chunk boundaries.

There was also no permanent report for:

```text
save bytes
save duration
JSON load duration
return-to-menu → first playable reload duration
```

This iteration adds broad regression thresholds plus machine-readable measured values, rather than claiming a universal hardware target.

## Decision · preserve immediate edits, add explicit bounded rebuild batches

Production composition becomes:

```text
BatchedStarWorldGame
└─ BatchedVoxelWorld
   └─ VoxelWorld public compatibility contract
```

`BatchedVoxelWorld` overrides only the rebuild boundary. When no batch is open, a normal one-cell edit still flushes immediately.

Explicit callers may open a scope:

```gdscript
world.begin_chunk_rebuild_batch("operation")
# authoritative set_block calls
world.end_chunk_rebuild_batch(true)
```

The outermost completion synchronously rebuilds each unique dirty loaded/building Chunk once.

## Hard budgets

| Contract | Limit |
|---|---:|
| Nested batch depth | 8 |
| Dirty Chunk coordinates before safety flush | 256 |
| `apply_block_mutations` entries | 4,096 |
| Additional Timer | 0 |
| Additional per-frame scheduler | 0 |
| Persisted batching fields | 0 |

A capacity flush preserves correctness if a pathological operation touches more than 256 dirty chunks. It only reduces coalescing efficiency for that operation.

## Production diagnostics

The existing `get_streaming_stats()` contract now includes:

```text
rebuild.request_count
rebuild.execution_count
rebuild.coalesced_count
rebuild.pending_chunks
rebuild.flush_count
rebuild.last_flush_usec
rebuild.max_dirty_chunks
```

The state is reset by `clear_world()` and never enters `world.json`.

## Permanent acceptance

### Static contract

`tests/developer_b/validate_world_mutation_batch.ps1` verifies:

- production composition;
- immediate single-edit semantics;
- nested and bounded batch ports;
- 8 / 256 / 4,096 hard limits;
- deterministic flush order;
- loaded and building Chunk coverage;
- no Timer, second scheduler or parallel persistence;
- existing streaming telemetry integration;
- permanent domain and desktop CI entry points.

### Domain regression

`tests/qa/world_mutation_batch_regression.gd` verifies:

- one edit still performs one immediate rebuild;
- 128 edits in one Chunk perform one rebuild;
- ten boundary edits collapse twenty requests to two rebuilds;
- nested scopes flush only at the outer boundary;
- the 4,096-entry cap and truncation result;
- streaming diagnostics;
- clear/reset and persistence boundaries.

### Real desktop and visualization

`tests/qa/world_scale_desktop_acceptance.gd` uses production `GameScene`, `BatchedVoxelWorld`, `VoxelChunk`, rendering, `SaveService` and menu reload. It applies more than 3,000 requested mutations, writes a real sparse world save, loads it, returns to menu and reaches a playable reloaded world.

Evidence includes:

```text
1024×576 mixed-shape screenshot
JSON benchmark report
stdout/stderr logs
```

The screenshot includes an in-game metric panel with raw mutation and rebuild counts. The JSON report preserves timings and save size for trend comparison.

## Compatibility

This iteration does not change:

- any block numeric ID;
- `world.version`;
- `world.block_overrides`;
- placement, harvest, door, ladder or crop signals;
- the `VoxelWorld` public gameplay API;
- immediate behaviour of ordinary single-cell edits;
- chunk streaming scheduler ownership.

## Next evidence-driven steps

After this iteration:

1. add repeated cross-Chunk unload/reload stress around dense connected structures;
2. compare multi-machine and large-farm scale against the same report format;
3. add longer soak with mutation bursts and creature/drop pressure;
4. extract reusable GitHub Actions workflow components only after the scale workflow stabilizes;
5. consider incremental mesh sections or caches only if real reports show unique-Chunk rebuild cost remains dominant after request coalescing.
