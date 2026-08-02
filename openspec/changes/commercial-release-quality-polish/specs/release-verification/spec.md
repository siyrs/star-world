## ADDED Requirements

### Requirement: Fresh Windows release evidence
The release verification workflow SHALL export the current commit to an isolated output directory, record EXE/PCK hashes and timestamps, launch the exported executable, collect stdout/stderr and screenshots, and fail on fatal runtime logs.

#### Scenario: Successful fresh export smoke
- **WHEN** the documented Windows release-smoke command is run against Godot 4.7
- **THEN** it produces an isolated EXE/PCK pair, identity metadata, lifecycle evidence, and an explicit pass/fail result

#### Scenario: Old artifact is present
- **WHEN** a pre-existing build artifact predates the current commit
- **THEN** release acceptance SHALL not use it as evidence for the current commit

### Requirement: Portable documented smoke entry point
The documented smoke command SHALL either run under Windows PowerShell 5.1 and PowerShell 7 or fail before export with a precise version prerequisite and an actionable replacement command.

#### Scenario: Windows PowerShell compatibility
- **WHEN** the documented command is invoked from Windows PowerShell 5.1
- **THEN** it SHALL not fail from unavailable ProcessStartInfo APIs

### Requirement: Shipping package boundary
The Windows export SHALL exclude QA screenshots, reports, logs, and other `build/` evidence resources while retaining required runtime assets.

#### Scenario: Export package inspection
- **WHEN** a fresh export is produced after QA evidence exists in `build/`
- **THEN** the export log and package inspection SHALL show no `res://build/` evidence resources
