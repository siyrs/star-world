# Architecture Audit Iteration 14

## Scope

Continue from multi-hostile danger batching.

Primary audit targets:

- Machine expansion readiness;
- Furnace lifecycle boundaries;
- Persistence ownership;
- UI and interaction ownership;
- Automation scalability.

## Findings

### P1 Machine lifecycle duplication risk

Current machines such as furnace contain progress, inventory slots, fuel, persistence and world position concerns together. Adding more machines by copying furnace logic will increase divergence.

Recommended direction:

```text
MachineRuntimeParticipant
        |
MachineStateStore
        |
MachineRecipePolicy
        |
MachineProgressPolicy
```

The first migration should preserve Furnace behavior and add contracts before adding more machines.

### P1 Automation needs bounded simulation

Future machines must not create unlimited timers or per-machine processing loops.

Rules:

- bounded offline progress;
- shared scheduler;
- deterministic save state;
- no machine-owned file writes;
- one world save transaction.

## Next implementation

Create Machine Base foundation without changing player-visible furnace behavior.

Acceptance:

- existing furnace tests remain green;
- save/load compatibility preserved;
- machine state diagnostics available;
- real desktop furnace journey passes;
- Windows release passes.
