# External Qualification Evidence Kit

Iteration 60 provides the repository-owned tooling required to collect, bind and validate the remaining commercial-release evidence without allowing hosted CI or fixtures to impersonate real external qualification.

## Scope

The kit covers four external evidence classes:

1. independent E4-H final-build experiential review;
2. minimum and recommended real target-hardware qualification;
3. a strict 7,200-second final-package target-hardware soak;
4. real HDD, antivirus-interference and power-loss recovery experiments.

The repository ships the schema, recorders, collectors, package assembler and anti-forgery gates. It does **not** fabricate the physical run, reviewer identity, hardware identity or interruption event.

## Evidence states

`ExternalQualificationContract` returns one of three valid states:

- `fixture_contract_complete`: a retained fixture proves the schema and validator work;
- `reference_only`: structurally valid hosted/reference evidence that cannot close release gates;
- `external_evidence_complete`: a complete target-hardware package that passes every real-evidence rule.

Invalid packages return `invalid`. Only `external_evidence_complete` sets `release_gate_passed=true`.

## Schema v2 immutable binding

Every accepted package is bound to:

- one 40-character Git commit SHA;
- one final `StarWorld.exe` SHA-256;
- one final `StarWorld.pck` SHA-256;
- one version string.

Schema v2 enforces this twice:

1. the assembler checks every source record before creating the package;
2. both the GDScript and standalone PowerShell validators re-check every child record after the package exists.

The E4-H review, both hardware tiers, strict soak and all three fault records must reference the same build. Child `evidence_source`, `reference_only` and fault-operator identity must also match the package. Editing an assembled JSON file to mix evidence from another commit, EXE, PCK, hosted run or operator is rejected.

Hardware and soak child records use qualification schema 2 and bind the exact SHA-256 plus schema from `data/release_qualification.json`. The validators do not trust a recorded `result=pass`: PowerShell and GDScript independently recompute every performance assertion, soak aggregate and lifecycle semantic from the packaged fields. A loosened threshold, stale policy hash, forged PASS flag, or `scene_exit_without_prepared_quit` is invalid.

## 1. Independent E4-H review

Run on the final candidate after the independent reviewer completes every checklist item:

```powershell
pwsh -NoProfile -File tests/ci/new_independent_experience_review.ps1 `
  -ReviewerId reviewer-identity `
  -ImplementerId implementer-identity `
  -CommitSha <40-character-sha> `
  -ExecutableSha256 <StarWorld.exe-sha256> `
  -PckSha256 <StarWorld.pck-sha256> `
  -OutputPath evidence/e4-h-review.json `
  -FreshInstall -NewWorld -SaveReload -FiveProfiles `
  -InputAndUi -QuitAndRestart -IndependentAttestation
```

The script rejects self-review, an incomplete checklist and unresolved blockers. The identity fields are operator attestations; the repository cannot cryptographically prove a person's identity.

## 2. Minimum and recommended hardware

Use the exact already-exported final EXE/PCK on each real machine:

```powershell
pwsh -NoProfile -File tests/ci/run_external_hardware_qualification.ps1 `
  -ProjectRoot . `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -Tier minimum `
  -OperatorId operator-minimum `
  -OperatorAttested `
  -OutputDirectory build/external-qualification/minimum
```

Repeat with `-Tier recommended` on the recommended machine.

The collector:

- refuses real qualification on GitHub Actions;
- records CPU, GPU, RAM, OS and storage information;
- hashes a normalized machine identity instead of storing a device serial number;
- runs the existing final-package five-profile route matrix;
- reuses the supplied exact EXE/PCK for all five profiles;
- requires real movement, at least two Chunks, visual acceptance and zero post-spawn transport;
- evaluates average FPS, 1% low FPS, frame-time p95 and p99, 30 FPS budget-miss percentage, profile load time and Working Set p95 for each profile (35 assertions per tier);
- records the repository policy schema/hash and rejects threshold drift;
- records the final package hashes in each tier result.

`-ReferenceOnly` is available for mechanism testing, but that result can never close the release gate.

The minimum and recommended records must come from machines that actually represent those physical tiers. One overpowered machine cannot be relabeled as the minimum tier merely because it exceeds the minimum performance floor.

## 3. Strict final-package soak

First, run one normal-exit preflight against the same already-exported package. `-SkipExport` is mandatory for qualification reuse; this step must not create a new EXE/PCK:

```powershell
pwsh -NoProfile -File tests/release/run_windows_export_smoke.ps1 `
  -SkipExport `
  -ExecutablePath C:\candidate\StarWorld.exe `
  -ProfileId star_continent `
  -RouteProbe `
  -RunnerTimeoutMilliseconds 1200000 `
  -OutputDirectory build/external-qualification/lifecycle-preflight
```

The preflight writes `release-lifecycle-report.json` after the release-smoke runner calls the production `request_application_quit("release_smoke")` coordinator. The driver parses the report and requires a successful save, matching world identity, monotonic timings, `prepared=true`, `termination_reason=prepared_quit`, and zero service/game quit failures.

Then run the exact same final package on target hardware:

```powershell
pwsh -NoProfile -File tests/ci/run_strict_target_hardware_soak.ps1 `
  -ProjectRoot . `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -LifecycleReportPath build\external-qualification\lifecycle-preflight\release-lifecycle-report.json `
  -OperatorId soak-operator `
  -OperatorAttested `
  -SoakSeconds 7200 `
  -OutputDirectory build/external-qualification/strict-soak
```

The harness repeatedly starts the same final package through the production release-smoke route, rotates across all five formal profiles and accumulates real wall-clock time with `Stopwatch`. Policy currently requires at least 7,200 seconds and 10 completed routes. Every cycle must produce its own parsed authoritative lifecycle report, exit cleanly, retain real player traversal and avoid direct transform writes or post-spawn transport. Aggregate fatal diagnostics must be zero and first-to-last Working Set p95 growth must remain at or below the policy limit (currently 25%). A progress journal, per-cycle reports and SHA-256 manifest are retained.

The script refuses a real run shorter than 7,200 seconds and refuses real mode on hosted GitHub runners. A short `-ReferenceOnly` run is suitable only for validating the harness.

## 4. HDD, antivirus and power-loss laboratory records

Each fault scenario is two phase so the pre-interruption world and build digests survive the real restart. Both phases must receive the same final EXE/PCK.

Prepare:

```powershell
pwsh -NoProfile -File tests/ci/new_external_fault_lab_record.ps1 `
  -Scenario power_loss -Phase prepare `
  -WorldJsonPath <world.json> `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -OperatorId fault-operator `
  -RecordPath evidence/fault-power-loss.json `
  -AttestedReal
```

After the real interruption, restart and recovery verification:

```powershell
pwsh -NoProfile -File tests/ci/new_external_fault_lab_record.ps1 `
  -Scenario power_loss -Phase complete `
  -WorldJsonPath <recovered-world.json> `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -RecoveryEvidencePath <recovery-log-or-report> `
  -OperatorId fault-operator `
  -RecordPath evidence/fault-power-loss.json `
  -AttestedReal `
  -InterruptionObserved -RecoveryVerified -WorldIntegrityVerified
```

Repeat for `hdd` and `antivirus`. The recorder preserves the world ID, before/after world hashes and exact EXE/PCK hashes. Completion fails if a different package or operator is supplied.

## 5. Assemble and validate the package

```powershell
pwsh -NoProfile -File tests/ci/new_external_qualification_package.ps1 `
  -CommitSha <40-character-sha> `
  -Version v1.3.0 `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -ExperienceReviewPath evidence/e4-h-review.json `
  -MinimumHardwarePath evidence/hardware-minimum.json `
  -RecommendedHardwarePath evidence/hardware-recommended.json `
  -StrictSoakPath evidence/strict-soak.json `
  -HddFaultPath evidence/fault-hdd.json `
  -AntivirusFaultPath evidence/fault-antivirus.json `
  -PowerLossFaultPath evidence/fault-power-loss.json `
  -ReleaseOwnerId release-owner `
  -ReleaseOwnerApproved -AllArtifactsAttached `
  -OutputPath evidence/external-qualification-package.json
```

The assembler verifies all build/source/reference/operator bindings, qualification child schema 2 and `exact_final_package_reused=true` before writing schema v2. It hashes the supplied EXE/PCK again after assembly and invokes:

```powershell
pwsh -NoProfile -File tests/ci/validate_external_qualification_package.ps1 `
  -PackagePath evidence/external-qualification-package.json `
  -RequireReleaseGate
```

The standalone validator re-checks the complete package, including policy hash/schema, all 35 metrics per tier, duration, route count, five-profile coverage, fatal/transport/write counts, Working Set growth and authoritative lifecycle semantics. Successful assembly alone is not treated as proof.

## Permanent repository evidence

The workflow `.github/workflows/external-qualification-iteration-60-tests.yml` validates:

- strict Godot 4.7 import and GDScript/PowerShell contract parity;
- fixture and hosted-reference non-qualification;
- self-review, hosted-target and short-soak rejection;
- commit/EXE/PCK rebinding rejection after package assembly;
- policy loosening, performance PASS forgery, short route count, fatal diagnostic, excessive memory growth and dirty lifecycle rejection;
- child source/reference and fault-operator mismatch rejection;
- PowerShell parser correctness for all collectors;
- an end-to-end reference package assembly and deliberate tampering attempt;
- adjacent release lifecycle, release-smoke and profile journey contracts.

A green workflow proves that the qualification kit is ready. It does not prove that the physical external evidence has been collected.

## Commercial decision

Until an actual `external_evidence_complete` package is attached to the final candidate, commercial release remains **HOLD**.
