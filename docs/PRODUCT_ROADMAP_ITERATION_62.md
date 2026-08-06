# Product Roadmap · Iteration 62 · Offline Release Promotion

## Objective

Close the remaining repository-owned promotion gap after Iteration 61: a chain bundle must be independently verifiable without trusting the current repository checkout, and final release approval must be pinned to an externally retained identity so a different but internally consistent candidate cannot be substituted by mistake.

## Completed repository scope

- Add a release-owner promotion pin with one deterministic `pin_id` bound to candidate ID, chain bundle ID, package ID, commit, version, EXE/PCK hashes, release channel and owner label.
- Keep the promotion pin separate from the immutable chain bundle until the release owner intentionally selects the candidate.
- Add a Promotion Bundle wrapper that preserves the Iteration 61 chain unchanged and adds frozen snapshots of `data/release_qualification.json`, `project.godot` and `export_presets.cfg`.
- Validate the nested candidate chain against those frozen snapshots through a temporary synthetic contract root, so evidence validation does not depend on whatever repository version happens to be checked out on the receiving machine.
- Require an externally retained `ExpectedPinId` whenever `-RequireReleaseGate` is used.
- Reject promotion bundles with missing/extra physical files, hidden injections, unsafe paths, reparse points, hash/length changes or promotion-ID drift.
- Add a handoff receipt written outside the immutable promotion bundle. The receipt records promotion, pin, candidate, chain and package identity plus validator hashes and the promotion-manifest hash.
- Prevent a receipt from mutating the canonical promotion directory.
- Add retained reference assembly and eight negative tests covering contract tamper, nested-chain tamper, wrong expected pin, visible/hidden injection, path traversal, promotion-ID tamper and receipt-in-bundle mutation.
- Add a permanent Windows/Godot 4.7 workflow, full-runner integration, architecture audit and operator documentation.

## Review corrections

- A direct change to the Iteration 61 19-file chain was rejected. Iteration 62 wraps the accepted chain rather than changing its canonical payload.
- Current-repository validation alone was rejected because an operator could validate the right binary against the wrong checkout. Contract snapshots are now carried with the promotion payload.
- Internal consistency alone was rejected for the final gate. Real release validation requires an externally retained pin ID that is not derived during the validation call.
- Handoff receipts are append-only records outside the canonical bundle, so receiving evidence never changes `promotion_id`.

## Preserved boundaries

- No gameplay, world save, scheduler, Timer, runtime node or persistent game schema changes.
- Iteration 60 remains the semantic authority for E4-H, hardware, soak and fault evidence.
- Iteration 61 remains the canonical candidate/evidence chain.
- Iteration 62 owns promotion selection, offline contract snapshots and handoff validation only.
- The pin and receipt are not cryptographic signatures and do not prove a human identity. They prevent stale/wrong candidate selection and create an auditable operational record.

## Remaining external execution

Commercial release still requires:

- an independent E4-H reviewer;
- minimum and recommended physical target-hardware runs;
- a real 7,200-second target-hardware soak;
- real HDD, antivirus and power-loss experiments;
- release-owner selection of the final candidate and retention of the resulting `pin_id` outside the promotion bundle;
- publisher signing/timestamp infrastructure if stronger identity authenticity is required.

## Decision

Iteration 62 repository scope is complete when its permanent workflow and all affected release gates pass on one fixed PR head and again after merge to `master`. Commercial release remains **HOLD** until real external evidence exists and the final Promotion Bundle succeeds with `-RequireReleaseGate -ExpectedPinId <retained-pin>`.
