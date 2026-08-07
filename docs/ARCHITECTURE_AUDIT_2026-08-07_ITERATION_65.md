# Architecture Audit · Iteration 65 · Task Workspace Governance Closure

Date: 2026-08-07

## Audit question

Can one release owner, QA reviewer or automation process determine the current v1.3.0 task state without manually reconciling contradictory historical Markdown documents, while preserving the original development history and the external commercial-release trust boundary?

## Findings

### 1. Historical summaries were being treated as live state

`00-index.md`, `05-test-report.md`, `06-bugfix-log.md`, `07-acceptance-report.md` and `08-delivery-summary.md` still described the first implementation loop. Later iterations updated `09-feature-status-board.md` and `11-readiness-gates.md`, so the workspace had multiple incompatible truths.

Decision: distinguish historical snapshots from current-state authority explicitly.

### 2. Markdown-only state has no enforceable consistency contract

Human-readable prose is valuable for rationale, but CI cannot safely infer release state from arbitrary prose without a stable schema.

Decision: add `16-current-status.json` with exact repository implementation, QA, acceptance, delivery, function-point counts, blocker count, commercial decision and external-gate inventory.

### 3. One JSON file alone could become another stale source

A canonical contract is useful only if it is continuously checked against the detailed feature board and readiness boundary.

Decision: the Iteration 65 validator cross-checks the contract, six current summaries, all FP-001..FP-011 rows, readiness HOLD text, risk history and the Iteration 65 workflow itself.

### 4. Historical evidence must not be destroyed to make the current board look clean

Replacing every planning artifact with today's wording would erase why earlier rejections and bug loops were legitimate.

Decision: preserve planning/collaboration/decision records and label the reconciled reports clearly. Git history remains the immutable record of the original rejected snapshots.

### 5. Repository delivery and commercial release are separate state machines

The code/test/tooling scope can be delivered while physical hardware, independent human review and production signing are still legitimately outstanding.

Decision: canonical state supports `repository_delivery=delivered` together with `commercial_release=hold`. CI is forbidden from converting external evidence into a synthetic pass.

### 6. Governance must participate in the same regression surface

A docs-only validator that never runs beside product regressions could allow release governance to diverge from the tested repository.

Decision: `tests/ci/run_iteration_65_full_regression.ps1` first validates governance and then delegates unchanged to the existing `tests/run_all.ps1`. The dedicated workflow also performs strict Godot import before the full regression.

## Architecture

```text
09-feature-status-board.md ─┐
                            ├──► Iteration 65 governance validator
11-readiness-gates.md ──────┤        │
                            │        ├── validates 16-current-status.json
16-current-status.json ─────┤        ├── validates current summary documents
                            │        ├── rejects stale live-state tokens
00/05/06/07/08/15 docs ─────┘        └── preserves commercial HOLD boundary
                                             │
                                             ▼
                              run_iteration_65_full_regression.ps1
                                             │
                                             ├── governance validator
                                             └── existing tests/run_all.ps1
                                                        │
                                                        ▼
                                            GitHub Actions PR/push gate
```

## State ownership

- `16-current-status.json` owns machine-readable current task state.
- `09-feature-status-board.md` owns detailed function-point implementation/validation evidence.
- `11-readiness-gates.md` owns the repository-ready versus external-commercial-HOLD boundary.
- `00`, `05`, `06`, `07`, `08` and `15` are current human-readable summaries that must agree with the contract.
- planning, collaboration and decision documents remain historical evidence unless separately reconciled.
- GitHub Actions owns repeatable enforcement, not commercial-signing authority.

## Failure behavior

The validator fails closed when:

- any FP row is no longer complete/passed;
- repository blocker count becomes non-zero while summaries still claim delivery;
- stale in-development/not-delivered/not-accepted language returns to current summaries;
- Commercial HOLD disappears while external gates remain;
- historical risk IDs disappear;
- the external-gate inventory is silently reduced;
- the permanent workflow stops running the validator or the full regression composition.

## External trust boundary

The governance contract intentionally cannot satisfy independent E4-H review, physical machine tests, real 7,200-second soak, HDD/antivirus/power-loss experiments, release-owner pin retention, publisher private-key signing, trusted timestamping or first-production updater pin bootstrap. Those controls stay outside hosted CI and remain explicit reasons for Commercial HOLD.

## Conclusion

Iteration 65 is a maintainability and release-reliability correction, not feature expansion. It removes contradictory current state from the task workspace, creates one enforceable state model, preserves audit history and prevents future documentation drift from silently changing the release decision.
