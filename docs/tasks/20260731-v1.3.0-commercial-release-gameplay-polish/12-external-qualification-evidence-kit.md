# External Qualification Evidence Kit · Iteration 60

## Repository implementation checklist

- [x] Define one versioned evidence package schema.
- [x] Distinguish fixture, hosted reference and target-hardware evidence.
- [x] Prevent hosted CI and fixtures from closing commercial release gates.
- [x] Bind the package to one commit, one EXE SHA-256 and one PCK SHA-256.
- [x] Add an independent E4-H review recorder.
- [x] Reject self-review, incomplete checklists and unresolved blockers.
- [x] Reuse the exact final EXE/PCK across the five-profile route matrix.
- [x] Add minimum/recommended hardware collectors.
- [x] Record normalized CPU, GPU, RAM, OS and storage evidence.
- [x] Add a strict wall-clock final-package soak harness.
- [x] Reject real target-hardware soak shorter than 7,200 seconds.
- [x] Rotate the strict soak across all five formal profiles.
- [x] Preserve zero post-spawn transport and clean-cycle exits.
- [x] Add resumable HDD, antivirus and power-loss experiment records.
- [x] Preserve world identity plus pre/post-fault hashes.
- [x] Add package assembly with cross-artifact hash verification.
- [x] Add strict package validation and `-RequireReleaseGate` mode.
- [x] Add a retained non-qualifying reference fixture.
- [x] Add end-to-end virtual package assembly regression.
- [x] Add permanent Godot 4.7, PowerShell parser and anti-forgery CI.
- [x] Document commands, evidence boundaries and commercial decision rules.

## External execution checklist

These items cannot be marked complete by repository automation:

- [ ] An independent person performs and signs the E4-H final-build review.
- [ ] The exact final EXE/PCK passes the minimum target-hardware five-profile matrix.
- [ ] The same exact final EXE/PCK passes the recommended target-hardware five-profile matrix.
- [ ] The same exact final EXE/PCK completes at least 7,200 seconds on target hardware.
- [ ] A real HDD interference/recovery experiment is completed.
- [ ] A real antivirus interference/recovery experiment is completed.
- [ ] A real power-loss interruption/recovery experiment is completed.
- [ ] The release owner attaches every artifact and approves the final package.
- [ ] `validate_external_qualification_package.ps1 -RequireReleaseGate` returns `external_evidence_complete`.

## Acceptance rule

Repository implementation is accepted when the Iteration 60 permanent workflow is green. Commercial release remains **HOLD** while any external execution item above is unchecked.
