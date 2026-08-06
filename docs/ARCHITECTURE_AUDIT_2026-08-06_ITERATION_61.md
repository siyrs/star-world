# Architecture Audit · 2026-08-06 · Iteration 61

## Scope reviewed

- Iteration 60 evidence schema and package assembler;
- independent review, hardware, strict soak and fault recorders;
- `artifact_manifest` and supporting-report hash behavior;
- cross-machine final-candidate transport;
- roadmap and commercial-release task board state.

## Findings

### A-61-01 · Evidence semantics were strong but transport identity was implicit

Iteration 60 rejects mixed commit, EXE and PCK hashes during package assembly and validation. Before assembly, however, operators could still identify the candidate by directory name or a copied command line.

**Resolution:** create one deterministic candidate manifest before external execution and validate it after every transfer.

### A-61-02 · Absolute paths cannot be part of candidate identity

Minimum, recommended, soak and fault machines naturally store the same files at different locations. Including those paths would generate a different identity on every machine.

**Resolution:** candidate identity uses commit, version, lengths and content hashes only. Paths are limited to stable file names and fixed repository contract paths.

### A-61-03 · Package artifact hashes were not tied to a delivered directory

The Iteration 60 package contains hashes for all source evidence records, but a recipient still needed to locate the matching files manually.

**Resolution:** create a canonical directory layout and validate the physical summary records against the package artifact manifest.

### A-61-04 · Summary records alone were not independently reviewable

Hardware records reference their five-profile journey matrices; strict-soak records reference lifecycle, cycles and progress reports; fault records reference recovery reports. Delivering only the summary JSON preserved a digest but not the bytes a recipient needed to verify it.

**Resolution:** carry all eight referenced supporting reports in the canonical bundle and revalidate each report against its source record.

### A-61-05 · Copy destinations must fail closed

Merging a new evidence set into an old directory can preserve obsolete screenshots, logs or JSON records and create ambiguous delivery state.

**Resolution:** bundle assembly refuses a non-empty destination. It never deletes or merges operator evidence automatically.

### A-61-06 · Expected-file checks alone do not reject injection

A validator that only verifies required files can still accept an unexpected executable, script or misleading second package. A normal enumeration can also omit hidden files.

**Resolution:** recursively enumerate with `-Force` and require an exact 19-file payload plus `bundle-manifest.json`.

### A-61-07 · Portable paths require traversal and link defenses

A manifest path can be syntactically relative while escaping the root through `..`, a drive prefix or a reparse point.

**Resolution:** reject absolute/drive/parent paths before allowlist evaluation, verify resolved paths remain beneath the bundle root and reject all reparse points.

### A-61-08 · The main roadmap lagged the merged implementation

`docs/PRODUCT_ROADMAP.md` still described Iteration 59 as the current end state after Iteration 60 had already merged.

**Resolution:** reconcile the main roadmap with Iteration 60 and this chain-of-custody iteration as part of the same PR.

## Architecture decision

Iteration 61 is an offline release-evidence transport domain:

- it owns no gameplay state;
- it does not alter `world.json` or any runtime service;
- it builds on the existing Iteration 60 semantic validator;
- it verifies ordinary files and deterministic JSON;
- it keeps the canonical bundle inspectable without archive extraction;
- it treats source summaries and supporting reports as one evidence graph;
- it avoids private keys, device serials and invented identity authority.

## Failure behavior

The chain fails closed for:

- missing, visible-extra or hidden-extra files;
- changed byte length or SHA-256;
- changed candidate identity;
- candidate/package commit, version or binary mismatch;
- summary evidence files that do not match `artifact_manifest`;
- supporting reports that do not match their source records;
- stale non-empty output directories;
- symbolic links/reparse points;
- absolute, drive-prefixed or parent paths;
- a reference package presented with `-RequireReleaseGate`.

No failed validation mutates source evidence.

## Test strategy

- parse every new PowerShell script independently;
- assemble the existing retained Iteration 60 reference package;
- generate and validate a real byte-derived candidate manifest;
- assemble and validate the complete 19-file portable payload;
- deliberately mutate summary evidence content;
- deliberately mutate a supporting report;
- deliberately mutate candidate identity while updating the outer file hash;
- inject a visible unexpected file;
- inject a hidden unexpected file;
- inject a parent-path manifest entry;
- run strict Godot 4.7 import and the existing qualification GDScript regression;
- retain the assembled reference directory as workflow evidence.

## Result

The repository-owned chain-of-custody and referenced-evidence completeness gaps are closed when the permanent workflow is green. External commercial qualification remains **HOLD** because transport integrity cannot substitute for independent people, physical machines or real interruption events.
