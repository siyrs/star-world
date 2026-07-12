# Risk Register

| ID | Risk | Probability | Impact | Mitigation / Contingency | Owner | Status |
|---|---|---|---|---|---|---|
| R-001 | Godot not preinstalled | high | high | official 4.7 console and matching Windows templates installed outside repo; commands documented | DEV-C/Root | closed |
| R-002 | voxel draw/collision cost | medium | high | bounded render radius/height, exposed-face mesh, dirty rebuild and unload > render invariant | DEV-C/Root | mitigated |
| R-003 | parallel integration mismatch | medium | high | public contracts, fixed ownership and full integration regression | PM/Root | closed |
| R-004 | breadth exceeds commercial polish | high | medium | preserve every required loop with complete simplified systems and procedural assets | PM | accepted |
| R-005 | save schema drift | medium | high | schema version, defaults, deterministic seed + sparse overrides, round-trip QA | DEV-B/QA | mitigated |
| R-006 | QA bugfix regression | medium | high | focused fixes plus full 193-check regression and package retest | PM/QA/Root | closed |
