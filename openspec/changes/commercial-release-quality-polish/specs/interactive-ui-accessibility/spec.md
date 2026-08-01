## ADDED Requirements

### Requirement: Interactive UI contrast
Every enabled text-bearing Button, SecondaryButton, PrimaryButton, MenuPrimaryButton, CardButton, SelectedCardButton, GhostButton, and DangerButton variation SHALL maintain a computed contrast ratio of at least 4.5:1 in normal, hover, pressed, and focus states.

#### Scenario: Primary map action is hovered
- **WHEN** the player hovers the map creation action
- **THEN** its effective foreground/background contrast SHALL be at least 4.5:1

#### Scenario: Disabled state is displayed
- **WHEN** a disabled control is rendered
- **THEN** it SHALL be visually distinguishable and SHALL not be counted as an enabled-state contrast pass

### Requirement: Desktop UI evidence contract
The production-scene visual acceptance flow SHALL emit the caller-requested primary screenshot, ten named screenshots, and a JSON report describing the captures.

#### Scenario: Desktop runner receives a requested output path
- **WHEN** the desktop acceptance runner invokes the visual flow with an OutputPath
- **THEN** the exact primary screenshot and all named capture evidence SHALL exist before the runner reports success

### Requirement: Viewport-safe interaction
Map selection and settings SHALL remain usable without permanent overlap or clipping at 1280x720 and 1024x576.

#### Scenario: Narrow desktop settings view
- **WHEN** settings are opened at 1024x576
- **THEN** the action bar, return action, and scrollable controls SHALL remain reachable and non-overlapping
