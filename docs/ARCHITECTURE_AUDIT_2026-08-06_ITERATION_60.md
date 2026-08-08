# Architecture Audit · 2026-08-06 · Iteration 60

## Scope reviewed

- `docs/PRODUCT_ROADMAP.md`
- Iteration 59 release integrity and lifecycle implementation
- release readiness and evidence workflows
- final Windows export journey matrix
- hosted reference soak
- commercial-release task status board

## Findings

### A-60-01 · External HOLD items existed only as prose

The roadmap correctly preserved independent review, real hardware, 7,200-second soak and real fault-lab evidence as external. However, there was no canonical machine-readable package joining those items. This allowed evidence to be complete in separate folders while remaining impossible to validate as one final-build decision.

**Resolution:** introduce one versioned qualification contract and strict package validator.

### A-60-02 · Hosted reference evidence could be misread as acceptance

Hosted CI already exercised Windows export, five profiles and a shorter soak mechanism. The documents stated the limitation, but no code-level gate prevented a future package from labelling hosted results as target hardware.

**Resolution:** evidence source, `reference_only`, `hosted_runner` and `fixture_mode` are jointly validated. Hosted or fixture evidence can never set `release_gate_passed=true`.

### A-60-03 · Hardware tiers needed immutable final-package identity

Running an export separately on minimum and recommended hardware could produce two different artifacts. Passing both would not prove that one final candidate was qualified.

**Resolution:** the existing five-profile matrix now supports exact prebuilt EXE/PCK reuse. Both hardware tier records, E4-H review, strict soak and the package assembler verify the same SHA-256 values.

### A-60-04 · Soak duration needed a truthful clock

A high frame count is not a time qualification because render and simulation rates vary by hardware. Sleeping for two hours would also prove nothing.

**Resolution:** the strict harness repeatedly executes the same final package through the production release-smoke route and uses a monotonic `Stopwatch` wall clock. Policy requires duration, at least 10 routes and all five profiles. Each cycle must pass through the production quit coordinator with a parsed `prepared_quit` lifecycle report; aggregate fatal diagnostics, post-spawn transport and direct transform writes must be zero, and Working Set growth must remain within policy.

### A-60-05 · Real interruption evidence must survive the interruption

A single-process script cannot truthfully perform and verify a real power loss. Antivirus and HDD interference also require an operator-controlled external condition.

**Resolution:** fault records are two phase. `prepare` writes world identity, pre-fault digest and exact EXE/PCK hashes; `complete` runs after restart and refuses a changed package, operator or world identity before recording recovery evidence.

### A-60-06 · Experiential independence was not enforceable in repository data

The repository cannot prove a human identity, but it can reject obvious self-review and incomplete review records.

**Resolution:** the E4-H recorder requires distinct reviewer/implementer identifiers, explicit independence attestation, six completed checks and zero blockers. Documentation states that identity fields remain human attestations rather than cryptographic identity proof.

### A-60-07 · Assembly-time checks alone did not protect stored JSON

The first implementation verified cross-artifact hashes only while assembling the package. A later manual edit could replace a child record while leaving the top-level build unchanged, and a standalone validator would have accepted the structurally complete JSON.

**Resolution:** schema v2 performs validation-time rebinding in both GDScript and PowerShell. Review commit/EXE/PCK, both hardware EXE/PCK pairs, soak EXE/PCK, all fault EXE/PCK pairs, child evidence class/reference flags and fault operator identity are rechecked every time. Hardware thresholds and strict-soak limits are additionally bound to the repository policy hash/schema and recomputed from packaged metrics/lifecycle fields. Regression tests assemble a valid package, mutate build, policy, metrics and lifecycle data, and require rejection.

## Architecture decision

The qualification domain is a diagnostics/evidence domain:

- it reads build artifacts and external evidence;
- it never owns or writes gameplay state;
- it does not alter `world.json`;
- it reuses release-smoke, route and lifecycle contracts;
- it emits deterministic JSON plus SHA-256 bindings;
- it validates the same schema in GDScript and PowerShell;
- it preserves a hard separation between repository mechanism validation and external acceptance.

## Test strategy

- GDScript regression validates valid states and all material tampering cases.
- PowerShell self-test independently implements and checks schema v2.
- Static audit parses all scripts and checks anti-forgery invariants.
- End-to-end fixture assembly binds synthetic artifacts, proves the result remains non-qualifying, mutates a child digest and proves standalone rejection.
- Adjacent lifecycle, release-smoke and profile journey regressions prevent contract drift.
- Real hardware, 7,200-second duration and physical fault injection are intentionally not simulated by CI.

## Result

No remaining repository architecture blocker was identified for the external qualification workflow. Commercial release remains **HOLD** because the real evidence package is not part of this architecture iteration.
