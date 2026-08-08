# Architecture Audit · Iteration 66 · Five-Map Weather & Climate

Date: 2026-08-07

## Audit question

Can Star World add persistent, visibly distinct weather to all five production maps without introducing a parallel world clock, duplicated environment ownership, unbounded world scans, a second persistence domain or lifecycle ordering regressions?

## Findings

### 1. Day/night already owns the environment

`DayNightService` already owns sun rotation/energy, procedural sky, procedural cloud layer and depth fog. A separate weather renderer that writes the same values each frame would create ordering-sensitive cumulative drift.

Decision: keep `DayNightService` as the sole environment writer. Weather sends normalized modifiers through one `set_weather_profile()` port. Weather changes invalidate the sky cache once; normal day/night processing remains authoritative afterwards.

### 2. Weather is world state, not UI state

Current climate and its remaining duration affect survival and must survive restart. Storing those values in HUD/GameUI would make reload behavior dependent on presentation lifetime.

Decision: `WeatherService` is the single state owner and `WeatherRuntimeParticipant` writes only one additive `weather` object into the existing `world.json` transaction.

### 3. A mutable RNG would make reload continuation ambiguous

If weather used a process-global `RandomNumberGenerator`, saving only the visible state would not prove which future sequence follows after reload.

Decision: state and duration derive deterministically from `map_id + world_seed + transition_index`. Persisting the transition index is sufficient to reproduce the future sequence without storing hidden RNG state.

### 4. Weather cost must not scale with world size

A weather feature does not justify scanning columns, loaded Chunks, blocks or entities each frame.

Decision: the runtime owns only a small state machine. Profile count is five, states are capped at four per profile, transition work is capped at eight per explicit advance, and survival exposure applications are capped at twelve per advance. There is no world scan or weather-owned physics query.

### 5. Survival already has the correct authority

Directly decrementing hunger or health from WeatherService would bypass saturation, tuning, starvation and difficulty rules.

Decision: weather contributes only bounded exhaustion through `SurvivalService.add_exhaustion()`. SurvivalService remains authoritative for the actual reserve/hunger consequences.

### 6. The existing FeatureLifecycle should own integration

Adding more begin/save/clear overrides directly to the base GameplayServiceHub would increase inheritance fragility.

Decision: Weather is a normal FeatureLifecycle participant. It normalizes old state, begins the current world, contributes to the shared save/snapshot transaction and clears through the same reverse lifecycle used by machines, agriculture, husbandry, ranch and exploration.

### 7. Autosave teardown must still happen first

Weather is persistent gameplay state. An autosave callback must not race a weather teardown.

Decision: register Weather immediately before Autosave. The coordinator invokes cleanup in reverse registration order, so Autosave disables checkpoint activity before Weather clears its world state.

### 8. HUD extension should not enlarge the core GameUI contract

Changing the already-wide GameUI `setup()` signature only to pass one new read-only service would ripple across unrelated tests.

Decision: the weather participant installs a small `WeatherStatusBadge` child into GameUI. The badge subscribes to WeatherService signals and owns no gameplay state. Existing GameUI/HUD setup contracts remain compatible.

## Architecture

```text
data/weather_profiles.json
        │
        ▼
 WeatherRegistry
  strict bounds
  stable hash
        │
        ▼
 WeatherService  ───────────────► SurvivalService.add_exhaustion()
  map + seed                      (existing authority)
  state + duration
  transition index
        │
        ├──────── modifiers ─────► DayNightService
        │                         single sun/sky/cloud/fog writer
        │
        └──────── snapshot ──────► WeatherStatusBadge

 WeatherRuntimeParticipant
        │
        ├── normalize old worlds
        ├── begin / activate
        ├── save_into world.json
        ├── snapshot_into diagnostics
        └── reverse clear / shutdown

 FeatureLifecycle order
 machine → agriculture → husbandry → ranch → exploration → journal/reward
        → weather → autosave
 clear/shutdown executes in reverse
```

## Compatibility

- Existing world files without `weather` receive an empty migrated container and deterministic baseline on open.
- Existing `day_night` serialization is unchanged; weather has its own additive object.
- Existing SurvivalService save shape is unchanged.
- Existing GameUI setup signature is unchanged.
- Existing machine/agriculture/husbandry/exploration participant IDs and save domains remain unchanged.
- Weather does not alter deterministic terrain, Seed generation, block IDs or map profile IDs.

## Failure behavior

- Missing/invalid weather profile data causes WeatherService installation to fail instead of running an undefined climate.
- Unknown saved state or wrong-map weather state falls back to the deterministic clear baseline.
- Future unsupported weather save versions fail restoration and fall back to a safe baseline.
- Oversized explicit time advance is capped and transition/exposure loops have hard budgets.
- Clearing the world removes active weather modifiers from DayNight and hides the HUD badge.

## Security and release boundary

Weather adds no network requests, executable loading, credentials or updater trust. The publisher-pinned update and distribution-signing chains from Iterations 63-64 remain unchanged. Commercial HOLD remains governed by real external evidence, not by this gameplay iteration.

## Conclusion

Weather is justified as the next gameplay iteration because it fills a visible sandbox-survival gap while reusing existing state, survival, environment, lifecycle, save, UI and release contracts. The selected architecture keeps the feature deterministic, bounded and additive rather than creating another parallel runtime subsystem.
