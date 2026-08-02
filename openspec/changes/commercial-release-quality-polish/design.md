## Context

The Godot 4.7 Windows project has five procedural world profiles, no traditional quest or map-completion system, and a substantial existing QA suite. Current-cycle evidence proves a fresh PowerShell 7 export and limited production-scene input flow, but also documents release-runner compatibility, font packaging, package pollution, UI state contrast, spawn quality, streaming convergence, and telemetry gaps. Existing user worlds are protected: all destructive or malformed-save tests must use isolated QA data.

The user-provided commercial release manual at `C:\Users\sirius\.codex\attachments\24964602-687b-47e6-9db7-e68b02bb5711\pasted-text.txt` is the authoritative acceptance baseline. The OpenSpec artifacts translate that manual into traceable, testable work; they do not reduce or replace its gates.

## Goals / Non-Goals

**Goals:**

- Make current release evidence repeatable, scoped, and impossible to misread as full-game acceptance.
- Repair P1 UI and spawn defects with tests that cover the actual failing states and seeds.
- Build a data-driven five-profile journey harness that uses normal menu entry before any focused diagnostics.
- Collect valid release-mode performance, loading, memory, and long-run evidence.

**Non-Goals:**

- Add a quest, ending, portal, underwater-art, or multiplayer system that the product does not currently design.
- Change procedural terrain seed output merely to make a test pass.
- Modify, delete, or migrate real user worlds during QA.
- Publish, tag, push, or upload a release.

## Decisions

### Treat a profile journey as the acceptance unit

Each profile is an infinite procedural world rather than a finite map. Acceptance therefore combines normal menu creation, local player traversal, profile-specific feature probes, save/load/death recovery, and finite content registries; it does not claim an artificial “map completion.” This preserves the game’s actual design while giving release QA a bounded contract.

### Keep two evidence layers separate

Fresh exported-EXE smoke proves export identity, resource packaging, process lifecycle, and release-mode metrics. Production-scene desktop InputEvent tests prove menu and gameplay interaction. A release gate requiring both SHALL cite both outputs; neither layer substitutes for the other. The external Windows control capture refusal is recorded as a tooling boundary, not a pass or a game failure.

### Use data-driven, bounded spawn assessment

Spawn selection uses profile data and deterministic scoring over hard-safe candidate cells. A candidate must first satisfy support/body clearance, then be evaluated for local movement, forward visibility, obstacle distance, and terrain safety. Work is bounded independently of score, with cheap rejection before expensive evaluation and metrics for scanned/evaluated candidates and elapsed time. Valid loaded-save positions remain untouched.

### Fix UI at token/state level

Interactive UI contrast is a property of effective foreground/background combinations, not a single base color. Button variations and normal/hover/pressed/focus states are therefore tested at the theme factory/token layer and checked again through real pointer screenshots. Disabled states are documented separately rather than treated as normal interactive text.

### Measure release performance from valid sources

The game-owned diagnostic report retains engine information but marks unavailable release memory sources as unavailable. A wrapper bound to the launched EXE PID records Windows Working Set and Private Bytes. Streaming health first waits for explicit static convergence, then runs movement pressure, so a moving short smoke cannot incorrectly declare a backlog healthy.

## Risks / Trade-offs

- [Spawn scoring increases generation work] → bounded budget, staged gates, per-profile timing distribution, and fixed-seed regressions are required before broad rollout.
- [Stricter visual contrast changes pixel-art feel] → preserve hierarchy through value/chroma decisions and verify screenshots at all target desktop viewports.
- [Long running tests consume local resources] → every test has a timeout, process-tree cleanup, evidence directory, and a short focused mode before full matrices.
- [QA tests can affect saves] → all QA worlds use unique names and isolated APPDATA where applicable; user-world manifest/hash checks run before and after.
- [Build evidence can pollute PCK] → export contracts reject `build/` evidence resources and inspect export output/PCK entries.

## Migration Plan

1. Retain existing user saves and schema; new spawn logic is used only for new-world creation.
2. Land test/observability changes with their focused regressions before production behavior changes where possible.
3. Re-export to a fresh isolated directory after each release-tool/resource change.
4. If a release behavior regression appears, revert the smallest dedicated commit; keep the evidence and regression test where it accurately describes the failure.

## Open Questions

- Whether the intended product design gives lava damage and non-swimmable behavior remains unresolved and must be answered by actual deep-world QA before release acceptance.
- GPU/VRAM counter availability depends on the local driver/tooling; unavailable counters must be reported as unavailable with the collection attempt, not fabricated.
- Visible version target remains to be reconciled with the previously published v1.2.0 and current 1.1.0 metadata.
