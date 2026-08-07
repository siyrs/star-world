# Product Roadmap · Iteration 66 · Five-Map Weather & Climate

Date: 2026-08-07

## Decision

Iteration 65 closed the v1.3.0 task-workspace governance drift and confirmed that the original eleven repository-owned commercial-polish function points are complete. A new repository audit then reviewed the remaining product gaps rather than fabricating completion of the external hardware/signing gates.

The largest missing core sandbox-survival layer is weather: the game already has five distinct maps, deterministic terrain, day/night, survival hunger, water/lava, ecology and map-specific danger, but no map-specific weather or persistent climate state.

Iteration 66 adds that layer as a complete closed loop. It does **not** change the existing commercial-release HOLD decision or claim that external qualification has been executed.

## Scope

1. Add a strict data registry for exactly five production map climates.
2. Provide clear baselines and map-signature weather states: rain/thunderstorm, sandstorm, snow/blizzard, cloudburst/high wind, ashfall/void mist.
3. Select future states and durations deterministically from map ID, world seed and transition index without a mutable global RNG.
4. Persist current weather, remaining duration and transition identity through the existing `world.json` transaction.
5. Migrate old worlds that have no weather domain without modifying existing player/world data.
6. Add bounded hazardous-weather exhaustion through `SurvivalService.add_exhaustion()`; no direct health/hunger writes.
7. Keep `DayNightService` as the single owner of sun, sky, cloud and fog presentation while accepting normalized weather modifiers.
8. Add a compact WeatherStatusBadge and transition notifications through the existing GameUI feedback path.
9. Integrate Weather as the eighth FeatureLifecycle participant immediately before Autosave, preserving reverse cleanup safety.
10. Extend existing lifecycle regression from seven to eight production participants and prove weather persistence/reload/clear.
11. Add headless deterministic/persistence/survival/environment regression.
12. Add real desktop weather rendering/HUD acceptance evidence.
13. Compose the weather gate with the complete Iteration 65 repository regression.
14. Re-export and run the Windows Release after all domain/full-suite gates pass.

## Acceptance

Iteration 66 is accepted only if:

- the profile JSON contains exactly the five formal maps and passes strict bounds;
- every map has a clear baseline and at least one distinct climate state;
- identical `(map, seed, transition_index)` inputs produce identical state and duration;
- weather runtime work remains bounded independently of world/Chunk size;
- a hazardous weather state consumes survival reserves only through the existing exhaustion API;
- weather state and remaining duration survive save/reload;
- old worlds without a weather key normalize and open successfully;
- DayNight remains the environment writer and weather modifiers do not create cumulative lighting drift;
- production FeatureLifecycle exposes eight participants and clears Autosave before Weather;
- the weather HUD is visible and communicates the active climate/survival pressure;
- strict Godot 4.7 import passes;
- weather headless regression passes;
- existing ServiceHub lifecycle regression passes after the eight-participant update;
- real desktop sandstorm acceptance writes valid screenshot evidence;
- the complete prior repository regression passes;
- final Windows Release export/start smoke passes;
- final PR head is reviewed with no unresolved blocking thread before merge to `master`.

## Non-goals

Iteration 66 deliberately does not add lightning damage, wind physics, shelter raycasts, biome scanning, precipitation collision, a second clock, per-block weather timers or another save sidecar. Those additions require separate evidence that they improve gameplay enough to justify their runtime and persistence cost.

## Commercial boundary

The v1.3.0 repository-owned task remains delivered. Commercial release remains **HOLD** on the same eight real external qualification/signing/bootstrap gates recorded in the canonical task contract. Weather CI cannot and must not satisfy those external controls.
