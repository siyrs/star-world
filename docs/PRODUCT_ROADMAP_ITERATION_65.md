# Product Roadmap · Iteration 65 · Task Workspace Governance Closure

Date: 2026-08-07

## Decision

The repository implementation and permanent validation gates continued advancing through Iteration 64, but the original v1.3.0 task workspace retained several first-loop summary documents that still described the project as in development, with seven P0/P1 bugs, zero commits and no acceptance/delivery. At the same time, the reconciled feature board already recorded FP-001..FP-011 as complete/passed and the readiness gates correctly separated repository readiness from external commercial qualification.

This is a release-governance defect: two readers can reach contradictory decisions from documents in the same task workspace.

Iteration 65 closes that defect without adding new gameplay scope.

## Scope

1. Introduce `16-current-status.json` as the machine-readable canonical task state.
2. Reconcile the current-facing Index, Test Report, Bugfix Log, Acceptance Report, Delivery Summary and Risk Register.
3. Preserve July/August first-loop history as historical evidence instead of deleting or rewriting the project history.
4. Require the canonical state to remain `11/11 complete`, repository QA passed, repository acceptance accepted, repository delivery delivered and zero repository P0/P1 blockers.
5. Keep Commercial release `HOLD` while eight explicit external qualification/signing/bootstrap gates remain.
6. Validate all FP rows against `09-feature-status-board.md` and the external HOLD boundary against `11-readiness-gates.md`.
7. Fail CI if stale current-state tokens such as `Current status: in-development`, `Delivered: no`, `Accepted: no` or seven open P0/P1 bugs reappear in current summary documents.
8. Preserve historical risk IDs RISK-001..008 but close/reconcile their repository status.
9. Track only genuine external commercial risks as RISK-009..014.
10. Compose the governance validator with the existing complete `tests/run_all.ps1` regression runner.
11. Add a dedicated pull-request/push workflow that runs governance validation, strict Godot import and the complete repository regression.

## Acceptance

Iteration 65 is accepted only if:

- the canonical JSON parses under strict PowerShell and contains the exact current task state;
- the feature board still proves all eleven FP rows `complete` and `passed`;
- repository P0/P1 blocker count is zero;
- current Index/Test/Bugfix/Acceptance/Delivery/Risk summaries agree with the canonical contract;
- stale first-loop current-state tokens are rejected;
- readiness gates continue to say Repository readiness is complete while Commercial release remains **HOLD**;
- all eight external gates remain explicitly inventoried and are not converted into fake CI passes;
- Iteration 65 static validator passes on Windows;
- strict Godot 4.7 import passes;
- the existing complete `tests/run_all.ps1` regression passes through the Iteration 65 composition runner;
- the PR is reviewed at its final head and merged only after required GitHub Actions are green.

## Product Boundary

No new gameplay feature is justified by this audit. The planned repository-owned v1.3.0 function points are already complete. The next commercial milestone is execution of the existing external qualification/signing/bootstrap controls against one immutable final candidate.

Commercial release remains **HOLD** until that real evidence exists.
