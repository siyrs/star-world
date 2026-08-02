## ADDED Requirements

### Requirement: Deterministic safe new-world spawning
New worlds SHALL choose a deterministic, hard-safe spawn for the selected profile and seed, with valid support, body clearance, navigable local space, and a readable forward view.

#### Scenario: Reproduced Star Continent seed
- **WHEN** a Star Continent world is created with seed 24681357
- **THEN** the player SHALL not spawn against a tree trunk or low canopy and the assessment SHALL report hard-safe success

### Requirement: Bounded spawn assessment
Spawn candidate search SHALL have an unconditional candidate-work budget, emit scanned/evaluated/termination/elapsed metrics, and select a fallback only from hard-safe candidates.

#### Scenario: Quality threshold is not met early
- **WHEN** early candidates do not meet the preferred score
- **THEN** the search SHALL stop at its configured work budget and SHALL not scan an unbounded radius

### Requirement: Existing saves retain their positions
Loading an existing valid save SHALL use the saved/resolver position rules and SHALL not apply new-world lateral spawn scoring to relocate the player.

#### Scenario: Existing world is loaded
- **WHEN** an existing world with a valid player position is resumed
- **THEN** its position and orientation SHALL be preserved
