# Product Roadmap · Iteration 60 · Auditable External Qualification Evidence

## Objective

Convert the remaining commercial-release HOLD items from prose-only requirements into one executable, version-bound and anti-forgery evidence workflow without pretending that repository automation is physical target-hardware evidence.

## Completed repository scope

- Added schema v2 `ExternalQualificationContract` with explicit `fixture`, `hosted_reference` and `target_hardware` evidence classes.
- Added independent E4-H review recording with self-review, incomplete-checklist and unresolved-blocker rejection.
- Extended the five-profile Windows Release matrix so minimum and recommended qualification reuse one exact prebuilt EXE/PCK.
- Added target-hardware collection for CPU, GPU, RAM, OS, storage, machine fingerprint and five-profile final-package routes.
- Bound both hardware tiers to `data/release_qualification.json` and added validation-time recomputation of 35 five-profile performance assertions per tier.
- Added a strict wall-clock soak harness that refuses real runs below policy duration/route count, rotates the exact final package through all five profiles and enforces fatal, transport and Working Set growth limits.
- Routed fixed-package release-smoke shutdown through the production quit coordinator and made every strict-soak cycle prove `prepared_quit` lifecycle semantics.
- Added resumable two-phase HDD, antivirus and power-loss records with world identity, before/after hashes and exact EXE/PCK continuity across restart.
- Added a package assembler that binds every record to one commit, EXE and PCK and invokes the strict validator.
- Added validation-time rebinding in both GDScript and PowerShell so stored JSON cannot mix another commit, binary, evidence class, reference flag, fault operator, loosened policy, forged performance PASS or dirty lifecycle.
- Added a non-qualifying retained fixture and an end-to-end test that assembles, mutates and requires rejection of a reference package.
- Added a permanent Godot 4.7 workflow for schema, parser, anti-forgery and adjacent release-contract regression.

## Review corrections made during implementation

- The first hardware collector design exported a package per hardware tier. It was replaced with exact prebuilt-package reuse so minimum, recommended, soak and E4-H evidence share identical binary hashes.
- The first soak wrapper attempted to keep one ReleaseSmokeRunner alive through a large frame count. It was replaced with repeated clean runs of the exact final package and a real `Stopwatch` wall-clock target.
- Fault evidence assembly uses explicit operator equality and now persists the exact build hashes in both prepare and complete phases.
- The first package contract verified bindings only while assembling. Schema v2 rechecks all child bindings every time either validator reads the package.
- Reference fixtures and hosted evidence remain structurally valid but are prohibited from setting `release_gate_passed=true`.

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

Iteration 60 repository scope is complete when its permanent workflow passes. Commercial release remains **HOLD** until a real schema v2 package validates as `external_evidence_complete`.
