# External Qualification Evidence Kit · Iteration 60

## Repository implementation checklist

- [x] Define one schema v2 evidence package.
- [x] Distinguish fixture, hosted reference and target-hardware evidence.
- [x] Prevent hosted CI and fixtures from closing commercial release gates.
- [x] Bind the package to one commit, one EXE SHA-256 and one PCK SHA-256.
- [x] Revalidate every child binding after package assembly in both GDScript and PowerShell.
- [x] Reject mixed commit, EXE, PCK, evidence-source, reference-flag and fault-operator records.
- [x] Add an independent E4-H review recorder.
- [x] Reject self-review, incomplete checklists and unresolved blockers.
- [x] Reuse the exact final EXE/PCK across the five-profile route matrix.
- [x] Add minimum/recommended hardware collectors.
- [x] Record normalized CPU, GPU, RAM, OS and storage evidence.
- [x] Bind both hardware records to `data/release_qualification.json` and recompute all 35 five-profile performance assertions per tier.
- [x] Add a strict wall-clock final-package soak harness.
- [x] Reject real target-hardware soak shorter than 7,200 seconds.
- [x] Require at least 10 completed real routes, zero fatal diagnostics, zero transport/write violations and policy-bounded Working Set growth.
- [x] Rotate the strict soak across all five formal profiles.
- [x] Route fixed-package smoke/soak exits through the production quit coordinator and reject non-prepared lifecycle reports.
- [x] Add resumable HDD, antivirus and power-loss experiment records.
- [x] Preserve world identity, pre/post-fault hashes and exact EXE/PCK across both phases.
- [x] Add package assembly with cross-artifact hash verification.
- [x] Add strict package validation and `-RequireReleaseGate` mode.
- [x] Add a retained non-qualifying schema v2 fixture.
- [x] Add end-to-end assembly, mutation and rebinding-rejection regression.
- [x] Add permanent Godot 4.7, PowerShell parser and anti-forgery CI.
- [x] Document commands, evidence boundaries and commercial decision rules.

## External execution checklist

These items cannot be marked complete by repository automation:

- [ ] An independent person performs and signs the E4-H final-build review.
- [ ] The exact final EXE/PCK passes the minimum target-hardware five-profile matrix.
- [ ] The same exact final EXE/PCK passes the recommended target-hardware five-profile matrix.
- [ ] The same exact final EXE/PCK completes at least 7,200 seconds and 10 routes on target hardware with five profiles, fatal=0, no transport and Working Set growth within policy.
- [ ] A real HDD interference/recovery experiment is completed.
- [ ] A real antivirus interference/recovery experiment is completed.
- [ ] A real power-loss interruption/recovery experiment is completed.
- [ ] The release owner attaches every artifact and approves the final package.
- [ ] `validate_external_qualification_package.ps1 -RequireReleaseGate` returns `external_evidence_complete`.

## Acceptance rule

Repository implementation is accepted when the Iteration 60 permanent workflow is green on the fixed PR head. Commercial release remains **HOLD** while any external execution item above is unchecked.
