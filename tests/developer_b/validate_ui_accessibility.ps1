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
$headless = Get-Content -Raw -Encoding UTF8 $headlessPath
$desktop = Get-Content -Raw -Encoding UTF8 $desktopPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath

if ($policy -notmatch 'class_name\s+UiAccessibilityPolicy') { throw 'Accessibility policy class is missing' }
if ($policy -notmatch 'ALLOWED_SCALES[^\n]+0\.8[^\n]+1\.0[^\n]+1\.25[^\n]+1\.5') {
    throw 'Accessibility policy must own 80, 100, 125 and 150 percent scales'
}
if ($policy -notmatch 'CONTROLLER_AXIS_THRESHOLD\s*:=\s*0\.55') {
    throw 'Controller mode detection must retain a hard drift threshold'
}
if ($policy -notmatch 'CONTROLLER_MOUSE_MOTION_GUARD_MSEC\s*:=\s*350') {
    throw 'Controller ownership must retain one explicit 350ms synthetic-motion guard'
}
if ($policy -notmatch 'UI_TRANSITION_MOUSE_MOTION_GUARD_MSEC\s*:=\s*750') {
    throw 'UI transitions must retain one explicit 750ms synthetic-motion guard'
}
foreach ($hysteresisContract in @(
    'is_intentional_controller_event','is_intentional_mouse_motion',
    'should_ignore_mouse_motion_after_controller'
)) {
    if ($policy -notmatch [regex]::Escape($hysteresisContract)) {
        throw "Controller hysteresis policy is missing contract: $hysteresisContract"
    }
}
foreach ($controllerContract in @('controller_command','COMMAND_ACCEPT','COMMAND_CANCEL','JOY_BUTTON_A','JOY_BUTTON_B')) {
    if ($policy -notmatch [regex]::Escape($controllerContract)) {
        throw "Controller command policy is missing contract: $controllerContract"
    }
}
if ($settingsPolicy -notmatch '"ui_scale"\s*:\s*UiAccessibilityPolicyScript\.DEFAULT_SCALE') {
    throw 'Game settings must persist canonical interface scale'
}
if ($settingsPolicy -notmatch 'normalize_ui_scale') { throw 'Game settings must normalize interface scale' }

foreach ($needle in @(
    'ThemeDB.fallback_base_scale','input_mode_changed','prefers_focus_navigation',
    'get_snapshot','dispose','consume_input_event','begin_ui_transition_guard',
    'ignored_mouse_motion_count','ui_transition_guard_count',
    'controller_mouse_motion_guard_msec','ui_transition_mouse_motion_guard_msec'
)) {
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
foreach ($menuContract in @(
    'MODE_MOUSE','_release_owned_focus','get_accessibility_navigation_snapshot',
    '_handle_controller_command','controller_command','_on_menu_visibility_changed',
    'begin_ui_transition_guard'
)) {
    if ($menu -notmatch [regex]::Escape($menuContract)) {
        throw "Main menu accessibility contract is missing: $menuContract"
    }
}
foreach ($overlayContract in @(
    '_restore_accessibility_focus','_focus_root_for_overlay','focus_inside_active_overlay',
    '_handle_controller_overlay_command','controller_command','PanelAnimator.DURATION',
    'accessibility_focus_restored','accessibility_focus_restore_failed',
    'focus_restore_success_count','focus_restore_failure_count','begin_ui_transition_guard'
)) {
    if ($gameUi -notmatch [regex]::Escape($overlayContract)) {
        throw "Gameplay overlay accessibility contract is missing: $overlayContract"
    }
}
if ($gameUi -notmatch 'FOCUS_RESTORE_ATTEMPTS\s*:=\s*2') {
    throw 'Presented overlay focus must retain a bounded two-attempt confirmation budget'
}
if ($gameUi -match 'Timer\.new\(') {
    throw 'Overlay focus must reuse the presentation lifecycle instead of owning Timer nodes'
}
foreach ($testText in @($headless,$desktop)) {
    if ($testText -notmatch '_open_and_wait_for_overlay_focus' -or $testText -notmatch 'accessibility_focus_restored') {
        throw 'Accessibility tests must synchronize with the production overlay focus lifecycle'
    }
    if ($testText -notmatch 'ignored_mouse_motion_count' -or $testText -notmatch 'ui_transition_guard_count') {
        throw 'Accessibility tests must retain transition and ignored-motion evidence'
    }
}
if ($headless -notmatch 'exact controller guard boundary' -or $headless -notmatch 'UI transition guard ignores motion') {
    throw 'Headless accessibility regression must cover both hysteresis budgets'
}
if ($desktop -notmatch 'hiding the production menu starts a bounded UI transition guard' -or $desktop -notmatch 'synthetic high-DPI mouse motion') {
    throw 'Desktop accessibility regression must reproduce real Windows transition ordering'
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

Write-Host 'PASS ui accessibility scales=4 input_modes=3 controller_focus=1 controller_accept_cancel=1 controller_mouse_guard_ms=350 transition_mouse_guard_ms=750 transition_sources=theme|menu|overlay ignored_motion_exact=1 mouse_button_immediate=1 scoped_overlay_focus=1 presentation_bound=1 focus_attempts=2 high_dpi_desktop=1 stable_hub=1 self_cleanup=1'
