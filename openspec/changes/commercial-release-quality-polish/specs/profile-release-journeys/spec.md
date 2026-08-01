## ADDED Requirements

### Requirement: Normal-entry profile acceptance journeys
Each production profile SHALL be tested from the main menu using a fixed seed and isolated QA world, then cover movement, interaction, a chunk seam, save/return/continue, death/respawn, and repeat entry.

#### Scenario: A profile is accepted
- **WHEN** a profile journey is marked accepted
- **THEN** its normal menu entry, persistence, recovery, logs, screenshots, and profile-specific probes SHALL have passed

### Requirement: Profile-specific hazard coverage
The release journey SHALL exercise Star Continent river water, Frozen Wastes ice-underwater recovery, Sky Islands fall recovery, and Abyss lava/deep-cave behavior; Desert Ruins SHALL cover ruins and underground ore traversal.

#### Scenario: Sky Islands fall recovery
- **WHEN** the player falls beyond the safe world height on Sky Islands
- **THEN** recovery SHALL return the player to a safe playable state

### Requirement: User data isolation
All destructive, malformed-save, or long-running QA flows SHALL use unique QA worlds or isolated application data and SHALL verify the user-world manifest before and after execution.

#### Scenario: QA journey cleanup
- **WHEN** a profile journey ends
- **THEN** its QA world SHALL be cleaned or explicitly retained as evidence without changing existing user worlds
