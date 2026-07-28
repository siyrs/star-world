$ErrorActionPreference = 'Stop'

$projectRoot = Resolve-Path "$PSScriptRoot\..\.."
$profilePath = Join-Path $projectRoot 'data\gameplay_controller_profile.json'
$profileScriptPath = Join-Path $projectRoot 'src\input\gameplay_controller_profile.gd'
$actionsPath = Join-Path $projectRoot 'src\input\gameplay_input_actions.gd'
$servicePath = Join-Path $projectRoot 'src\input\gameplay_input_service.gd'
$playerPath = Join-Path $projectRoot 'src\player\controller_exploration_player.gd'
$basePlayerPath = Join-Path $projectRoot 'src\player\first_person_player.gd'
$scenePath = Join-Path $projectRoot 'scenes\game\player.tscn'
$regressionPath = Join-Path $projectRoot 'tests\qa\controller_gameplay_regression.gd'
$desktopPath = Join-Path $projectRoot 'tests\qa\controller_gameplay_desktop_acceptance.gd'
$workflowPath = Join-Path $projectRoot '.github\workflows\controller-gameplay-tests.yml'

foreach ($path in @(
  $profilePath,
  $profileScriptPath,
  $actionsPath,
  $servicePath,
  $playerPath,
  $basePlayerPath,
  $scenePath,
  $regressionPath,
  $desktopPath,
  $workflowPath
)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing controller gameplay contract file: $path" }
}

$data = Get-Content -Raw -Encoding UTF8 $profilePath | ConvertFrom-Json
if ([int]$data.schema_version -ne 1) { throw 'Controller gameplay schema_version must remain 1' }
if ([string]$data.profile_id -ne 'standard_gamepad') { throw 'Controller gameplay profile_id must remain standard_gamepad' }

$movementDeadzone = [double]$data.movement_deadzone
$lookDeadzone = [double]$data.look_deadzone
$responseExponent = [double]$data.look_response_exponent
$lookSpeed = [double]$data.look_speed_radians_per_second
$triggerThreshold = [double]$data.trigger_threshold
if ($movementDeadzone -lt 0.05 -or $movementDeadzone -gt 0.6) { throw 'Movement deadzone is outside the bounded range' }
if ($lookDeadzone -lt 0.05 -or $lookDeadzone -gt 0.6) { throw 'Look deadzone is outside the bounded range' }
if ($responseExponent -lt 1.0 -or $responseExponent -gt 3.0) { throw 'Look response exponent is outside the bounded range' }
if ($lookSpeed -lt 0.5 -or $lookSpeed -gt 8.0) { throw 'Look speed is outside the bounded range' }
if ($triggerThreshold -lt 0.1 -or $triggerThreshold -gt 0.95) { throw 'Trigger threshold is outside the bounded range' }

$requiredActions = @(
  'move_left','move_right','move_forward','move_backward',
  'look_left','look_right','look_up','look_down',
  'jump','sprint','primary_action','secondary_action',
  'hotbar_previous','hotbar_next','toggle_inventory','toggle_crafting',
  'toggle_exploration_journal','toggle_guidance','toggle_diagnostics',
  'quick_save','ui_cancel'
)
$bindings = @($data.bindings)
if ($bindings.Count -ne 21 -or $bindings.Count -gt 32) {
  throw "Controller gameplay binding count must be exactly 21 and at most 32; actual=$($bindings.Count)"
}
$actionCounts = @{}
$physicalCounts = @{}
foreach ($binding in $bindings) {
  $action = [string]$binding.action
  $kind = [string]$binding.kind
  if ($action -notin $requiredActions) { throw "Unknown controller gameplay action: $action" }
  $actionCounts[$action] = 1 + [int]($actionCounts[$action] ?? 0)
  if ($kind -eq 'button') {
    $button = [int]$binding.button
    if ($button -lt 0 -or $button -gt 31) { throw "Invalid controller button for $action" }
    $physicalKey = "button:$button"
  } elseif ($kind -eq 'axis') {
    $axis = [int]$binding.axis
    $value = [double]$binding.value
    if ($axis -lt 0 -or $axis -gt 7 -or [Math]::Abs([Math]::Abs($value) - 1.0) -gt 0.0001) {
      throw "Invalid controller axis for $action"
    }
    $physicalKey = "axis:$axis:$([Math]::Sign($value))"
  } else {
    throw "Unknown controller binding kind: $kind"
  }
  $physicalCounts[$physicalKey] = 1 + [int]($physicalCounts[$physicalKey] ?? 0)
}
foreach ($action in $requiredActions) {
  if ([int]($actionCounts[$action] ?? 0) -ne 1) { throw "Controller action must appear exactly once: $action" }
}
foreach ($physicalKey in $physicalCounts.Keys) {
  if ([int]$physicalCounts[$physicalKey] -ne 1) { throw "Controller physical binding conflict: $physicalKey" }
}

$actionsText = Get-Content -Raw -Encoding UTF8 $actionsPath
foreach ($required in @(
  'ControllerProfileScript',
  'PRIMARY_ACTION',
  'SECONDARY_ACTION',
  'HOTBAR_PREVIOUS',
  'HOTBAR_NEXT',
  '_ensure_controller_binding',
  'InputMap.action_set_deadzone'
)) {
  if (-not $actionsText.Contains($required)) { throw "GameplayInputActions is missing '$required'" }
}

$serviceText = Get-Content -Raw -Encoding UTF8 $servicePath
foreach ($required in @(
  'get_movement_vector',
  'get_look_vector',
  'is_primary_action_pressed',
  'is_secondary_action_just_pressed',
  'get_hotbar_cycle_just_pressed',
  'get_controller_profile_snapshot'
)) {
  if (-not $serviceText.Contains($required)) { throw "GameplayInputService is missing '$required'" }
}

$playerText = Get-Content -Raw -Encoding UTF8 $playerPath
foreach ($required in @(
  '_sync_controller_primary',
  '_apply_controller_look',
  '_handle_controller_commands',
  'get_controller_gameplay_snapshot'
)) {
  if (-not $playerText.Contains($required)) { throw "Controller player is missing '$required'" }
}
foreach ($forbidden in @('InputEventJoypad','JOY_BUTTON_','JOY_AXIS_')) {
  if ($playerText.Contains($forbidden)) { throw "Physical controller mapping leaked into production player: $forbidden" }
}
$basePlayerText = Get-Content -Raw -Encoding UTF8 $basePlayerPath
foreach ($forbidden in @('InputEventJoypad','JOY_BUTTON_','JOY_AXIS_')) {
  if ($basePlayerText.Contains($forbidden)) { throw "Physical controller mapping leaked into base player: $forbidden" }
}

$sceneText = Get-Content -Raw -Encoding UTF8 $scenePath
if (-not $sceneText.Contains('res://src/player/controller_exploration_player.gd')) {
  throw 'Production player scene does not mount the controller gameplay composition layer'
}

$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath
foreach ($required in @(
  'validate_controller_gameplay.ps1',
  'controller_gameplay_regression.gd',
  'controller_gameplay_desktop_acceptance.gd',
  'ui_accessibility_regression.gd',
  'combat_cadence_regression.gd'
)) {
  if (-not $workflowText.Contains($required)) { throw "Controller gameplay workflow is missing '$required'" }
}

Write-Host "PASS controller gameplay bindings=$($bindings.Count) movement_deadzone=$movementDeadzone look_deadzone=$lookDeadzone trigger=$triggerThreshold"
