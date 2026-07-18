$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path "$PSScriptRoot\..\.."
$itemPath = Join-Path $projectRoot 'data\items.json'
$mapPath = Join-Path $projectRoot 'data\map_profiles.json'
$journalPath = Join-Path $projectRoot 'data\exploration_journal.json'
$rewardPath = Join-Path $projectRoot 'data\exploration_milestone_rewards.json'
$inventoryPath = Join-Path $projectRoot 'src\inventory\inventory_service.gd'
$migrationPath = Join-Path $projectRoot 'src\exploration\exploration_reward_state_migration.gd'

$itemData = Get-Content -Raw -Encoding UTF8 $itemPath | ConvertFrom-Json
$mapData = Get-Content -Raw -Encoding UTF8 $mapPath | ConvertFrom-Json
$journalData = Get-Content -Raw -Encoding UTF8 $journalPath | ConvertFrom-Json
$rewardData = Get-Content -Raw -Encoding UTF8 $rewardPath | ConvertFrom-Json

if ([int]$rewardData.schema_version -ne 1) { throw 'Exploration reward schema_version must equal 1' }

$itemIds = @{}
foreach ($item in @($itemData.items)) {
  $itemId = [string]$item.id
  if (-not [string]::IsNullOrWhiteSpace($itemId)) { $itemIds[$itemId] = $true }
}
$mapIds = @{}
foreach ($map in @($mapData.maps)) {
  $mapId = [string]$map.id
  if (-not [string]::IsNullOrWhiteSpace($mapId)) { $mapIds[$mapId] = $true }
}
$milestoneIds = @{}
foreach ($milestone in @($journalData.milestones)) {
  $milestoneId = [string]$milestone.id
  if ([string]::IsNullOrWhiteSpace($milestoneId)) { throw 'Journal milestone id is empty' }
  if ($milestoneIds.ContainsKey($milestoneId)) { throw "Duplicate journal milestone: $milestoneId" }
  $milestoneIds[$milestoneId] = $true
}

$rewardIds = @{}
$firstProfileIds = @{}
foreach ($reward in @($rewardData.rewards)) {
  $milestoneId = [string]$reward.milestone_id
  if ([string]::IsNullOrWhiteSpace($milestoneId)) { throw 'Reward milestone_id is empty' }
  if ($rewardIds.ContainsKey($milestoneId)) { throw "Duplicate milestone reward: $milestoneId" }
  if (-not $milestoneIds.ContainsKey($milestoneId)) { throw "Reward references unknown milestone: $milestoneId" }
  if ([string]::IsNullOrWhiteSpace([string]$reward.description)) { throw "Reward description is empty: $milestoneId" }
  $rewardIds[$milestoneId] = $true
  $items = @($reward.items)
  if ($items.Count -lt 1) { throw "Reward has no items: $milestoneId" }
  foreach ($item in $items) {
    $itemId = [string]$item.item_id
    $count = [int]$item.count
    if (-not $itemIds.ContainsKey($itemId)) { throw "Reward $milestoneId references unknown item: $itemId" }
    if ($count -lt 1 -or $count -gt 256) { throw "Reward $milestoneId has invalid count for ${itemId}: $count" }
  }
  if ($null -ne $reward.profile_bonus) {
    foreach ($property in $reward.profile_bonus.PSObject.Properties) {
      $profileId = [string]$property.Name
      if (-not $mapIds.ContainsKey($profileId)) { throw "Reward $milestoneId has unknown profile bonus: $profileId" }
      $bonusItems = @($property.Value)
      if ($bonusItems.Count -lt 1) { throw "Reward $milestoneId has empty profile bonus: $profileId" }
      foreach ($item in $bonusItems) {
        $itemId = [string]$item.item_id
        $count = [int]$item.count
        if (-not $itemIds.ContainsKey($itemId)) { throw "Profile bonus $milestoneId/$profileId references unknown item: $itemId" }
        if ($count -lt 1 -or $count -gt 256) { throw "Profile bonus $milestoneId/$profileId has invalid count for ${itemId}: $count" }
      }
      if ($milestoneId -eq 'first_discovery') { $firstProfileIds[$profileId] = $true }
    }
  }
}

foreach ($milestoneId in $milestoneIds.Keys) {
  if (-not $rewardIds.ContainsKey($milestoneId)) { throw "Milestone has no reward transaction: $milestoneId" }
}
if ($rewardIds.Count -ne $milestoneIds.Count) { throw 'Reward and milestone counts must match exactly' }
foreach ($mapId in $mapIds.Keys) {
  if (-not $firstProfileIds.ContainsKey($mapId)) { throw "First discovery reward has no map-specific bonus: $mapId" }
}

$inventorySource = Get-Content -Raw -Encoding UTF8 $inventoryPath
if ($inventorySource -notmatch 'func\s+transact_items\s*\(') { throw 'InventoryService must expose transact_items' }
if ($inventorySource -notmatch 'inventory_transaction_policy\.gd') { throw 'InventoryService must use the transaction policy' }
$migrationSource = Get-Content -Raw -Encoding UTF8 $migrationPath
if ($migrationSource -notmatch 'const\s+VERSION\s*:=\s*1') { throw 'Exploration reward state version must equal 1' }

Write-Host "PASS exploration rewards=$($rewardIds.Count) maps=$($mapIds.Count) items=$($itemIds.Count)"
