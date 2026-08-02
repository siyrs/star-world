## ADDED Requirements

### Requirement: Manual-governed release completion
The commercial-release-quality-polish change SHALL use the user-provided commercial release manual at `C:\Users\sirius\.codex\attachments\24964602-687b-47e6-9db7-e68b02bb5711\pasted-text.txt` as its authoritative acceptance contract. A green smoke, test suite, or partial map visit SHALL NOT by itself mark the proposal or release as complete.

#### Scenario: A partial verification is green
- **WHEN** a focused smoke or regression passes while map, content, persistence, performance, or final-report gates remain incomplete
- **THEN** the change SHALL remain in progress and record the exact remaining gate

### Requirement: Evidence-backed end-to-end release loop
The release process SHALL repeatedly build, launch, operate, inspect, repair, rebuild, and regression-test the real project until the manual's release gates are met or an actual external blocker is evidenced.

#### Scenario: A player-visible defect is found
- **WHEN** exploration or automated operation finds a player-visible defect
- **THEN** the record SHALL contain reproduction evidence, root cause, scoped fix, focused regression, and the final QA state

### Requirement: Complete release acceptance record
Before this change is marked complete, the repository SHALL contain a current map coverage matrix, issue register, performance comparison, regression evidence, session state, final release report, independent-branch commit list, and the manual's delivery fields.

#### Scenario: Release readiness is reviewed
- **WHEN** the release recommendation is prepared
- **THEN** it SHALL report each formal map, content coverage, P0/P1 status, performance/long-run evidence, remaining risks, and the final publish recommendation

### Requirement: Design-accurate completion claims
For each world, the acceptance record SHALL distinguish a completed designed win/ending from an acceptance journey. If the product has no quest, ending, portal, or map-completion design, the record SHALL label it as not designed and SHALL not fabricate completion through direct state mutation.

#### Scenario: A profile has no designed completion condition
- **WHEN** source and runtime discovery confirm a profile has no implemented completion/settlement condition
- **THEN** the matrix SHALL mark traditional completion as not applicable and require the full profile acceptance journey instead
