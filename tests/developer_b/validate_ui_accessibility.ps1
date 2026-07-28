$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'src\settings\ui_accessibility_policy.gd'
$settingsPolicyPath = Join-Path $root 'src\settings\game_settings_policy.gd'
$servicePath = Join-Path $root 'src\ui\ui_accessibility_service.gd'
$hubPath = Join-Path $root 'src\ui\exploration_progression_service_hub.gd'
$menuPath = Join-Path $root 'src\ui\accessibility_protected_main_menu.gd'
$gameUiPath = Join-Path $root 'src\ui\accessibility_machine_game_ui.gd'
$settingsPanelPath = Join-Path $root 'src\ui\hardened_settings_panel.gd'
$serviceScenePath = Join-Path $root 'scenes\ui\service_hub.tscn'
$menuScenePath = Join-Path $root 'scenes\ui\main_menu.tscn'
$gameUiScenePath = Join-Path $root 'scenes\ui\game_ui.tscn'
$headlessPath = Join-Path $root 'tests\qa\ui_accessibility_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\ui_accessibility_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\ui-accessibility-tests.yml'
$docPath = Join-Path $root 'docs\UI_ACCESSIBILITY_SCALING.md'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

$paths = @(
    $policyPath,$settingsPolicyPath,$servicePath,$hubPath,$menuPath,$gameUiPath,
    $settingsPanelPath,$serviceScenePath,$menuScenePath,$gameUiScenePath,
    $headlessPath,$desktopPath,$workflowPath,$docPath,$runAllPath
)
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) { throw "UI accessibility file is missing: $path" }
}

$policy = Get-Content -Raw -Encoding UTF8 $policyPath
$settingsPolicy = Get-Content -Raw -Encoding UTF8 $settingsPolicyPath
$service = Get-Content -Raw -Encoding UTF8 $servicePath
$hub = Get-Content -Raw -Encoding UTF8 $hubPath
$menu = Get-Content -Raw -Encoding UTF8 $menuPath
$gameUi = Get-Content -Raw -Encoding UTF8 $gameUiPath
$settingsPanel = Get-Content -Raw -Encoding UTF8 $settingsPanelPath
$serviceScene = Get-Content -Raw -Encoding UTF8 $serviceScenePath
$menuScene = Get-Content -Raw -Encoding UTF8 $menuScenePath
$gameUiScene = Get-Content -Raw -Encoding UTF8 $gameUiScenePath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($policy -notmatch 'class_name\s+UiAccessibilityPolicy') { throw 'Accessibility policy class is missing' }
if ($policy -notmatch 'ALLOWED_SCALES[^\n]+0\.8[^\n]+1\.0[^\n]+1\.25[^\n]+1\.5') {
    throw 'Accessibility policy must own 80, 100, 125 and 150 percent scales'
}
if ($policy -notmatch 'CONTROLLER_AXIS_THRESHOLD\s*:=\s*0\.55') {
    throw 'Controller mode detection must retain a hard drift threshold'
}
if ($settingsPolicy -notmatch '"ui_scale"\s*:\s*UiAccessibilityPolicyScript\.DEFAULT_SCALE') {
    throw 'Game settings must persist canonical interface scale'
}
if ($settingsPolicy -notmatch 'normalize_ui_scale') { throw 'Game settings must normalize interface scale' }

foreach ($needle in @('ThemeDB.fallback_base_scale','input_mode_changed','prefers_focus_navigation','get_snapshot','dispose')) {
    if ($service -notmatch [regex]::Escape($needle)) { throw "Accessibility service is missing contract: $needle" }
}
if ($service -notmatch 'func\s+_exit_tree\s*\([\s\S]{0,120}dispose\(\)') {
    throw 'Accessibility service must own terminal cleanup without changing hub lifecycle forwarding'
}
if ($hub -notmatch 'extends\s+"res://src/ui/runtime_health_service_hub\.gd"') {
    throw 'Accessibility must retain the stable Exploration Hub inheritance entry point'
}
if ($hub -notmatch '_add_service' -or $hub -notmatch 'setup_accessibility' -or $hub -notmatch 'ui_accessibility') {
    throw 'Final composition must install one accessibility state owner and wire both UI roots'
}
if ($hub -match 'func\s+_exit_tree\s*\(') {
    throw 'Exploration hub must remain a thin registration layer and not take over exit forwarding'
}
if ($menu -notmatch 'MODE_MOUSE' -or $menu -notmatch '_release_owned_focus' -or $menu -notmatch 'get_accessibility_navigation_snapshot') {
    throw 'Main menu must transfer focus ownership by active input mode'
}
if ($gameUi -notmatch '_restore_accessibility_focus' -or $gameUi -notmatch 'focus_inside_game_ui') {
    throw 'Gameplay overlays must restore controller focus deterministically'
}
if ($settingsPanel -notmatch 'get_ui_scale_control' -or $settingsPanel -notmatch 'allowed_ui_scales') {
    throw 'Settings UI must expose the authoritative scale catalog'
}

if ($serviceScene -notmatch 'exploration_progression_service_hub\.gd') {
    throw 'Production service scene must retain the stable exploration composition entry point'
}
if ($menuScene -notmatch 'accessibility_protected_main_menu\.gd') { throw 'Production menu scene does not use accessibility navigation' }
if ($gameUiScene -notmatch 'accessibility_machine_game_ui\.gd') { throw 'Production game UI scene does not use accessibility navigation' }

foreach ($testName in @('ui_accessibility_regression.gd','ui_accessibility_desktop_acceptance.gd')) {
    if ($workflow -notmatch [regex]::Escape($testName) -and $runAll -notmatch [regex]::Escape($testName)) {
        throw "UI accessibility test is not permanently wired: $testName"
    }
}
if ($workflow -notmatch 'ui-accessibility-controller-focus\.png' -or $workflow -notmatch 'ui-accessibility-high-dpi-settings\.json') {
    throw 'Accessibility workflow must retain controller screenshot and JSON evidence'
}

Write-Host 'PASS ui accessibility scales=4 input_modes=3 controller_focus=1 high_dpi_desktop=1 stable_hub=1 self_cleanup=1'
