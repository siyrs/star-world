$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$dataPath = Join-Path $root 'data\exploration_journal.json'
$mapPath = Join-Path $root 'data\map_profiles.json'
$overlayPath = Join-Path $root 'src\ui\game_ui_extension_overlay_ids.gd'
$inputPath = Join-Path $root 'src\input\gameplay_input_actions.gd'
$migrationPath = Join-Path $root 'src\exploration\prospecting_state_migration.gd'

$data = Get-Content -Raw -Encoding UTF8 $dataPath | ConvertFrom-Json
$maps = @((Get-Content -Raw -Encoding UTF8 $mapPath | ConvertFrom-Json).maps)
if ([int]$data.schema_version -ne 2) { throw "Unsupported exploration journal schema: $($data.schema_version)" }
if ([int]$data.max_visible_records -lt 1 -or [int]$data.max_visible_records -gt 64) {
  throw "Invalid exploration journal visible record budget: $($data.max_visible_records)"
}

$mapIds = @{}
foreach ($map in $maps) { $mapIds[[string]$map.id] = $true }
$milestones = @($data.milestones)
if ($milestones.Count -ne 8) { throw "Expected eight exploration milestones, got $($milestones.Count)" }
$allowedKinds = @('record_count','unique_chunks','depth_band','density','danger_tier','depth_band_count','profile_rule')
$allowedDepths = @('upper','middle','lower','deep')
$allowedDensities = @('sparse','normal','promising','rich')
$allowedDangers = @('safe','caution','dangerous','severe')
$ids = @{}
foreach ($milestone in $milestones) {
  $id = [string]$milestone.id
  if ([string]::IsNullOrWhiteSpace($id)) { throw 'Exploration milestone id is empty' }
  if ($ids.ContainsKey($id)) { throw "Duplicate exploration milestone: $id" }
  $ids[$id] = $true
  if ([string]::IsNullOrWhiteSpace([string]$milestone.name)) { throw "Milestone name is empty: $id" }
  if ([string]::IsNullOrWhiteSpace([string]$milestone.description)) { throw "Milestone description is empty: $id" }
  $kind = [string]$milestone.kind
  if ($kind -notin $allowedKinds) { throw "Unsupported milestone kind '$kind': $id" }
  if ($kind -in @('record_count','unique_chunks','depth_band_count')) {
    if ([int]$milestone.threshold -lt 1 -or [int]$milestone.threshold -gt 64) { throw "Invalid milestone threshold: $id" }
  }
  if ($kind -in @('depth_band','density') -and [string]::IsNullOrWhiteSpace([string]$milestone.value)) {
    throw "Milestone value is empty: $id"
  }
  if ($kind -eq 'danger_tier') {
    $dangerValues = @($milestone.values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($dangerValues.Count -lt 1) { throw "Danger milestone has no accepted tiers: $id" }
  }
  if ($kind -eq 'profile_rule') {
    $rules = $milestone.rules
    if ($null -eq $rules) { throw "Profile milestone has no rules: $id" }
    $seenProfiles = @{}
    foreach ($property in $rules.PSObject.Properties) {
      $profileId = [string]$property.Name
      if (-not $mapIds.ContainsKey($profileId)) { throw "Profile milestone has unknown map: $id/$profileId" }
      $rule = $property.Value
      $depths = @($rule.depth_band_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      $densities = @($rule.density_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      $dangers = @($rule.danger_tier_ids | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
      $minimumDanger = [int]$rule.minimum_danger_score
      foreach ($depth in $depths) { if ([string]$depth -notin $allowedDepths) { throw "Unknown profile milestone depth: $id/$profileId/$depth" } }
      foreach ($density in $densities) { if ([string]$density -notin $allowedDensities) { throw "Unknown profile milestone density: $id/$profileId/$density" } }
      foreach ($danger in $dangers) { if ([string]$danger -notin $allowedDangers) { throw "Unknown profile milestone danger: $id/$profileId/$danger" } }
      if ($depths.Count -eq 0 -and $densities.Count -eq 0 -and $dangers.Count -eq 0 -and $minimumDanger -le 0) {
        throw "Profile milestone rule has no conditions: $id/$profileId"
      }
      $seenProfiles[$profileId] = $true
    }
    foreach ($mapId in $mapIds.Keys) {
      if (-not $seenProfiles.ContainsKey($mapId)) { throw "Profile milestone has no rule for map: $id/$mapId" }
    }
  }
}
foreach ($required in @('first_discovery','three_regions','deep_delver','rich_signal','danger_scout','four_depths','seasoned_explorer','signature_finding')) {
  if (-not $ids.ContainsKey($required)) { throw "Missing required exploration milestone: $required" }
}

$overlayText = Get-Content -Raw -Encoding UTF8 $overlayPath
$repairMatch = [regex]::Match($overlayText, 'const\s+REPAIR\s*:=\s*(\d+)')
$journalMatch = [regex]::Match($overlayText, 'const\s+EXPLORATION_JOURNAL\s*:=\s*(\d+)')
if (-not $repairMatch.Success -or -not $journalMatch.Success) { throw 'Unable to parse extension overlay ids' }
$repairOverlay = [int]$repairMatch.Groups[1].Value
$journalOverlay = [int]$journalMatch.Groups[1].Value
if ($repairOverlay -le 6 -or $journalOverlay -le 6 -or $repairOverlay -eq $journalOverlay) {
  throw "Feature overlay ids must be unique and outside the base range: repair=$repairOverlay journal=$journalOverlay"
}

$inputText = Get-Content -Raw -Encoding UTF8 $inputPath
if ($inputText -notmatch 'TOGGLE_EXPLORATION_JOURNAL') { throw 'Exploration journal input action is missing' }
if ($inputText -notmatch 'TOGGLE_EXPLORATION_JOURNAL:\s*\[KEY_J\]') { throw 'Exploration journal must keep the J binding' }

$migrationText = Get-Content -Raw -Encoding UTF8 $migrationPath
$versionMatch = [regex]::Match($migrationText, 'const\s+VERSION\s*:=\s*(\d+)')
if (-not $versionMatch.Success -or [int]$versionMatch.Groups[1].Value -ne 3) { throw 'Exploration persistence must use migration version 3' }

Write-Host "PASS exploration_journal milestones=$($milestones.Count) maps=$($mapIds.Count) visible=$($data.max_visible_records) migration=3"
