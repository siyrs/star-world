$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$dataPath = Join-Path $root 'data\exploration_journal.json'
$overlayPath = Join-Path $root 'src\ui\game_ui_extension_overlay_ids.gd'
$inputPath = Join-Path $root 'src\input\gameplay_input_actions.gd'
$migrationPath = Join-Path $root 'src\exploration\prospecting_state_migration.gd'

$data = Get-Content -Raw -Encoding UTF8 $dataPath | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) { throw "Unsupported exploration journal schema: $($data.schema_version)" }
if ([int]$data.max_visible_records -lt 1 -or [int]$data.max_visible_records -gt 64) {
  throw "Invalid exploration journal visible record budget: $($data.max_visible_records)"
}

$milestones = @($data.milestones)
if ($milestones.Count -lt 6) { throw "Expected at least six exploration milestones, got $($milestones.Count)" }
$allowedKinds = @('record_count','unique_chunks','depth_band','density','danger_tier','depth_band_count')
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
    if ([int]$milestone.threshold -lt 1 -or [int]$milestone.threshold -gt 64) {
      throw "Invalid milestone threshold: $id"
    }
  }
  if ($kind -in @('depth_band','density') -and [string]::IsNullOrWhiteSpace([string]$milestone.value)) {
    throw "Milestone value is empty: $id"
  }
  if ($kind -eq 'danger_tier' -and @($milestone.values).Count -lt 1) {
    throw "Danger milestone has no accepted tiers: $id"
  }
}
foreach ($required in @('first_discovery','three_regions','deep_delver','rich_signal','danger_scout','four_depths','seasoned_explorer')) {
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
if (-not $versionMatch.Success -or [int]$versionMatch.Groups[1].Value -ne 3) {
  throw 'Exploration persistence must use migration version 3'
}

Write-Host "PASS exploration_journal milestones=$($milestones.Count) visible=$($data.max_visible_records) overlays=$repairOverlay,$journalOverlay migration=3"
