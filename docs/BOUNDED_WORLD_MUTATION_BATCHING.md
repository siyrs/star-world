# Bounded World Mutation Batching

## Purpose

A single `VoxelChunk` contains `16×64×16 = 16,384` cells. The original `VoxelWorld.set_block()` path rebuilt the complete visual and collision mesh immediately after every changed cell. That is correct for one player placement, but it scales poorly when one domain updates many cells in the same operation:

```text
1,000 changed cells in 6 loaded chunks
old path: up to 1,000 complete chunk rebuilds
batch path: at most one rebuild per dirty loaded chunk
```

The batching contract reduces repeated mesh work without changing the sparse world save format, block IDs, event delivery, or the immediate behavior of ordinary one-cell player interactions.

## Production composition

`GameScene` now composes:

```text
BatchedStarWorldGame
└─ BatchedVoxelWorld
   └─ VoxelWorld compatibility contract
```

`BatchedVoxelWorld` inherits the existing world implementation and overrides only the rebuild boundary used by `set_block()`. Existing APIs such as `start_world`, `set_block`, `remove_block`, `get_block`, streaming, sparse serialization, and chunk loading remain available.

## Immediate single-edit semantics

When no batch is open:

```text
set_block
→ update sparse override and loaded chunk cells
→ collect affected current/boundary chunks
→ rebuild immediately
→ emit existing block signals
```

This preserves current placement, harvest, door, ladder, crop, collision, and ray-target behavior. Batching is explicit; it is not an asynchronous hidden queue.

## Explicit rebuild scope

Callers that own a bounded multi-cell operation can use:

```gdscript
world.begin_chunk_rebuild_batch("operation_name")
for change in changes:
    world.set_block(change.position, change.block_id)
world.end_chunk_rebuild_batch(true)
```

Scopes may nest. Only completion of the outermost scope flushes pending work. The world stores unique dirty `Vector2i` chunk coordinates, so repeated requests for the same chunk are coalesced.

Hard limits:

| Contract | Limit |
|---|---:|
| Nested rebuild batch depth | 8 |
| Dirty chunks tracked before a safety flush | 256 |
| `apply_block_mutations` entries | 4,096 |
| Additional Timer / per-frame scheduler | 0 |
| Persisted batching fields | 0 |

If the dirty-chunk safety capacity is reached, the current set is flushed before accepting more coordinates. Correctness is preserved; only coalescing efficiency is reduced for pathological operations.

## Bounded bulk API

`apply_block_mutations(changes, reason)` accepts entries shaped as:

```gdscript
{
    "position": Vector3i(x, y, z),
    "block_id": "stone_bricks",
}
```

The API:

- processes at most 4,096 entries;
- validates positions and registered block IDs;
- calls the authoritative `set_block()` path for every accepted entry;
- keeps all existing `block_changed`, `block_placed`, and `block_broken` signals;
- reports requested, accepted, changed, unchanged, rejected, and truncated counts;
- batches only rebuild work and does **not** claim transaction atomicity.

Atomic multi-cell gameplay structures such as doors continue to own their rollback rules. This API is for bounded world mutation and rebuild coalescing, not inventory or structure atomicity.

## Building chunks

A changed coordinate may belong to a chunk that is still generating or meshing. The flush path checks both:

```text
loaded chunks
+
building chunks
```

If a building chunk is dirty, its mesh is rebuilt from the latest block array before it is finalized. This prevents a mutation that occurs behind the current mesh cursor from producing a stale final mesh.

## Diagnostics

`get_chunk_rebuild_stats()` reports:

```text
batch_depth
batch_active
pending_chunks
request_count
execution_count
coalesced_count
flush_count
forced_capacity_flush_count
max_dirty_chunks
last_flush_usec
last_flush_chunk_count
last_reason
```

The same dictionary is included under the existing `get_streaming_stats().rebuild` path. Runtime telemetry therefore gains rebuild evidence without a second diagnostics service.

A useful efficiency measure is:

```text
coalescing ratio = 1 - execution_count / request_count
```

The real desktop scale acceptance records raw counts rather than enforcing a machine-specific throughput number.

## Persistence boundary

The world continues to save only:

```text
world.version
profile_id
seed
world_id
block_overrides
loaded_chunks
```

The following remain process-local:

```text
open batch depth
dirty chunk set
request/execution/coalesced counters
flush timing
last operation reason
benchmark report
```

`clear_world()` resets all pending rebuild state before inherited chunk disposal. A new or reloaded world begins with zero requests and no pending chunks.

## Scale acceptance

The permanent desktop acceptance uses production `GameScene`, `BatchedVoxelWorld`, `VoxelChunk`, rendering, collision, `SaveService`, and full menu reload. It applies more than 3,000 requested mutations containing:

- glass panes;
- oak fences;
- two-cell doors;
- all four ladder orientations;
- stone-brick floors and supports.

The test verifies:

1. at least 1,500 real cells change;
2. actual rebuilds do not exceed unique dirty chunks;
3. no pending work remains after the batch;
4. the operation completes within a broad 30-second desktop budget;
5. the sparse save stays below 2 MiB;
6. save and JSON load stay below 10 seconds each;
7. full return-to-menu reload becomes playable within 30 seconds;
8. representative blocks restore exactly once;
9. batching state does not enter the save;
10. a 1024×576 visualization and JSON benchmark report are uploaded.

The timing limits are regression guards, not hardware targets. The report preserves the actual measured values for later trend comparison.
