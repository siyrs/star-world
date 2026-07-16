$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$dataPath = Join-Path $root 'data\block_visuals.json'
$registryPath = Join-Path $root 'src\block\block_registry.gd'

$data = Get-Content -Raw -Encoding UTF8 $dataPath | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) { throw "Unsupported block visual schema: $($data.schema_version)" }
if ([int]$data.tile_size -ne 16) { throw "Block texture tile_size must remain 16" }
if ([int]$data.atlas_columns -lt 4 -or [int]$data.atlas_columns -gt 16) {
  throw "Invalid atlas column count: $($data.atlas_columns)"
}

$registryText = Get-Content -Raw -Encoding UTF8 $registryPath
$blockListMatch = [regex]::Match($registryText, '(?s)const BLOCK_IDS := \[(.*?)\]')
if (-not $blockListMatch.Success) { throw 'Unable to parse BlockRegistry.BLOCK_IDS' }
$knownBlocks = @([regex]::Matches($blockListMatch.Groups[1].Value, '"([^"]+)"') | ForEach-Object {
  $_.Groups[1].Value
})
if ($knownBlocks.Count -lt 40) { throw "Expected >=40 registered blocks, got $($knownBlocks.Count)" }

$visualAliases = @{}
$aliasMatches = [regex]::Matches(
  $registryText,
  '"([^"]+)"\s*:\s*\{[^\r\n]*"visual_parent"\s*:\s*"([^"]+)"'
)
foreach ($match in $aliasMatches) {
  $visualAliases[$match.Groups[1].Value] = $match.Groups[2].Value
}

$tileOrder = @($data.tile_order)
if ($tileOrder.Count -lt 45) { throw "Expected >=45 reusable pixel tiles, got $($tileOrder.Count)" }
$tileIds = @{}
$allowedPatterns = @(
  'transparent','noise','grass_side','cobble','bark','rings','leaves','water','lava',
  'boards','bricks','glass','ore','crafting_top','crafting_side','furnace','chest','door',
  'fence','ladder','torch','weave','ice','furrows','crop','bed_top','bed_side',
  'repair_top','repair_side'
)
foreach ($rawTileId in $tileOrder) {
  $tileId = [string]$rawTileId
  if ([string]::IsNullOrWhiteSpace($tileId)) { throw 'Empty block visual tile id' }
  if ($tileIds.ContainsKey($tileId)) { throw "Duplicate tile id in tile_order: $tileId" }
  $tileIds[$tileId] = $true
  $style = $data.tiles.$tileId
  if ($null -eq $style) { throw "Missing tile style: $tileId" }
  $pattern = [string]$style.pattern
  if ($pattern -notin $allowedPatterns) { throw "Unsupported pattern '$pattern' in tile $tileId" }
  $palette = @($style.palette)
  if ($palette.Count -lt 1) { throw "Tile has no palette: $tileId" }
  foreach ($color in $palette) {
    if ([string]$color -notmatch '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$') {
      throw "Invalid color '$color' in tile $tileId"
    }
  }
}

$blockProfiles = @($data.blocks.PSObject.Properties.Name)
foreach ($blockId in $knownBlocks) {
  $profileId = $blockId
  if ($visualAliases.ContainsKey($blockId)) {
    $profileId = [string]$visualAliases[$blockId]
    if ($profileId -notin $knownBlocks) { throw "Visual parent for $blockId is unknown: $profileId" }
  }
  if ($profileId -notin $blockProfiles) { throw "Missing visual profile for block: $blockId (resolved $profileId)" }
  $profile = $data.blocks.$profileId
  $references = @()
  foreach ($key in @('all','top','side','bottom')) {
    if ($null -ne $profile.$key -and -not [string]::IsNullOrWhiteSpace([string]$profile.$key)) {
      $references += [string]$profile.$key
    }
  }
  if ($references.Count -eq 0) { throw "Block visual profile is empty: $profileId" }
  foreach ($tileId in $references) {
    if (-not $tileIds.ContainsKey($tileId)) { throw "Block $blockId references unknown tile $tileId" }
  }
}
foreach ($blockId in $blockProfiles) {
  if ($blockId -notin $knownBlocks) { throw "Visual profile references unknown block: $blockId" }
}

if ([string]$data.blocks.grass.top -eq [string]$data.blocks.grass.side) {
  throw 'Grass must use distinct top and side tiles'
}
if ([string]$data.blocks.wood.top -eq [string]$data.blocks.wood.side) {
  throw 'Logs must use distinct end-grain and bark tiles'
}
$oreTiles = @(
  [string]$data.blocks.coal_ore.all,
  [string]$data.blocks.iron_ore.all,
  [string]$data.blocks.gold_ore.all,
  [string]$data.blocks.diamond_ore.all
)
if (@($oreTiles | Select-Object -Unique).Count -ne 4) { throw 'Each ore must have a distinct pixel tile' }

Write-Host "PASS block_visuals blocks=$($knownBlocks.Count) aliases=$($visualAliases.Count) tiles=$($tileOrder.Count) tile_size=$($data.tile_size)"
