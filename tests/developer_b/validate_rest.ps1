$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$rest = Get-Content -Raw -Encoding UTF8 "$root\data\rest.json" | ConvertFrom-Json
$items = @((Get-Content -Raw -Encoding UTF8 "$root\data\items.json" | ConvertFrom-Json).items)
$recipes = @((Get-Content -Raw -Encoding UTF8 "$root\data\recipes.json" | ConvertFrom-Json).recipes)
$harvestRules = @((Get-Content -Raw -Encoding UTF8 "$root\data\block_harvest.json" | ConvertFrom-Json).rules)

if ([int]$rest.schema_version -lt 1) { throw 'Rest schema version must be >= 1' }
$bedBlocks = @($rest.bed_blocks)
if ($bedBlocks.Count -lt 1) { throw 'Rest policy requires at least one bed block' }
if ('oak_bed' -notin $bedBlocks) { throw 'Rest policy must include oak_bed' }
if (@($bedBlocks | Select-Object -Unique).Count -ne $bedBlocks.Count) { throw 'Rest bed block ids must be unique' }

$window = $rest.sleep_window
foreach ($field in @('start_hour','end_hour','wake_hour')) {
  if ($null -eq $window.$field) { throw "Missing sleep window field: $field" }
  $value = [double]$window.$field
  if ($value -lt 0 -or $value -ge 24) { throw "Sleep window hour is out of range: $field=$value" }
}
if ([double]$window.start_hour -eq [double]$window.end_hour) { throw 'Sleep window must have a distinct start and end' }

$offsets = @($rest.spawn_offsets)
if ($offsets.Count -lt 5) { throw "Expected at least 5 respawn offsets, got $($offsets.Count)" }
$offsetKeys = @{}
foreach ($offset in $offsets) {
  $values = @($offset)
  if ($values.Count -ne 3) { throw 'Each respawn offset must contain exactly three integers' }
  $key = "{0},{1},{2}" -f [int]$values[0], [int]$values[1], [int]$values[2]
  if ($offsetKeys.ContainsKey($key)) { throw "Duplicate respawn offset: $key" }
  $offsetKeys[$key] = $true
}
$clearance = [int]$rest.required_clearance_blocks
if ($clearance -lt 2 -or $clearance -gt 4) { throw "Invalid respawn clearance: $clearance" }

$bedItem = $items | Where-Object { $_.id -eq 'oak_bed' } | Select-Object -First 1
if ($null -eq $bedItem) { throw 'Missing oak_bed item' }
if ([string]$bedItem.category -ne 'block') { throw 'oak_bed must be a block item' }
if ([string]$bedItem.block_id -ne 'oak_bed') { throw 'oak_bed item must place the oak_bed block' }
if ([int]$bedItem.max_stack -ne 1) { throw 'oak_bed must be non-stackable in the current interaction model' }

$bedRecipe = $recipes | Where-Object { $_.id -eq 'oak_bed' } | Select-Object -First 1
if ($null -eq $bedRecipe) { throw 'Missing oak_bed recipe' }
if ([string]$bedRecipe.station -ne 'workbench') { throw 'oak_bed must require a workbench' }
if ([int]$bedRecipe.ingredients.oak_planks -ne 3) { throw 'oak_bed recipe requires three planks' }
if ([int]$bedRecipe.ingredients.wool -ne 3) { throw 'oak_bed recipe requires three wool' }
if ([string]$bedRecipe.output.id -ne 'oak_bed' -or [int]$bedRecipe.output.count -ne 1) {
  throw 'oak_bed recipe output is invalid'
}

$bedHarvest = $harvestRules | Where-Object { $_.block_id -eq 'oak_bed' } | Select-Object -First 1
if ($null -eq $bedHarvest) { throw 'Missing oak_bed harvest rule' }
if ([string]$bedHarvest.preferred_tool -ne 'axe') { throw 'oak_bed should prefer an axe' }

Write-Host "PASS rest beds=$($bedBlocks.Count) offsets=$($offsets.Count) wake=$($window.wake_hour)"
