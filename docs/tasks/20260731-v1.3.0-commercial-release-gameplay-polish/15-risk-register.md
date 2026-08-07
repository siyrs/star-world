# Risk Register

Track delivery, product, architecture, implementation, QA, release and coordination risks without confusing historical repository risks with current external commercial gates.

## Current Risk Summary
- Reconciled at: 2026-08-07 (Iteration 65)
- Repository implementation blockers: 0
- Open repository P0/P1 bugs: 0
- Commercial release risks remain external
- Canonical status: `16-current-status.json`

## Historical Repository Risks
| Risk ID | Original Category | Description | Current Status | Closure / Mitigation Evidence |
|---|---|---|---|---|
| RISK-001 | qa | Dynamic/procedural content discovery could omit formal content | closed | deterministic five-profile/content registries and coverage matrices |
| RISK-002 | release | stale build could be mistaken for current source | closed | fresh export, exact candidate hashes and immutable candidate identity |
| RISK-003 | qa | GUI observation alone could not prove internal state | closed | screenshots plus in-game JSON/log/save assertions and desktop acceptance runners |
| RISK-004 | development | QA/performance tooling could leak into release logic/package | closed | isolated tests/tools, package contracts and release workflows |
| RISK-005 | qa | testing could contaminate existing user saves | closed | isolated user-data directories, save/catalog recovery and protected deletion gates |
| RISK-006 | qa | performance evidence could drift with environment/sampling | closed for repository scope | exact-package collectors, immutable candidate identity and fixed evidence schema; real target hardware remains external below |
| RISK-007 | development | broad fixes could regress saves/APIs/gameplay | closed | focused + adjacent + full permanent regressions across persistence and gameplay |
| RISK-008 | coordination | long work could lose checkpoints/evidence continuity | closed for repository scope | machine-readable candidate/package/promotion/distribution receipts and permanent CI |

## Current External Commercial Risks
| Risk ID | Category | Description | Probability | Impact | Mitigation / Required Evidence | Owner | Status |
|---|---|---|---|---|---|---|---|
| RISK-009 | independent-qa | Hosted CI cannot perform independent E4-H human acceptance | medium | high | independent reviewer completes signed evidence against exact candidate | Release Owner + Independent QA | external-open |
| RISK-010 | hardware | Hosted runners cannot prove minimum/recommended physical-machine behavior or real 7,200-second target soak | medium | high | run exact final EXE/PCK on both physical tiers and complete strict target soak | QA / Release Owner | external-open |
| RISK-011 | fault-qualification | HDD, antivirus interference and power-loss behavior require physical experiments | medium | high | execute two-phase prepare/complete fault-lab records and assemble them into the external package | QA / Release Owner | external-open |
| RISK-012 | promotion-identity | An internally consistent but unintended candidate could be promoted | low | critical | release owner independently retains and checks intended Promotion Pin before gate execution | Release Owner | external-open |
| RISK-013 | publisher-signing | Repository/hosted CI must not possess or simulate the production publisher private key or trusted timestamp | medium | critical | sign exact final EXE externally, trusted-timestamp it, retain publisher certificate SHA-256, then run Distribution Gate | Release Owner / Signing Operator | external-open |
| RISK-014 | update-bootstrap | First production install needs real manifest/publisher pins and signed publication without allowing target content to choose trust roots | medium | critical | bootstrap pins from trusted signed baseline, create detached CMS manifest externally and publish signed assets from signing environment | Release Owner / Signing Operator | external-open |

## Risk Review Rules
- Repository P0/P1 blockers must be zero before repository acceptance/delivery.
- External commercial gates are not converted into fake repository test passes.
- Every external-open risk must retain evidence outside the immutable candidate where the release contracts require independent retention.
- Commercial GO requires all eight `remaining_external_gates` in `16-current-status.json` to be satisfied against the same immutable candidate.
- Any change to source, EXE/PCK identity, qualification contract, publisher identity or trust pins invalidates the affected downstream evidence and requires requalification.
