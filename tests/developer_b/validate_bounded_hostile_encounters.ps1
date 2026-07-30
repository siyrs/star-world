$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = [ordered]@{
  Data = Join-Path $root 'data\hostile_encounters.json'
  Registry = Join-Path $root 'src\entity\hostile_encounter_registry.gd'
  Policy = Join-Path $root 'src\entity\hostile_encounter_policy.gd'
  Director = Join-Path $root 'src\entity\hostile_encounter_director.gd'
  Overlay = Join-Path $root 'src\ui\hostile_encounter_overlay.gd'
  Scene = Join-Path $root 'scenes\ui\service_hub.tscn'
  Headless = Join-Path $root 'tests\qa\hostile_encounter_director_regression.gd'
  Desktop = Join-Path $root 'tests\qa\hostile_encounter_director_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\bounded-hostile-encounter-director-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
  Contract = Join-Path $root 'docs\BOUNDED_HOSTILE_ENCOUNTER_DIRECTOR.md'
  Testing = Join-Path $root 'docs\BOUNDED_HOSTILE_ENCOUNTER_DIRECTOR_TESTING.md'
  Audit = Join-Path $root 'docs\ARCHITECTURE_AUDIT_2026-07-30_ITERATION_55.md'
  Roadmap = Join-Path $root 'docs\PRODUCT_ROADMAP_ITERATION_55.md'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Hostile encounter director file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  if ($entry.Key -ne 'Data') {
    $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
  }
}

$data = Get-Content -Raw -Encoding UTF8 $paths.Data | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) { throw 'Hostile encounter schema must begin at version 1' }
$profiles = @($data.profiles)
if ($profiles.Count -ne 3) { throw "Hostile encounter release must contain exactly 3 profiles; actual=$($profiles.Count)" }
$profileIds = @{}
foreach ($profile in $profiles) {
  $id = [string]$profile.id
  if ([string]::IsNullOrWhiteSpace($id) -or $profileIds.ContainsKey($id)) { throw "Duplicate/empty encounter profile: $id" }
  $profileIds[$id] = $true
  $members = @($profile.members)
  $memberCount = 0
  foreach ($member in $members) {
    if ([string]$member.role -notin @('vanguard','support','finisher')) { throw "Invalid encounter role: $id/$($member.role)" }
    if ([string]$member.species_id -notin @('zombie','abyss_marksman','abyss_brute')) { throw "Invalid encounter species: $id/$($member.species_id)" }
    $memberCount += [int]$member.count
  }
  if ($memberCount -lt 2 -or $memberCount -gt 5) { throw "Encounter member count must be 2..5: $id/$memberCount" }
  if ([double]$profile.maximum_total_pressure -gt 8.0) { throw "Encounter pressure exceeds hard budget: $id" }
  if ([double]$profile.maximum_spawn_radius -gt 36.0) { throw "Encounter radius exceeds hard budget: $id" }
}
foreach ($required in @('abyss_skirmish','abyss_assault','continent_night_patrol')) {
  if (-not $profileIds.ContainsKey($required)) { throw "Missing encounter profile: $required" }
}

foreach ($token in @(
  'class_name\s+HostileEncounterRegistry','MAX_PROFILES\s*:=\s*16',
  'MAX_MEMBERS_PER_ENCOUNTER\s*:=\s*5','MAX_TOTAL_PRESSURE\s*:=\s*8\.0',
  'var\s+staged:\s*Dictionary','_profiles\s*=\s*staged','get_validation_errors'
)) {
  if ($text.Registry -notmatch $token) { throw "Atomic encounter registry is missing: $token" }
}
if ($text.Registry -match 'extends\s+Node|Timer\.new|Thread\.new|save_world|serialize\s*\(') {
  throw 'Encounter registry must remain pure, atomic and non-persistent'
}
foreach ($token in @(
  'class_name\s+HostileEncounterPolicy','MAX_ACTIVE_ENCOUNTERS\s*:=\s*2',
  'MAX_TRACKED_MEMBERS\s*:=\s*12','LOW_HEALTH_SUPPRESSION_RATIO\s*:=\s*0\.35',
  'select_profile','is_profile_eligible','formation_requests','estimate_pressure'
)) {
  if ($text.Policy -notmatch $token) { throw "Pure encounter policy is missing: $token" }
}
if ($text.Policy -match 'extends\s+Node|FileAccess|DirAccess|Timer\.new|Thread\.new|RandomNumberGenerator') {
  throw 'Encounter policy must remain pure and deterministic'
}
foreach ($token in @(
  'class_name\s+HostileEncounterDirector','DECISION_INTERVAL_SECONDS\s*:=\s*1\.0',
  'MAX_SPAWN_ATTEMPTS_PER_DECISION\s*:=\s*1','WeakRef','spawn_transaction_failed',
  'world_changed','_population_snapshot','_rollback_spawned','HostileEncounterOverlay'
)) {
  if ($text.Director -notmatch $token) { throw "Bounded encounter director is missing: $token" }
}
if ($text.Director -match 'Timer\.new|Thread\.new|get_nodes_in_group|current_state\["hostile_encounter|save_world|serialize\s*\(') {
  throw 'Encounter director must use one bounded process without a parallel save domain or global scans'
}
if (($text.Scene | Select-String -Pattern 'HostileEncounterDirector' -AllMatches).Matches.Count -ne 1) {
  throw 'Service composition must install exactly one HostileEncounterDirector'
}
foreach ($token in @('HostileEncounterPanel','剩余 %d/%d','生命过低','pressure_ratio','set_blocked')) {
  if ($text.Overlay -notmatch [regex]::Escape($token)) { throw "Encounter HUD is missing: $token" }
}
foreach ($phrase in @(
  'invalid encounter profile rejects the entire staged registry',
  'low health suppresses new hostile encounters',
  'abyss assault creates exactly four role-aware members',
  'sixty minute planner simulation never exceeds encounter budgets',
  'world clear removes every tracked encounter member'
)) {
  if ($text.Headless -notmatch [regex]::Escape($phrase)) { throw "Encounter headless regression is missing: $phrase" }
}
foreach ($phrase in @(
  'production director starts the abyss assault through the real spawner',
  'encounter HUD renders the active mixed-role squad',
  'real mouse firearm defeats one encounter member',
  'completed encounter leaves no tracked runtime members',
  'hostile encounter state does not enter world.json'
)) {
  if ($text.Desktop -notmatch [regex]::Escape($phrase)) { throw "Encounter desktop acceptance is missing: $phrase" }
}
foreach ($token in @(
  'uses:\s*\./\.github/workflows/reusable-godot-quality-gate\.yml',
  'validate_bounded_hostile_encounters\.ps1','hostile_encounter_director_regression\.gd',
  'hostile_encounter_director_desktop_acceptance\.gd','hostile-encounter-active\.png',
  'hostile-encounter-complete\.png','hostile-encounter-report\.json'
)) {
  if ($text.Workflow -notmatch $token) { throw "Encounter workflow is missing: $token" }
}
foreach ($token in @('validate_bounded_hostile_encounters\.ps1','hostile_encounter_director_regression\.gd')) {
  if ($text.RunAll -notmatch $token) { throw "Full regression entry is missing encounter gate: $token" }
}
foreach ($concept in @('危险预算','原子','低血量','角色','WeakRef','不进入存档','60 分钟','Windows Release')) {
  if (($text.Contract + $text.Testing + $text.Audit + $text.Roadmap) -notmatch [regex]::Escape($concept)) {
    throw "Encounter documentation is missing concept: $concept"
  }
}
Write-Host "PASS bounded hostile encounters profiles=$($profiles.Count) members<=5 pressure<=8 active<=2 tracked<=12"
