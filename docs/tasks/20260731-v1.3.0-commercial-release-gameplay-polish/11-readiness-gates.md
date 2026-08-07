# Readiness Gates

This file records gates that must pass before implementation starts.

Allowed `Result` values:

- `yes`: gate item passed.
- `no`: gate item is not passed yet.
- `not-needed`: gate item is intentionally skipped; `Notes` must include the rationale.
- `blocked`: gate item is blocked and implementation must not start.

Do not use `unknown`. Resolve all questions before setting `Implementation may start: yes`.

## Gate 0: PM-led Agent Roster

| Item | Result | Owner | Notes |
|---|---|---|---|
| Product Manager agent active first | yes | PM | Main agent 先启动唯一 PM |
| Main agent only interacts with PM | yes | PM | Team Delivery 通信边界已建立 |
| Main agent delegated roster decisions to PM | yes | PM | PM 自主决定最小分阶段名单 |
| Specialist agents report only to PM | yes | PM | Handoff Packet 强制该边界 |
| Active agents recorded | yes | PM | PM 与 Analyst 已记录 |
| Skipped agents recorded with rationale | yes | PM | Architect/Developer/QA/Coordinator 当前阶段理由已记录 |
| Each active agent has one responsibility | yes | PM | PM 管理门禁；Analyst 只读发现 |
| Each active agent has expected output and exit condition | yes | PM | 见 10-collaboration-log.md |
| Real agent tooling used or fallback recorded | yes | PM | 使用真实 sub-agent |

## Gate 1: Discovery / Analysis

| Item | Result | Owner | Notes |
|---|---|---|---|
| Analyst needed | yes | PM | 内容、地图、构建和既有 QA 断点规模未知，需只读发现 |
| Evidence gathered or skip rationale documented | yes | Analyst | A-001 完整发现包：5 地图、内容、水域、存档、测试、性能 |
| Analysis questions resolved | yes | PM | 无开放需求问题；运行未知转为测试项 |

## Gate 2: Architecture Review

| Item | Result | Owner | Notes |
|---|---|---|---|
| Architecture impact triaged | yes | PM | 现阶段沿用现有 src/scenes/data 与 tests/tools/qa 隔离边界 |
| Architect needed | not-needed | PM | 尚无已确认的跨系统 API/迁移决策；发现具体架构风险再激活 |
| Architecture guidance or no-impact rationale documented | yes | PM | 见 02-development-plan.md |
| Technical constraints documented when needed | yes | PM | 存档兼容、测试隔离、fresh artifact、禁止伪造通过 |
| Risks and alternatives documented when needed | yes | PM | 见 02-development-plan.md 与 15-risk-register.md |
| Architecture questions resolved | yes | PM | 当前无未决架构问题 |

## Gate 3: Feasibility

| Item | Result | Owner | Notes |
|---|---|---|---|
| Developer needed | yes | PM | 用户要求真实修复、自测和回归 |
| Can implement | yes | Developer when active | D-001 四项均可修；UI/出生/runner/packaging 有最小工作包 |
| Difficulty | yes | Developer when active | high；五地图/性能/长稳多阶段 |
| Rough effort | yes | Developer when active | 首批门禁约 1 个工作日；性能结构改造由数据触发 |
| Risks | yes | Developer when active | 参数转义、存档/玩法回归、性能阈值伪通过和 QA 资源入包已记录 |
| Concrete implementation plan or PM no-developer rationale | yes | PM or Developer | D-001 + PM 优先级见 02-development-plan.md |
| Need user confirmation | not-needed | PM | 用户已在 2026-07-31 请求中明确授权实施，无需重复询问 |

## Gate 4: Test Strategy

| Item | Result | Owner | Notes |
|---|---|---|---|
| QA Tester needed | yes | PM | 商业发布任务必须独立验证并对 QA 报告的 bug 执行重测 |
| Test strategy owner assigned | yes | PM | QA Tester；Packet QA-001 |
| Test scope | yes | PM or QA | QA-001 已复核 TC-001..020、五地图沙盒旅程、水/熔岩、存档、性能和发布边界 |
| Concrete test cases or PM acceptance checklist | yes | PM or QA | 五地图正常菜单入口旅程及专项/极端/重测规则已明确 |
| Test data | yes | PM or QA | 固定 Seed、唯一 QA 世界、用户 12 世界/设置/回收站前后 SHA-256 保护 |
| Environment | yes | PM or QA | Windows x64、Godot 4.7、GL Compatibility；执行时记录硬件/驱动/产物哈希 |
| Pass rule | yes | PM or QA | P0/P1 为 0；双证据层均通过；性能阈值与长稳规则见 QA-001/04-test-plan.md |
| Regression scope | yes | QA when active | 原用例、相邻流程、受影响地图、全量回归、fresh EXE 与 production-scene 分层 |
| Bugfix retest rule | yes | QA when active | QA 报告 bug 必须 Developer 修复+自测，再由同一 QA 用原用例和相邻回归重测 |

## Gate 5: Coordination

| Item | Result | Owner | Notes |
|---|---|---|---|
| Coordinator needed | not-needed | PM | PM 按 Analyst→Developer→QA 串行调度，当前无多工作流协调风险 |
| Handoffs documented or skip rationale recorded | yes | PM | Packet A-001、D-001、QA-001 均已落盘并完成准备阶段交付 |
| Cross-agent blockers routed | yes | PM | 所有 specialist 只向 PM 报告，PM 负责 Developer↔QA 循环 |

## Gate 6: PM Readiness Review

| Item | Result | Owner | Notes |
|---|---|---|---|
| Requirement reviewed | yes | PM | 01-product-requirement.md 已覆盖用户验收 |
| Agent roster reviewed | yes | PM | 采用 Analyst→Developer→QA 最小串行团队 |
| Specialist outputs reviewed | yes | PM | A-001、D-001、QA-001 已验收，无开放问题 |
| Developer plan or no-developer rationale reviewed | yes | PM | 首批 P1→发布门禁→性能/五地图实施顺序已确认 |
| Test strategy reviewed | yes | PM | QA-001 Gate 4 全 yes；双证据边界、性能阈值和重测规则确认 |
| Ready to ask user for implementation approval | yes | PM | readiness 完整；用户已在初始请求明确授权，无需重复询问 |

## Gate 7: User Confirmation

- Requirement confirmed: yes
- Agent roster confirmed: yes
- Architecture guidance or no-impact rationale confirmed: yes
- Development plan or no-developer rationale confirmed: yes
- Test plan or PM acceptance checklist confirmed: yes
- Implementation may start: yes
- Confirmed at: 2026-07-31 10:27 +08:00（用户在初始请求明确授权实施；PM 完成 A-001/D-001/QA-001 复审）

## Post-implementation reconciliation · Iteration 59 · 2026-08-06

The readiness decision remains historically valid, but implementation is no longer “not started.” Iterations 1-59 completed the repository-automatable gameplay, persistence, lifecycle and release-integrity scope.

## Post-implementation reconciliation · Iteration 60 · 2026-08-06

The repository now includes an auditable external-qualification kit:

- independent E4-H review recorder;
- exact-final-package minimum/recommended hardware collectors;
- strict 7,200-second wall-clock final-package soak harness;
- two-phase HDD, antivirus and power-loss experiment records;
- one commit/EXE/PCK-bound package assembler;
- fixture/hosted/target evidence separation and permanent anti-forgery CI.

Repository readiness is complete. External execution is intentionally not marked complete: independent human review, two real hardware tiers, the real target-hardware soak and all three physical fault experiments must still be performed. Commercial release remains **HOLD** until the assembled package validates as `external_evidence_complete`.


## Post-implementation reconciliation · Iterations 60-61

The repository now includes the Iteration 60 semantic evidence contract and the Iteration 61 candidate chain-of-custody workflow. Repository implementation, parser checks, strict Godot import, a complete 19-file portable reference payload, referenced-report revalidation, hidden-file detection and six deliberate tamper rejections are automatable and must remain green.

Commercial release remains **HOLD**. The independent E4-H review, minimum/recommended physical hardware runs, strict 7,200-second target-hardware soak, HDD/antivirus/power-loss experiments and release-owner approval remain external execution items and are not marked complete by CI.


## Post-implementation reconciliation · Iteration 62 · 2026-08-07

Repository-owned release promotion now adds an externally retained Promotion Pin, frozen release/project/export contract snapshots, offline nested-chain validation and immutable handoff receipts. `-RequireReleaseGate` must be paired with the expected pin ID so a different internally consistent candidate cannot be promoted accidentally.

Commercial release remains **HOLD**. Independent E4-H review, minimum/recommended physical hardware, the real 7,200-second target-hardware soak, HDD/antivirus/power-loss experiments, release-owner selection and any publisher signing/timestamp authority remain external execution controls.


## Post-implementation reconciliation · Iteration 63 · 2026-08-07

Repository-owned final distribution validation now requires sign-before-qualification, Windows Authenticode verification, an externally retained publisher-certificate SHA-256 and a trusted timestamp for the commercial gate. The Distribution Gate composes the Iteration 62 Promotion Pin with the exact qualified executable hash, and Distribution Receipts remain outside the immutable Promotion Bundle.

CI verifies a real trusted, timestamped Authenticode binary already present on the hosted Windows image and dynamically checks its signer-certificate SHA-256 and timestamp EKU. It does not create or use a Star World publisher key, and the Promotion fixture remains reference-only. Commercial release remains **HOLD** pending the real publisher certificate/private-key operation, trusted timestamp on the final Star World EXE, independent E4-H review, minimum/recommended physical hardware, real 7,200-second soak and physical HDD/antivirus/power-loss evidence.


## Post-implementation reconciliation · Iteration 64 · 2026-08-07

Repository-owned automatic update delivery now consumes the publisher trust introduced by Iteration 63. Schema/protocol 2 signs the exact payload Manifest with detached CMS, the staged EXE independently requires pinned Authenticode plus trusted timestamp, and all pins come from the currently installed version before the target package is promoted. The existing directory-swap/ACK/rollback transaction remains after this new pre-swap authentication gate.

Hosted CI no longer publishes unsigned public update assets; it produces reference-only evidence. Real Manifest signing, real certificate pins, first-baseline bootstrap and signed GitHub Release publication remain external release controls. Commercial release remains **HOLD** with the existing independent/physical qualification requirements.
