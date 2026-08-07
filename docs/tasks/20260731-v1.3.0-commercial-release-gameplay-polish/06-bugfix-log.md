# Bugfix Log

## Current Bugfix Summary
- Reconciled at: 2026-08-07 (Iteration 65)
- Remaining repository P0/P1 bugs: 0
- Original bugfix loop: closed/superseded by permanent regressions
- Repository QA: passed
- Commercial release: HOLD for external-only qualification/signing gates

## Historical bugfix evidence
The original task opened nine product/tool findings during the first implementation loop. They remain valuable as root-cause history, but their 2026-07-31 / 2026-08-01 statuses must not be used as the current release state.

| Bug ID | Original Area | Current Reconciliation | Permanent Evidence Family |
|---|---|---|---|
| BUG-QA-002 | desktop acceptance runner contract | closed | desktop acceptance + permanent QA runners |
| BUG-UI-002 | UI interaction-state contrast | closed | UI design-system/accessibility regressions |
| BUG-SPAWN-001 | spawn quality / deterministic seed / leak gates | closed | spawn experience + profile journey regressions |
| BUG-VERSION-001 | version identity | closed | release/version validation gates |
| BUG-REL-001 | Windows release compatibility | closed for repository scope | release smoke and Windows release workflows |
| BUG-UI-001 | pixel-font warning / UI packaging | closed for repository scope | UI/import/export regressions |
| BUG-PERF-001 | chunk/runtime health warning | closed for repository scope | runtime-health, scale and long-session regressions |
| BUG-OBS-001 | unreliable memory/health observability | closed for repository scope | runtime-health source/report validation |
| BUG-PACK-001 | QA resources in production package | closed for repository scope | packaging/release contract gates |

## Closure Rule
A historical bug is considered closed for repository delivery only when later production code and permanent regression gates cover the affected behavior. Iterations 57-64 supplied those permanent gates, and `09-feature-status-board.md` records FP-001..FP-011 as complete/passed.

## External Boundary
The following are not repository bugs and must not be entered as fake bugfixes simply to make the board green:

- independent E4-H sign-off;
- real minimum/recommended hardware runs;
- real 7,200-second target-hardware soak;
- physical HDD/antivirus/power-loss qualification;
- release-owner retained Promotion Pin and publisher-certificate hash;
- production Authenticode signing/trusted timestamp;
- production updater trust-pin bootstrap and signed publication.

These remain commercial-release gates in `11-readiness-gates.md` and `16-current-status.json`.
