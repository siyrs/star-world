# Weather & Climate System

Iteration 66 adds a five-map, data-driven weather layer without creating a second world clock, environment writer, save authority or timer graph.

## Ownership

The weather domain has one **single state owner**: `WeatherService`.

- `WeatherRegistry` owns immutable profile validation and deterministic selection.
- `WeatherService` owns current state, remaining duration, transition identity and bounded survival exposure.
- `WeatherRuntimeParticipant` owns lifecycle integration and the `world.json` weather payload.
- `WeatherStatusBadge` owns the small gameplay HUD extension.
- `DayNightService` remains the only owner that writes sun, sky, cloud and fog presentation. Weather only supplies normalized modifiers through `set_weather_profile()`.

No weather value is written to `world.json` by UI code and no target system writes directly into WeatherService state.

## Five formal climates

`data/weather_profiles.json` contains exactly the five production map IDs:

| Map | Baseline | Signature weather |
|---|---|---|
| `star_continent` | clear | rain, thunderstorm |
| `desert_ruins` | clear | sandstorm |
| `frozen_wastes` | clear | snow, blizzard |
| `sky_islands` | clear | cloudburst, high wind |
| `abyss_world` | clear | ashfall, void mist |

Each profile is limited to four states. Durations, fog/light/cloud modifiers and exhaustion pressure have hard validation bounds.

## Deterministic transitions

Weather is deterministic for the tuple:

`map_id + world_seed + transition_index`

The registry uses its own stable integer hash and weighted state selection. It does not store or consume a mutable global RNG. The same world seed and transition index therefore select the same weather and duration after process restart or cross-machine transfer.

A world starts in its profile's clear baseline unless a compatible persisted state exists. Subsequent transitions use the deterministic weighted sequence.

## Persistence

Weather is an additive migrated domain inside the existing authoritative `world.json` transaction:

```json
{
  "weather": {
    "version": 1,
    "map_id": "frozen_wastes",
    "state_id": "snow",
    "remaining_seconds": 65.0,
    "transition_index": 4
  }
}
```

Older worlds without `weather` are normalized to an empty weather object by the lifecycle participant and receive a deterministic baseline when opened. Autosave and manual save use the same existing `SaveService.save_world()` transaction; weather never creates a sidecar or parallel persistence domain.

## Bounded runtime

The runtime is intentionally bounded:

- maximum four states per map profile;
- maximum eight weather transitions in one explicit `advance()` call;
- process delta capped to one second;
- explicit advance capped to 300 seconds;
- survival exposure sampled every five seconds;
- maximum twelve exposure applications per `advance()` call;
- exhaustion pressure capped at `0.5` per minute by the registry contract;
- no world scan, no per-block timer and no weather-owned physics query.

This makes weather cost independent of world size and loaded Chunk count.

## Survival integration

Hazardous weather contributes small, bounded exhaustion through the existing `SurvivalService.add_exhaustion()` API. It does not directly alter health, hunger internals or player inventory.

This preserves SurvivalService as the authority for saturation/hunger conversion, starvation, regeneration and death. Clear weather has zero exposure cost.

## Day/night composition

`DayNightService` remains the presentation authority. It combines normal time-of-day/map values with normalized weather modifiers for:

- sun energy and tint;
- ambient energy and tint;
- procedural sky energy/tint;
- depth-fog range;
- procedural cloud tint and opacity.

Weather changes invalidate the cached sky strength once, so visual changes appear immediately without dirtying the sky material unnecessarily every frame.

## UI

`WeatherStatusBadge` is a small GameUI child installed by the weather lifecycle participant. It shows the localized weather state, remaining duration and whether the current climate is applying environmental survival pressure. It does not own gameplay state.

Weather transitions also use the existing `GameUI.show_message()` path, preserving the project's bounded/deduplicated player feedback model.

## Lifecycle order

Weather is registered immediately before Autosave. The shared coordinator runs begin/attach/activate/save forward and clear/shutdown in reverse registration order. This guarantees Autosave stops first during teardown, then Weather releases its current world state, followed by the older gameplay domains.

## Verification

Iteration 66 permanently verifies:

- strict five-map registry validation;
- deterministic selection and duration;
- persistence/reload continuity;
- survival exhaustion through the public authority;
- DayNight-owned environment composition;
- eight-participant ServiceHub lifecycle and reverse cleanup;
- HUD state exposure;
- real desktop sandstorm rendering evidence;
- complete prior repository regression;
- final Windows Release export and smoke.
