$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$husbandry = Get-Content -Raw -Encoding UTF8 "$root\data\husbandry.json" | ConvertFrom-Json
$items = (Get-Content -Raw -Encoding UTF8 "$root\data\items.json" | ConvertFrom-Json).items
$creatures = (Get-Content -Raw -Encoding UTF8 "$root\data\creatures.json" | ConvertFrom-Json).creatures

$itemIds = @{}
foreach ($item in $items) {
    $itemIds[[string]$item.id] = $true
}

if ([int]$husbandry.schema_version -lt 1) { throw 'Invalid husbandry schema version' }
if ([double]$husbandry.pair_radius -le 0 -or [double]$husbandry.pair_radius -gt 12) {
    throw 'Invalid husbandry pair radius'
}
if ([int]$husbandry.max_managed_animals -lt 2 -or [int]$husbandry.max_managed_animals -gt 64) {
    throw 'Invalid managed animal limit'
}
if ([double]$husbandry.max_offline_seconds -lt 0 -or [double]$husbandry.max_offline_seconds -gt 86400) {
    throw 'Invalid husbandry offline cap'
}
if ([double]$husbandry.simulation_radius -lt 8 -or [double]$husbandry.simulation_radius -gt 128) {
    throw 'Invalid managed animal simulation radius'
}
if ([double]$husbandry.baby_scale -lt 0.25 -or [double]$husbandry.baby_scale -gt 0.9) {
    throw 'Invalid baby visual scale'
}

$speciesProperties = @($husbandry.species.PSObject.Properties)
if ($speciesProperties.Count -ne 3) {
    throw "Expected 3 husbandry species, got $($speciesProperties.Count)"
}

$feedItems = @{}
foreach ($speciesProperty in $speciesProperties) {
    $speciesId = [string]$speciesProperty.Name
    $profile = $speciesProperty.Value
    if ($speciesId -notin @('chicken', 'cow', 'pig')) {
        throw "Unsupported husbandry species: $speciesId"
    }
    if ($null -eq $creatures.$speciesId) {
        throw "Husbandry species is missing from creature registry: $speciesId"
    }
    if ([double]$creatures.$speciesId.damage -ne 0) {
        throw "Hostile species cannot be configured for husbandry: $speciesId"
    }
    $feedItem = [string]$profile.feed_item
    if (-not $itemIds.ContainsKey($feedItem)) {
        throw "Unknown husbandry feed item $feedItem for $speciesId"
    }
    if ($feedItems.ContainsKey($feedItem)) {
        throw "Feed item is reused by multiple species: $feedItem"
    }
    $feedItems[$feedItem] = $speciesId
    foreach ($field in @('growth_seconds', 'love_seconds', 'breed_cooldown_seconds')) {
        if ([double]$profile.$field -le 0) {
            throw "Invalid $field for $speciesId"
        }
    }
    $ratio = [double]$profile.baby_growth_reduction_ratio
    if ($ratio -le 0 -or $ratio -gt 1) {
        throw "Invalid baby growth reduction ratio for $speciesId"
    }
}

if ([string]$husbandry.species.chicken.feed_item -ne 'wheat_seeds') {
    throw 'Chicken feed must use wheat seeds'
}
if ([string]$husbandry.species.cow.feed_item -ne 'wheat') {
    throw 'Cow feed must use wheat'
}
if ([string]$husbandry.species.pig.feed_item -ne 'carrot') {
    throw 'Pig feed must use carrots'
}
if ($null -ne $husbandry.species.zombie) {
    throw 'Zombie must never be husbandry-enabled'
}

Write-Host "PASS husbandry_species=$($speciesProperties.Count) pair_radius=$($husbandry.pair_radius) max_managed=$($husbandry.max_managed_animals)"
