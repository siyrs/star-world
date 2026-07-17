$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$registryPath = Join-Path $root 'src\block\block_registry.gd'
$itemsPath = Join-Path $root 'data\items.json'
$harvestPath = Join-Path $root 'data\block_harvest.json'

$registryText = Get-Content -Raw -Encoding UTF8 $registryPath
$blockListMatch = [regex]::Match($registryText, '(?s)const BLOCK_IDS := \[(.*?)\]')
if (-not $blockListMatch.Success) { throw 'Unable to parse BlockRegistry.BLOCK_IDS' }
$knownBlocks = @([regex]::Matches($blockListMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object {
  $_.Groups[1].Value
})
$blockSet = @{}
foreach ($blockId in $knownBlocks) {
  if ($blockSet.ContainsKey($blockId)) { throw "Duplicate BlockRegistry.BLOCK_IDS entry: $blockId" }
  $blockSet[$blockId] = $true
}

$definitions = @{}
$definitionMatches = [regex]::Matches(
  $registryText,
  '(?m)^\s*"([^"]+)"\s*:\s*\{([^\r\n]+)\}\s*,?\s*$'
)
foreach ($match in $definitionMatches) {
  $blockId = $match.Groups[1].Value
  $body = $match.Groups[2].Value
  $itemMatch = [regex]::Match($body, '"item_id"\s*:\s*"([^"]*)"')
  $parentMatch = [regex]::Match($body, '"visual_parent"\s*:\s*"([^"]*)"')
  $familyMatch = [regex]::Match($body, '"orientation_family"\s*:\s*"([^"]*)"')
  $definitions[$blockId] = @{
    item_id = if ($itemMatch.Success) { $itemMatch.Groups[1].Value } else { '' }
    visual_parent = if ($parentMatch.Success) { $parentMatch.Groups[1].Value } else { '' }
    orientation_family = if ($familyMatch.Success) { $familyMatch.Groups[1].Value } else { '' }
  }
}
foreach ($blockId in $knownBlocks) {
  if (-not $definitions.ContainsKey($blockId)) { throw "Registered block has no definition: $blockId" }
}
foreach ($blockId in $definitions.Keys) {
  if (-not $blockSet.ContainsKey($blockId)) { throw "Block definition is missing from BLOCK_IDS: $blockId" }
  $parent = [string]$definitions[$blockId].visual_parent
  if (-not [string]::IsNullOrWhiteSpace($parent) -and -not $blockSet.ContainsKey($parent)) {
    throw "Block $blockId references unknown visual_parent $parent"
  }
  $family = [string]$definitions[$blockId].orientation_family
  if (-not [string]::IsNullOrWhiteSpace($family) -and -not $blockSet.ContainsKey($family)) {
    throw "Block $blockId references unknown orientation_family $family"
  }
}

$items = @((Get-Content -Raw -Encoding UTF8 $itemsPath | ConvertFrom-Json).items)
$itemSet = @{}
foreach ($item in $items) {
  $itemId = [string]$item.id
  if ($itemSet.ContainsKey($itemId)) { throw "Duplicate item id: $itemId" }
  $itemSet[$itemId] = $true
}
foreach ($blockId in $knownBlocks) {
  $itemId = [string]$definitions[$blockId].item_id
  if (-not [string]::IsNullOrWhiteSpace($itemId) -and -not $itemSet.ContainsKey($itemId)) {
    throw "Block $blockId drops or maps to unknown item $itemId"
  }
}
foreach ($item in $items) {
  if ([string]$item.category -ne 'block') { continue }
  $itemId = [string]$item.id
  $blockId = [string]$item.block_id
  if ([string]::IsNullOrWhiteSpace($blockId)) { throw "Block item has no block_id: $itemId" }
  if (-not $blockSet.ContainsKey($blockId)) { throw "Block item $itemId references unregistered block $blockId" }
  if ([string]$definitions[$blockId].item_id -ne $itemId) {
    throw "Block item $itemId does not round-trip through BlockRegistry definition $blockId"
  }
  $canonical = $null
  foreach ($candidate in $knownBlocks) {
    if ([string]$definitions[$candidate].item_id -eq $itemId) {
      $canonical = $candidate
      break
    }
  }
  if ([string]$canonical -ne $blockId) {
    throw "Block item $itemId resolves to $canonical instead of declared canonical block $blockId"
  }
}

$harvestRules = @((Get-Content -Raw -Encoding UTF8 $harvestPath | ConvertFrom-Json).rules)
$harvestSet = @{}
foreach ($rule in $harvestRules) {
  $blockId = [string]$rule.block_id
  if (-not $blockSet.ContainsKey($blockId)) { throw "Harvest rule references unknown block: $blockId" }
  if ($harvestSet.ContainsKey($blockId)) { throw "Duplicate harvest rule: $blockId" }
  $harvestSet[$blockId] = $true
}

Write-Host "PASS catalog blocks=$($knownBlocks.Count) definitions=$($definitions.Count) items=$($items.Count) harvest_rules=$($harvestRules.Count)"
