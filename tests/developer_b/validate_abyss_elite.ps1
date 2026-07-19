$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$creatureData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creatures.json') | ConvertFrom-Json
$attackData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\hostile_attacks.json') | ConvertFrom-Json
$ecologyData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\creature_ecology.json') | ConvertFrom-Json
$itemData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\items.json') | ConvertFrom-Json
$recipeData = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'data\recipes.json') | ConvertFrom-Json
$factorySource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\entity\creature_factory.gd')
$spawnerSource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\entity\creature_spawner.gd')
$dangerSource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\exploration\exploration_danger_service.gd')
$focusSource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\interaction\player_focus_resolver.gd')
$promptSource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'src\experience\interaction_prompt_resolver.gd')
$runAllSource = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'tests\run_all.ps1')

$creatures = $creatureData.creatures
$zombie = $creatures.zombie
$brute = $creatures.abyss_brute
if ($null -eq $brute) { throw 'Missing abyss_brute creature profile' }
if (-not [bool]$brute.elite) { throw 'Abyss brute must be explicitly marked elite' }
if ([double]$brute.danger_weight -lt 2.0 -or [double]$brute.danger_weight -gt 6.0) { throw 'Abyss brute danger weight must remain bounded and above a normal hostile' }
if ([double]$brute.max_health -le [double]$zombie.max_health) { throw 'Abyss brute must have more health than a normal zombie' }
if ([double]$brute.speed -ge [double]$zombie.speed) { throw 'Abyss brute must trade speed for a readable heavy attack' }
if ([double]$brute.damage -le [double]$zombie.damage) { throw 'Abyss brute must have a meaningful single-hit threat' }
if ([int]$brute.drops.abyss_cinder[0] -ne 1 -or [int]$brute.drops.abyss_cinder[1] -ne 1) { throw 'Abyss brute must grant exactly one useful abyss cinder' }

$items = @{}
foreach ($item in @($itemData.items)) { $items[[string]$item.id] = $item }
if (-not $items.ContainsKey('abyss_cinder')) { throw 'Abyss elite drop references a missing item' }
$useRecipe = @($recipeData.recipes | Where-Object { $_.ingredients.PSObject.Properties.Name -contains 'abyss_cinder' })
if ($useRecipe.Count -lt 1) { throw 'Abyss elite drop would be dead content without a production recipe use' }
if ('abyss_prospecting_kit' -notin @($useRecipe.output.id)) { throw 'Abyss cinder must continue into the calibrated prospecting route' }

$profiles = @{}
foreach ($profile in @($attackData.profiles)) { $profiles[[string]$profile.species_id] = $profile }
if (-not $profiles.ContainsKey('abyss_brute')) { throw 'Missing abyss brute hostile attack profile' }
$zombieAttack = $profiles.zombie
$bruteAttack = $profiles.abyss_brute
if ([double]$bruteAttack.windup_seconds -le [double]$zombieAttack.windup_seconds) { throw 'Elite heavy attack must have a longer readable windup' }
if ([double]$bruteAttack.cooldown_seconds -le [double]$zombieAttack.cooldown_seconds) { throw 'Elite heavy attack must recover more slowly than the normal zombie attack' }
if ([double]$bruteAttack.attack_range -le [double]$zombieAttack.attack_range) { throw 'Elite warning zone must be visibly larger than the normal zombie range' }
if ([double]$bruteAttack.telegraph_radius_multiplier -lt [double]$zombieAttack.telegraph_radius_multiplier) { throw 'Elite telegraph must not be smaller than the normal warning' }
if ([string]$bruteAttack.source_id -ne 'abyss_brute') { throw 'Elite damage source identity must remain stable' }

if ([int]$ecologyData.schema_version -ne 2) { throw 'Conditional elite ecology requires schema_version 2' }
$abyss = @($ecologyData.profiles | Where-Object { $_.id -eq 'abyss_world' })[0]
$bruteEntry = @($abyss.hostile_species | Where-Object { $_.id -eq 'abyss_brute' })[0]
if ($null -eq $bruteEntry) { throw 'Abyss ecology does not include its elite species' }
if ([int]$bruteEntry.cap -ne 1) { throw 'Abyss elite population cap must remain one' }
if ([string]$bruteEntry.condition_mode -ne 'any') { throw 'Abyss elite night/depth conditions must use OR semantics' }
if ('night' -notin @($bruteEntry.phase_ids) -or [int]$bruteEntry.max_player_y -gt 19) { throw 'Abyss elite must require night or lower/deep layers' }
foreach ($profile in @($ecologyData.profiles | Where-Object { $_.id -ne 'abyss_world' })) {
  if ('abyss_brute' -in @($profile.hostile_species.id)) { throw "Abyss elite leaked into $($profile.id) ecology" }
}

if ($factorySource -notmatch '"abyss_brute"\s*:\s*preload\("res://src/entity/abyss_brute\.gd"\)') { throw 'CreatureFactory is missing the abyss brute production script' }
if ($factorySource -notmatch 'func is_hostile_species') { throw 'CreatureFactory must expose generic hostile capability lookup' }
if ($spawnerSource -match 'species_id\s*==\s*"zombie"') { throw 'Spawner must not special-case zombie targeting for hostile species' }
if ($spawnerSource -notmatch '_count_group\(&"hostile"\)') { throw 'Spawner hostile caps must use the generic hostile group' }
if ($spawnerSource -notmatch 'get_nearby_hostile_pressure') { throw 'Spawner must expose elite-weighted nearby pressure' }
if ($dangerSource -notmatch 'get_nearby_hostile_pressure') { throw 'Danger service must consume elite-weighted hostile pressure' }
if ($focusSource -notmatch '"elite"') { throw 'Player focus must expose elite identity' }
if ($promptSource -notmatch '精英重击蓄力') { throw 'Player prompt must explain the elite heavy windup' }
if ($runAllSource -notmatch 'validate_abyss_elite\.ps1') { throw 'Full test entry must run the abyss elite validator' }
if ($runAllSource -notmatch 'abyss_elite_regression\.gd') { throw 'Full test entry must run the abyss elite regression' }

Write-Host "PASS abyss_elite health=$($brute.max_health) damage=$($brute.damage) windup=$($bruteAttack.windup_seconds) drop=abyss_cinder ecology_cap=$($bruteEntry.cap)"
