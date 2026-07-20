$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$itemsPath = Join-Path $root 'data\items.json'
$craftingPath = Join-Path $root 'data\recipes.json'
$recipesPath = Join-Path $root 'data\stonecutter_recipes.json'
$blockRegistryPath = Join-Path $root 'src\block\block_registry.gd'
$harvestPath = Join-Path $root 'data\block_harvest.json'
$recipeRegistryPath = Join-Path $root 'src\machine\stonecutter_recipe_registry.gd'
$servicePath = Join-Path $root 'src\machine\stonecutter_service.gd'
$migrationPath = Join-Path $root 'src\machine\machine_state_migration.gd'
$participantPath = Join-Path $root 'src\machine\machine_runtime_participant.gd'
$routerPath = Join-Path $root 'src\machine\machine_interaction_router.gd'
$interactionPath = Join-Path $root 'src\interaction\block_interaction_service.gd'
$interactionRegistryPath = Join-Path $root 'src\interaction\block_interaction_registry.gd'
$uiScenePath = Join-Path $root 'scenes\ui\game_ui.tscn'
$uiPath = Join-Path $root 'src\ui\machine_game_ui.gd'
$panelPath = Join-Path $root 'src\ui\stonecutter_panel.gd'
$overlayPath = Join-Path $root 'src\ui\game_ui_extension_overlay_ids.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\stonecutter-machine-tests.yml'

foreach ($path in @(
  $itemsPath,$craftingPath,$recipesPath,$blockRegistryPath,$harvestPath,
  $recipeRegistryPath,$servicePath,$migrationPath,$participantPath,$routerPath,
  $interactionPath,$interactionRegistryPath,$uiScenePath,$uiPath,$panelPath,
  $overlayPath,$runAllPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Stonecutter contract file is missing: $path" }
}
if (-not (Test-Path -LiteralPath $workflowPath)) { throw 'Stonecutter workflow is missing' }

$items = @((Get-Content -Raw -Encoding UTF8 $itemsPath | ConvertFrom-Json).items)
$crafting = @((Get-Content -Raw -Encoding UTF8 $craftingPath | ConvertFrom-Json).recipes)
$recipeData = Get-Content -Raw -Encoding UTF8 $recipesPath | ConvertFrom-Json
$recipes = @($recipeData.recipes)
$harvest = @((Get-Content -Raw -Encoding UTF8 $harvestPath | ConvertFrom-Json).rules)
$blockText = Get-Content -Raw -Encoding UTF8 $blockRegistryPath
$registryText = Get-Content -Raw -Encoding UTF8 $recipeRegistryPath
$serviceText = Get-Content -Raw -Encoding UTF8 $servicePath
$migrationText = Get-Content -Raw -Encoding UTF8 $migrationPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$routerText = Get-Content -Raw -Encoding UTF8 $routerPath
$interactionText = Get-Content -Raw -Encoding UTF8 $interactionPath
$interactionRegistryText = Get-Content -Raw -Encoding UTF8 $interactionRegistryPath
$uiSceneText = Get-Content -Raw -Encoding UTF8 $uiScenePath
$uiText = Get-Content -Raw -Encoding UTF8 $uiPath
$panelText = Get-Content -Raw -Encoding UTF8 $panelPath
$overlayText = Get-Content -Raw -Encoding UTF8 $overlayPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath

$stonecutterItems = @($items | Where-Object { [string]$_.id -eq 'stonecutter' })
if ($stonecutterItems.Count -ne 1) { throw "Expected one stonecutter item, found $($stonecutterItems.Count)" }
if ([string]$stonecutterItems[0].category -ne 'block' -or [string]$stonecutterItems[0].block_id -ne 'stonecutter') {
  throw 'Stonecutter item must round-trip through the stonecutter block'
}
$craftingRecipes = @($crafting | Where-Object { [string]$_.id -eq 'stonecutter' })
if ($craftingRecipes.Count -ne 1 -or [string]$craftingRecipes[0].station -ne 'workbench') {
  throw 'Stonecutter must have one workbench recipe'
}
if ([int]$craftingRecipes[0].ingredients.cobblestone -ne 6 -or [int]$craftingRecipes[0].ingredients.iron_ingot -ne 2) {
  throw 'Stonecutter crafting cost must use six cobblestone and two iron ingots'
}
if ([int]$recipeData.schema_version -ne 1 -or $recipes.Count -ne 3) {
  throw "Expected schema one with three stonecutter recipes, found $($recipes.Count)"
}
$inputs = @{}
foreach ($recipe in $recipes) {
  $recipeId = [string]$recipe.id
  $inputId = [string]$recipe.input.id
  $outputId = [string]$recipe.output.id
  if ([string]::IsNullOrWhiteSpace($recipeId) -or [string]::IsNullOrWhiteSpace($inputId) -or [string]::IsNullOrWhiteSpace($outputId)) {
    throw 'Stonecutter recipe id/input/output must be non-empty'
  }
  if ($inputs.ContainsKey($inputId)) { throw "Stonecutter input has ambiguous recipes: $inputId" }
  $inputs[$inputId] = $true
  if ([double]$recipe.duration_seconds -le 0 -or [double]$recipe.duration_seconds -gt 10) {
    throw "Stonecutter duration is outside the bounded range: $recipeId"
  }
}
foreach ($requiredInput in @('cobblestone','stone','stone_bricks')) {
  if (-not $inputs.ContainsKey($requiredInput)) { throw "Missing stonecutter input: $requiredInput" }
}

if ($blockText -notmatch '"glass_pane_ns",\s*\r?\n\s*# New machines[\s\S]*"stonecutter"') {
  throw 'Stonecutter block must append after all existing numeric block IDs'
}
if ($blockText -notmatch '"stonecutter"\s*:\s*\{[^\r\n]+"item_id":"stonecutter"') {
  throw 'Stonecutter block definition is missing or not placeable'
}
if (@($harvest | Where-Object { [string]$_.block_id -eq 'stonecutter' }).Count -ne 1) {
  throw 'Stonecutter must have one harvest rule'
}

foreach ($method in @('load_from_file','recipe_count','get_recipe_for_input','get_validation_errors')) {
  if ($registryText -notmatch "func\s+$method\s*\(") { throw "Stonecutter recipe registry is missing method: $method" }
}
foreach ($method in @('set_external_scheduler','advance_machine_runtime','get_runtime_snapshot','serialize','deserialize','can_remove_machine','shutdown')) {
  if ($serviceText -notmatch "func\s+$method\s*\(") { throw "Stonecutter service is missing method: $method" }
}
if ($serviceText -match 'Timer\.new\(' -or $serviceText -match 'save_world\(' -or $serviceText -match 'FileAccess\.open\(') {
  throw 'Stonecutter must use shared scheduling and the world save transaction'
}
if ($serviceText -notmatch 'MAX_OFFLINE_SECONDS\s*:=\s*4\s*\*\s*60\s*\*\s*60' -or $serviceText -notmatch 'MAX_SIMULATION_ITERATIONS\s*:=\s*512') {
  throw 'Stonecutter offline and simulation budgets must remain bounded'
}
if ($migrationText -notmatch '"stonecutters"' -or $migrationText -notmatch '_normalize_stonecutter_state') {
  throw 'Machine migration must whitelist the stonecutter domain'
}
if ($participantText -notmatch 'register_domain"?,?\s*[\s\S]*&"stonecutter"' -or $participantText -notmatch 'item_processed') {
  throw 'Machine runtime participant must register and observe the stonecutter domain'
}
if ($participantText -notmatch '"stonecutters"' -or $participantText -notmatch 'machine_interaction_router') {
  throw 'Machine runtime participant must persist stonecutters and publish the interaction router'
}

if ($routerText -notmatch 'class_name\s+MachineInteractionRouter' -or $routerText -notmatch 'MAX_MACHINE_TYPES\s*:=\s*16') {
  throw 'Generic machine interaction router or its type budget is missing'
}
foreach ($method in @('register_machine_type','open_machine_type','can_remove_machine_type','remove_machine_type')) {
  if ($routerText -notmatch "func\s+$method\s*\(") { throw "Machine interaction router is missing method: $method" }
}
if ($interactionText -notmatch 'machine_access' -or $interactionText -notmatch 'open_machine_type' -or $interactionText -notmatch 'can_remove_machine_type') {
  throw 'Block interaction must consume the generic machine access contract'
}
if ($interactionText -match 'const\s+MACHINE_SLOTS') {
  throw 'Block interaction must not hard-code furnace slot names for all machines'
}
if ($interactionRegistryText -notmatch '"stonecutter"' -or $interactionRegistryText -notmatch '"machine_type": "stonecutter"') {
  throw 'Stonecutter block interaction definition is missing'
}

if ($uiSceneText -notmatch 'machine_game_ui\.gd') { throw 'Production GameUI must mount the machine extension layer' }
if ($uiText -notmatch 'func\s+open_stonecutter\s*\(' -or $uiText -notmatch 'setup_machine_runtime') {
  throw 'Machine GameUI must expose stonecutter setup and open ports'
}
if ($panelText -notmatch 'queued_jobs' -or $panelText -notmatch 'estimated_total_seconds' -or $panelText -notmatch '下一份') {
  throw 'Stonecutter panel must expose queue and ETA information'
}
if ($overlayText -notmatch 'STONECUTTER\s*:=\s*9' -or $overlayText -notmatch 'ALL:[^\r\n]+STONECUTTER') {
  throw 'Stonecutter overlay id must be unique and part of the shared extension catalog'
}

foreach ($testPath in @('stonecutter_machine_regression.gd','stonecutter_machine_desktop_acceptance.gd')) {
  if ($runAllText -notmatch $testPath -and $workflowText -notmatch $testPath) {
    throw "Stonecutter acceptance is not permanently wired: $testPath"
  }
}

Write-Host "PASS stonecutter recipes=$($recipes.Count) domains=2 machine_types=2 overlay=9 offline_hours=4"
