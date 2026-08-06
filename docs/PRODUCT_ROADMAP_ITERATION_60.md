# Product Roadmap · Iteration 60 · Auditable External Qualification Evidence

## Objective

Convert the remaining commercial-release HOLD items from prose-only requirements into one executable, version-bound and anti-forgery evidence workflow without pretending that repository automation is physical target-hardware evidence.

## Completed repository scope

- Added `ExternalQualificationContract` with explicit `fixture`, `hosted_reference` and `target_hardware` evidence classes.
- Added independent E4-H review recording with self-review, incomplete-checklist and unresolved-blocker rejection.
- Extended the five-profile Windows Release matrix so minimum and recommended qualification can reuse one exact prebuilt EXE/PCK.
- Added target-hardware collection for CPU, GPU, RAM, OS, storage, machine fingerprint and five-profile final-package routes.
- Added a strict wall-clock soak harness that refuses real runs below 7,200 seconds and rotates the exact final package through all five profiles.
- Added resumable two-phase HDD, antivirus and power-loss fault-lab records with world identity and before/after hashes.
- Added a package assembler that binds every record to one commit, EXE and PCK and invokes the strict validator.
- Added independent GDScript and PowerShell validators, a non-qualifying retained fixture and an end-to-end assembler test.
- Added a permanent Godot 4.7 workflow for schema, parser, anti-forgery and adjacent release-contract regression.

## Review corrections made during implementation

- The first hardware collector design exported a package per hardware tier. It was replaced with exact prebuilt-package reuse so minimum, recommended, soak and E4-H evidence can share identical binary hashes.
- The first soak wrapper attempted to keep one ReleaseSmokeRunner alive through a large frame count. It was replaced with repeated clean runs of the exact final package and a real `Stopwatch` wall-clock target, avoiding frame-rate-dependent duration claims.
- Fault evidence assembly now uses explicit operator-identity equality checks rather than pipeline-precedence-sensitive array logic.
- Reference fixtures and hosted evidence are structurally valid but explicitly prohibited from setting `release_gate_passed=true`.

## Preserved architecture boundaries

- The qualification domain owns evidence validation only and never owns gameplay or save state.
- `world.json` remains the authoritative world payload and is only read by the fault recorder for identity and hashing.
- Existing release-smoke and five-profile journey implementations are reused rather than duplicated.
- No new gameplay Timer, Thread, global group scan or persistent world field was introduced.
- Hardware identifiers are normalized and hashed; device serial numbers are not written to the package.
- Hosted CI validates the mechanism but cannot create `target_hardware` acceptance.

## Remaining external execution

The repository kit is complete, but these evidence runs remain external until humans and physical machines execute them:

- independent E4-H final-build experiential review;
- minimum target-hardware five-profile qualification;
- recommended target-hardware five-profile qualification;
- strict 7,200-second final-package target-hardware soak;
- real HDD interference/recovery experiment;
- real antivirus interference/recovery experiment;
- real power-loss interruption/recovery experiment;
- final release-owner attachment and approval of the complete package.

## Decision

Iteration 60 repository scope is complete when its permanent workflow passes. Commercial release remains **HOLD** until a real package validates as `external_evidence_complete`.
