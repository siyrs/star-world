## Why

The current Windows Godot build can be freshly exported and started, but it is not commercially release-ready: only the Star Continent has partial current-cycle coverage, key release automation and runtime evidence are incomplete, and P1 regressions exist in interactive UI contrast and first-frame world spawning. The existing QA record is evidence-rich but spread across session notes, issue logs, and build artifacts, making it hard to resume and verify the remaining release gate.

## Authoritative Acceptance Baseline

This proposal SHALL be completed only against the user-provided commercial release manual at `C:\Users\sirius\.codex\attachments\24964602-687b-47e6-9db7-e68b02bb5711\pasted-text.txt`. It is the governing acceptance contract for this change and takes precedence over a green unit test, a short smoke run, or a partial map visit.

The contract requires an actual loop of build, launch, player operation, discovery, repair, rebuild, and regression; complete map/content discovery; normal-path coverage beyond the tutorial; systematic collision/water/state/performance/stability testing; durable QA records; a protected Git branch with small commits; and a final report. The release gate remains closed until all discovered formal maps have a completed acceptance journey, all designed completion conditions are either exercised or documented as absent in the product, all P0/P1 defects are closed or have actual external-blocker evidence, performance and long-run evidence exists, automated/repeatable regressions pass, the coverage matrix is complete, and the work is committed on the independent branch.

## What Changes

- Establish a data-driven, evidence-backed release-quality gate for all five production world profiles rather than treating a short smoke run or tutorial as whole-game acceptance.
- Make Windows release verification reproducible across the documented PowerShell entry point, with artifact identity, resource-packaging checks, actionable runtime health, and external process metrics.
- Require accessible visual states for every interactive UI variation and preserve the desktop screenshot/JSON evidence contract.
- Replace first-fit player spawning with deterministic, bounded, quality-scored safe-spawn selection and its regression coverage, without changing generated terrain or relocating valid existing saves.
- Add isolated normal-entry journeys for every profile, covering persistence, recovery, profile-specific hazards, content milestones, and release-oriented performance/soak evidence.
- Keep QA evidence and generated artifacts out of shipping packages, and align visible/project/Windows version metadata before release.

## Capabilities

### New Capabilities

- `release-verification`: Fresh Windows export verification that produces trustworthy identity, packaging, lifecycle, log, and process-metric evidence.
- `interactive-ui-accessibility`: Accessible, viewport-safe interactive UI states with durable screenshot and JSON acceptance evidence.
- `safe-world-spawn`: Deterministic bounded spawning that provides safe, navigable first-frame player positions across every world profile.
- `profile-release-journeys`: Normal-entry end-to-end journeys for all five procedural profiles, including persistence, recovery, hazards, and finite-content coverage.
- `runtime-performance-observability`: Release-mode performance and long-run observability with valid metrics and convergence-oriented health rules.
- `commercial-release-acceptance`: The manual-derived release gate, durable evidence records, and final delivery contract.

### Modified Capabilities

- None; this repository has no pre-existing OpenSpec capability specifications.

## Impact

- Affected runtime code includes world generation/spawn assessment, UI theme/token construction, diagnostics and streaming telemetry.
- Affected release/test tooling includes Windows export smoke, desktop acceptance runners, data-driven Godot QA scripts, report generation, and `export_presets.cfg` resource boundaries.
- Affected release metadata includes `project.godot`, Windows export version information, and user-visible version strings.
- No external service, account, or production deployment is introduced; all work remains on the local `codex/commercial-release-gameplay-polish` branch and must preserve existing user worlds.
