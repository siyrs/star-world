# Architecture Audit · 2026-08-07 · Iteration 62

## Scope reviewed

- Iteration 60 external qualification semantics;
- Iteration 61 deterministic candidate and 19-file chain bundle;
- candidate validation dependence on `ProjectRoot`;
- final release acceptance behavior under `-RequireReleaseGate`;
- cross-machine handoff and archival restore;
- release-owner selection and audit records.

## Findings

### A-62-01 · Internal consistency did not pin the intended release candidate

Iteration 61 proves that its candidate, qualification package and evidence agree with each other. A different complete candidate can also be internally consistent.

**Resolution:** create an independently retained Promotion Pin and require its `ExpectedPinId` for the commercial gate.

### A-62-02 · Receiving validation depended on the current checkout

The Iteration 61 candidate validator intentionally rechecks `data/release_qualification.json`, `project.godot` and `export_presets.cfg`. On another machine or months later, the local checkout may no longer match the candidate even when the delivered candidate is correct.

**Resolution:** the Promotion Bundle carries frozen copies of those three contract files and validates the nested chain through a temporary synthetic contract root.

### A-62-03 · The accepted Iteration 61 chain should not be silently redefined

Adding files directly to the 19-file chain would invalidate an already accepted transport contract and blur ownership between iterations.

**Resolution:** keep the inner chain immutable and add a separate outer promotion domain.

### A-62-04 · A receipt must not mutate the evidence it describes

Writing validation receipts into the promotion directory would change physical inventory and force a new `promotion_id` after every handoff.

**Resolution:** receipts are written outside the canonical bundle and explicitly reference its IDs and manifest hash.

### A-62-05 · Outer inventory needs the same fail-closed rules as the inner chain

A wrapper that checks only expected top-level files could still accept hidden injections or unsafe manifest paths.

**Resolution:** recursively enumerate with `-Force`, reject reparse points, validate safe normalized paths, require exact physical/manifest equality, and hash every payload byte.

### A-62-06 · Promotion Pin is an operational root, not a cryptographic signature

A deterministic hash pin prevents wrong/stale selection only when its ID is retained independently. It does not authenticate the human label or resist an attacker who controls both the payload and the external approval record.

**Resolution:** document this boundary explicitly and leave public-key signing/timestamping to publisher infrastructure rather than inventing an in-repository trust authority.

## Architecture decision

Iteration 62 adds an offline promotion domain above the existing release evidence layers:

```text
Iteration 60 semantic evidence package
        ↓
Iteration 61 candidate + chain bundle
        ↓
Iteration 62 release-owner pin
        ↓
Promotion Bundle
├─ immutable Iteration 61 chain
├─ frozen repository contracts
└─ promotion pin
        ↓
offline validator + external ExpectedPinId
        ↓
receiver receipt outside the bundle
```

The promotion layer:

- owns no gameplay state;
- does not modify `world.json`;
- creates no runtime service or Timer;
- reuses the accepted semantic and transport validators;
- uses temporary files only for the synthetic contract root;
- leaves the source chain and promotion payload unchanged after validation.

## Failure behavior

Validation fails closed for:

- wrong externally retained pin ID;
- missing contract snapshots;
- contract snapshot byte changes;
- nested chain corruption;
- missing, extra, visible or hidden outer files;
- path traversal, drive-qualified/absolute paths or root escape;
- symbolic links/reparse points;
- changed file lengths or SHA-256 values;
- promotion ID drift;
- a real release gate invocation without an external pin;
- receipt output inside the immutable bundle.

## Test strategy

- parse every new PowerShell script independently;
- reuse the full Iteration 61 retained fixture and its six existing tamper cases;
- create a deterministic Promotion Pin;
- assemble a reference Promotion Bundle;
- validate it using only frozen contract snapshots for evidence data;
- create an external handoff receipt;
- deliberately tamper a contract snapshot;
- deliberately tamper the nested chain;
- use the wrong expected pin;
- inject visible and hidden extra files;
- inject parent-path traversal;
- alter `promotion_id`;
- attempt to write a receipt into the immutable bundle;
- run strict Godot 4.7 import and the existing external qualification contract regression.

## Result

The repository-owned offline promotion gap is closed when these tests and all affected release workflows pass on a fixed PR head and after merge. Commercial release remains **HOLD** until the required real external evidence and release-owner decision exist.
