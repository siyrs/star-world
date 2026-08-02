## ADDED Requirements

### Requirement: Valid release-mode performance metrics
Release performance reports SHALL identify unavailable engine metrics as unavailable and SHALL collect Working Set and Private Bytes from the launched EXE PID with timestamps and units.

#### Scenario: Release memory metric is unavailable internally
- **WHEN** Godot release telemetry returns an invalid static-memory value
- **THEN** the report SHALL not present it as zero memory and SHALL include external process metrics or an explicit collection failure

### Requirement: Streaming convergence and pressure evidence
Performance smoke SHALL separately measure static chunk convergence and controlled movement pressure, with a fixed maximum wait and explicit pending/building values.

#### Scenario: Initial world is still streaming
- **WHEN** pending or building chunks remain above the defined health threshold after the maximum static wait
- **THEN** the health result SHALL be warning or failing rather than overall pass

### Requirement: Long-run release stability
Release readiness SHALL include an evidence-backed long-run fresh-EXE soak spanning all profiles, save/load/menu transitions, and valid memory/frametime trends.

#### Scenario: Soak run completes
- **WHEN** the required long-run soak ends
- **THEN** the report SHALL include duration, crashes, fatal logs, frame-time percentiles, memory trend, and any unavailable counter boundary
