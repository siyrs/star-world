$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$required = @(
    'data\weather_profiles.json',
    'src\weather\weather_registry.gd',
    'src\weather\weather_service.gd',
    'src\weather\weather_runtime_participant.gd',
    'src\weather\weather_status_badge.gd',
    'src\survival\day_night_service.gd',
    'src\ui\exploration_progression_service_hub.gd',
    'tests\qa\weather_climate_regression.gd',
    'tests\qa\weather_climate_desktop_acceptance.gd',
    'tests\qa\service_hub_feature_lifecycle_regression.gd',
    'tests\ci\run_iteration_66_full_regression.ps1',
    '.github\workflows\weather-climate-iteration-66-tests.yml',
    'docs\PRODUCT_ROADMAP.md',
    'docs\WEATHER_CLIMATE_SYSTEM.md',
    'docs\PRODUCT_ROADMAP_ITERATION_66.md',
    'docs\ARCHITECTURE_AUDIT_2026-08-07_ITERATION_66.md'
)
foreach ($relative in $required) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Iteration 66 file missing: $relative" }
}

function Read-Text([string]$RelativePath) {
    return Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $RelativePath)
}

function Assert-ContainsAll([string]$RelativePath, [string[]]$Tokens) {
    $text = Read-Text $RelativePath
    foreach ($token in $Tokens) {
        if (-not $text.Contains($token)) { throw "Iteration 66 token '$token' missing from $RelativePath" }
    }
}

$data = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\weather_profiles.json') | ConvertFrom-Json -Depth 20
if ([int]$data.schema_version -ne 1) { throw 'Weather profile schema_version must be 1.' }
$expectedMaps = @('star_continent','desert_ruins','frozen_wastes','sky_islands','abyss_world')
$profiles = @($data.profiles)
if ($profiles.Count -ne 5) { throw 'Weather registry must contain exactly five formal map profiles.' }
$allStateIds = [System.Collections.Generic.List[string]]::new()
foreach ($mapId in $expectedMaps) {
    $profile = @($profiles | Where-Object { [string]$_.id -eq $mapId })
    if ($profile.Count -ne 1) { throw "Weather profile missing or duplicated: $mapId" }
    $states = @($profile[0].states)
    if ($states.Count -lt 2 -or $states.Count -gt 4) { throw "Weather state count is not bounded for $mapId" }
    if (@($states | Where-Object { [string]$_.id -eq 'clear' }).Count -ne 1) { throw "Weather profile must retain clear baseline: $mapId" }
    foreach ($state in $states) {
        $allStateIds.Add([string]$state.id)
        if ([int]$state.weight -lt 1 -or [int]$state.weight -gt 1000) { throw "Weather weight out of bounds: $mapId/$($state.id)" }
        if ([int]$state.min_duration_seconds -lt 15 -or [int]$state.max_duration_seconds -gt 600 -or [int]$state.max_duration_seconds -lt [int]$state.min_duration_seconds) { throw "Weather duration out of bounds: $mapId/$($state.id)" }
        if ([double]$state.fog_multiplier -lt 0.5 -or [double]$state.fog_multiplier -gt 3.0) { throw "Weather fog multiplier out of bounds: $mapId/$($state.id)" }
        if ([double]$state.light_multiplier -lt 0.4 -or [double]$state.light_multiplier -gt 1.2) { throw "Weather light multiplier out of bounds: $mapId/$($state.id)" }
        if ([double]$state.cloud_opacity -lt 0.0 -or [double]$state.cloud_opacity -gt 1.0) { throw "Weather cloud opacity out of bounds: $mapId/$($state.id)" }
        if ([double]$state.exhaustion_per_minute -lt 0.0 -or [double]$state.exhaustion_per_minute -gt 0.5) { throw "Weather exhaustion out of bounds: $mapId/$($state.id)" }
    }
}
foreach ($hazard in @('thunderstorm','sandstorm','blizzard','high_wind','void_mist')) {
    if (-not $allStateIds.Contains($hazard)) { throw "Map-signature hazardous weather missing: $hazard" }
}

Assert-ContainsAll 'src\weather\weather_registry.gd' @(
    'MAX_STATES_PER_PROFILE := 4',
    'choose_state_id',
    'duration_for_state',
    '_stable_hash',
    'EXPECTED_MAP_IDS'
)
Assert-ContainsAll 'src\weather\weather_service.gd' @(
    'MAX_TRANSITIONS_PER_ADVANCE := 8',
    'MAX_EXPOSURE_APPLICATIONS_PER_ADVANCE := 12',
    'EXPOSURE_INTERVAL_SECONDS := 5.0',
    'func serialize()',
    'force_weather_state',
    'add_exhaustion',
    'remaining_seconds',
    'transition_index'
)
Assert-ContainsAll 'src\weather\weather_runtime_participant.gd' @(
    'normalize_world_state',
    'payload["weather"]',
    'snapshot["weather"]',
    'weather_transitioned',
    'WeatherStatusBadgeScript'
)
Assert-ContainsAll 'src\survival\day_night_service.gd' @(
    'func set_weather_profile',
    'func get_weather_environment_snapshot',
    '_weather_fog_multiplier',
    '_weather_light_multiplier',
    '_weather_cloud_opacity',
    '_weather_tint_color',
    '_weather_profile.get("cloud_opacity", 0.8)'
)
Assert-ContainsAll 'src\ui\exploration_progression_service_hub.gd' @(
    'WEATHER_RUNTIME_FEATURE := &"weather_runtime"',
    'WeatherRuntimeParticipantScript.new()',
    'var weather_service: Node',
    'snapshot["weather"] = get_weather_snapshot()',
    'weather_runtime_participant = _register_feature_participant'
)

$hubText = Read-Text 'src\ui\exploration_progression_service_hub.gd'
$weatherIndex = $hubText.IndexOf('weather_runtime_participant = _register_feature_participant')
$autosaveIndex = $hubText.IndexOf('autosave_runtime_participant = _register_feature_participant')
if ($weatherIndex -lt 0 -or $autosaveIndex -lt 0 -or $weatherIndex -gt $autosaveIndex) {
    throw 'Weather must register before autosave so reverse cleanup stops autosave first.'
}

Assert-ContainsAll 'tests\qa\service_hub_feature_lifecycle_regression.gd' @(
    'all eight lifecycle participants',
    '&"weather_runtime"',
    'loaded.has("weather")',
    'participant_count", 0',
    'autosave_runtime,weather_runtime,exploration_journal_rewards'
)
Assert-ContainsAll 'tests\qa\weather_climate_regression.gd' @(
    'five formal maps',
    'state survives save/reload',
    'survival exhaustion',
    'production service hub installs weather service',
    'weather participates in the production lifecycle',
    'pre-weather cloud opacity'
)
Assert-ContainsAll 'tests\qa\weather_climate_desktop_acceptance.gd' @(
    'state=sandstorm',
    'desktop HUD exposes active sandstorm',
    'real desktop fog hides distant geometry',
    'weather desktop screenshot is saved'
)
Assert-ContainsAll 'tests\ci\run_iteration_66_full_regression.ps1' @(
    'validate_weather_climate_iteration_66.ps1',
    '--editor --quit',
    'weather_climate_regression.gd',
    'run_iteration_65_full_regression.ps1',
    'iteration66-wrapper.log',
    'ITERATION 66 FULL REGRESSION PASS'
)
Assert-ContainsAll '.github\workflows\weather-climate-iteration-66-tests.yml' @(
    'docs/PRODUCT_ROADMAP.md',
    'Validate weather and climate contracts',
    'Run weather climate regression',
    'Run real weather desktop acceptance',
    'Run complete repository regression',
    'Export and run Windows release'
)
Assert-ContainsAll 'docs\PRODUCT_ROADMAP.md' @(
    'Eight Feature Lifecycle Participants',
    '`weather_runtime`',
    '`autosave_runtime`',
    'Iteration 66 · Five-Map Weather & Climate',
    '0.8` 云层 opacity 基线',
    'Commercial release：继续 **HOLD**'
)
Assert-ContainsAll 'docs\WEATHER_CLIMATE_SYSTEM.md' @(
    'single state owner',
    'deterministic',
    'world.json',
    'bounded',
    'DayNightService'
)

Write-Host 'ITERATION 66 WEATHER CLIMATE PASS | maps=5 | deterministic=true | states<=4 | transition-budget=8 | exposure-budget=12 | persistence=world.json | lifecycle=participant | hud=extension | daynight=single-owner | legacy-clouds=preserved | roadmap=reconciled | full-regression=strict-import'