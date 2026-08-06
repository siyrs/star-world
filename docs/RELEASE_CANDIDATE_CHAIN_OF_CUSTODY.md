# Release Candidate Chain of Custody

Iteration 61 closes the transport and handoff gap between the Iteration 60 qualification collectors. Iteration 60 proves that every submitted record belongs to one commit, EXE and PCK when the package is assembled. Iteration 61 adds one immutable candidate manifest and one directly inspectable portable bundle so the same final candidate and its reviewable source evidence can be copied between the reviewer, minimum machine, recommended machine, soak machine and fault laboratory without relying on file names or operator memory.

## Design goals

- identify one final candidate by content rather than directory name;
- bind the EXE, PCK and repository release contracts before external testing begins;
- copy the candidate, summary records and supporting reports without losing their hashes;
- let a recipient independently verify every hash referenced by a summary JSON;
- detect missing, hidden, extra, replaced, truncated or path-traversal files;
- retain ordinary files that can be inspected without extracting an opaque archive;
- preserve the distinction between reference evidence and real target-hardware evidence;
- never claim that chain-of-custody validation proves a human identity or a physical event.

## 1. Create the final candidate manifest

After the final Windows export has been selected, create the manifest once:

```powershell
pwsh -NoProfile -File tests/ci/new_release_candidate_manifest.ps1 `
  -ProjectRoot . `
  -CommitSha <40-character-lowercase-sha> `
  -Version v1.3.0 `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -OutputPath evidence\release-candidate.json
```

The manifest records:

- Git commit and product version;
- exact EXE and PCK lengths and SHA-256 values;
- `data/release_qualification.json` hash;
- `project.godot` hash;
- `export_presets.cfg` hash;
- a deterministic `candidate_id` derived from all of those facts.

Absolute machine paths are not part of `candidate_id`. The same bytes therefore retain one identity after being copied to another machine. The three repository contract paths are fixed and cannot be redirected by editing the manifest.

Validate after every copy:

```powershell
pwsh -NoProfile -File tests/ci/validate_release_candidate_manifest.ps1 `
  -ProjectRoot . `
  -CandidateManifestPath evidence\release-candidate.json `
  -ReleaseExecutable D:\incoming\StarWorld.exe `
  -ReleasePck D:\incoming\StarWorld.pck
```

## 2. Collect Iteration 60 evidence

Use the existing Iteration 60 collectors for:

- independent E4-H review;
- minimum target-hardware matrix;
- recommended target-hardware matrix;
- strict 7,200-second soak;
- HDD recovery;
- antivirus-interference recovery;
- power-loss recovery;
- final release-owner approval.

Retain both each summary JSON and every report referenced by its SHA-256:

- minimum and recommended five-profile journey matrices;
- release lifecycle report;
- strict-soak cycles report and progress journal;
- HDD, antivirus and power-loss recovery reports.

Every collector records the final package hashes. The Iteration 60 package assembler rejects mixed builds before creating `qualification-package.json`.

## 3. Assemble the portable chain bundle

After the qualification package is complete:

```powershell
pwsh -NoProfile -File tests/ci/new_external_qualification_chain_bundle.ps1 `
  -ProjectRoot . `
  -CandidateManifestPath evidence\release-candidate.json `
  -QualificationPackagePath evidence\qualification-package.json `
  -ReleaseExecutable C:\candidate\StarWorld.exe `
  -ReleasePck C:\candidate\StarWorld.pck `
  -ExperienceReviewPath evidence\e4-h-review.json `
  -MinimumHardwarePath evidence\hardware-minimum.json `
  -RecommendedHardwarePath evidence\hardware-recommended.json `
  -StrictSoakPath evidence\strict-soak.json `
  -HddFaultPath evidence\fault-hdd.json `
  -AntivirusFaultPath evidence\fault-antivirus.json `
  -PowerLossFaultPath evidence\fault-power-loss.json `
  -MinimumJourneyMatrixPath evidence\minimum\release-journey-matrix.json `
  -RecommendedJourneyMatrixPath evidence\recommended\release-journey-matrix.json `
  -LifecycleReportPath evidence\soak\release-lifecycle-report.json `
  -StrictSoakReportPath evidence\soak\strict-soak-cycles.json `
  -StrictSoakProgressPath evidence\soak\strict-soak.progress.jsonl `
  -HddRecoveryEvidencePath evidence\faults\hdd-recovery.json `
  -AntivirusRecoveryEvidencePath evidence\faults\antivirus-recovery.json `
  -PowerLossRecoveryEvidencePath evidence\faults\power-loss-recovery.json `
  -OutputDirectory delivery\star-world-v1.3.0 `
  -RequireReleaseGate
```

The canonical output contains `bundle-manifest.json` plus exactly 19 payload files:

```text
release-candidate.json
qualification-package.json
binary/StarWorld.exe
binary/StarWorld.pck
evidence/e4-h-review.json
evidence/hardware-minimum.json
evidence/hardware-recommended.json
evidence/strict-soak.json
evidence/fault-hdd.json
evidence/fault-antivirus.json
evidence/fault-power-loss.json
support/hardware-minimum-journey-matrix.json
support/hardware-recommended-journey-matrix.json
support/release-lifecycle-report.json
support/strict-soak-cycles.json
support/strict-soak.progress.jsonl
support/fault-hdd-recovery.json
support/fault-antivirus-recovery.json
support/fault-power-loss-recovery.json
```

The assembler rejects a non-empty output directory to prevent stale evidence from silently surviving a new bundle. It validates every referenced supporting report against the hash stored by its source collector, copies the file, and hashes the copy again.

## 4. Validate after transport or archival restore

```powershell
pwsh -NoProfile -File tests/ci/validate_external_qualification_chain_bundle.ps1 `
  -ProjectRoot . `
  -BundleDirectory D:\received\star-world-v1.3.0 `
  -RequireReleaseGate
```

The validator checks:

- the exact 19-file payload, including hidden files in enumeration and no extras;
- no symbolic links or reparse points;
- safe relative paths with no absolute, drive-prefixed or parent-directory traversal;
- every file length and SHA-256 against `bundle-manifest.json`;
- the deterministic candidate ID;
- current repository policy, project and export-preset hashes;
- the Iteration 60 package contract;
- commit, version, EXE and PCK equality between candidate and package;
- actual summary evidence hashes against `artifact_manifest`;
- all eight supporting-report hashes against the source summary records;
- the deterministic `bundle_id`.

A valid reference bundle remains non-qualifying. `-RequireReleaseGate` succeeds only when the embedded Iteration 60 package is real target-hardware evidence and passes its own strict release gate.

## Security and evidence boundary

This chain detects accidental mixing and post-assembly byte changes. It does not provide public-key signatures, timestamp-authority proof, reviewer identity proof or physical-event proof. Those remain organizational controls. The repository intentionally avoids inventing a signing authority or storing hardware serial numbers.

The directory format is canonical and inspectable. Teams may archive it with an external ZIP, storage system or release artifact after validation, but the ZIP itself is not the source of truth.

## Permanent regression

`.github/workflows/release-candidate-chain-iteration-61-tests.yml` runs:

- PowerShell parser validation;
- candidate generation and validation;
- reference qualification package assembly;
- 19-file portable bundle assembly and revalidation;
- summary evidence tamper rejection;
- supporting-report tamper rejection;
- candidate-ID tamper rejection;
- visible unexpected-file rejection;
- hidden unexpected-file rejection;
- parent-path traversal rejection;
- strict Godot 4.7 import;
- the existing external qualification GDScript regression.

A green workflow proves that the chain mechanism works. It does not replace the real external executions listed in the commercial release checklist.
