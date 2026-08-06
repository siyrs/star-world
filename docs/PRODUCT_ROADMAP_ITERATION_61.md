# Product Roadmap · Iteration 61 · Release Candidate Chain of Custody

## Objective

Close the remaining repository-owned handoff gap after Iteration 60: identify one final Windows candidate before external qualification, carry it between machines without relying on file names, and validate the complete candidate plus evidence directory after every copy or archival restore.

## Completed repository scope

- Add a deterministic release-candidate manifest bound to one commit, version, EXE, PCK and the governing release/project/export contracts.
- Derive `candidate_id` from content and byte lengths rather than machine-specific absolute paths.
- Add strict candidate validation against copied EXE/PCK files and the current repository contracts.
- Add a directly inspectable portable evidence bundle containing the final binary, candidate manifest, Iteration 60 qualification package and all seven source evidence records.
- Reject stale output directories, unexpected files, missing files, reparse points and parent-directory traversal.
- Verify every copied file by length and SHA-256.
- Revalidate the Iteration 60 package and compare its artifact manifest against the physical evidence JSON files.
- Derive a deterministic `bundle_id` from the candidate ID, package hash and sorted file manifest.
- Add retained reference assembly plus four deliberate tamper cases.
- Add a permanent Windows/Godot 4.7 workflow and operator documentation.
- Reconcile the main roadmap and commercial-release status board with Iterations 60 and 61.

## Review corrections made during implementation

- A ZIP-only design was rejected because it would make the canonical evidence opaque and would shift trust to archive metadata. The canonical output remains an ordinary directory with a byte-level manifest.
- Candidate identity excludes absolute paths so the same candidate remains stable across machines.
- Bundle assembly refuses non-empty destinations instead of trying to clean or merge old evidence.
- Validation enumerates the complete file set and rejects extras, rather than checking only expected files.
- Candidate validation binds the current qualification policy, `project.godot` and `export_presets.cfg`, preventing a package from being evaluated under a different repository contract.

## Preserved boundaries

- No gameplay state, world schema, save domain, Timer, scheduler or runtime node is introduced.
- Iteration 60 collectors and package validator remain the authority for experiential, hardware, soak and fault evidence semantics.
- Iteration 61 owns transport integrity only.
- Human identity, physical hardware identity and real interruption proof remain external attestations.
- Reference and hosted evidence remain non-qualifying.

## Remaining external execution

The following still require people and physical machines:

- independent E4-H review;
- minimum and recommended target-hardware runs;
- strict 7,200-second target-hardware soak;
- real HDD, antivirus and power-loss experiments;
- release-owner approval of a real package;
- organizational signing, timestamping or archival controls if required by the publisher.

## Decision

Iteration 61 repository scope is complete when the candidate-chain workflow and all affected release workflows pass on a fixed PR head and after merge to `master`. Commercial release remains **HOLD** until the real Iteration 60 evidence is collected and the resulting Iteration 61 bundle passes `-RequireReleaseGate`.
