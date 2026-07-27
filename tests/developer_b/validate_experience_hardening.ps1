$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$cameraPolicyPath = Join-Path $root 'src\player\camera_feel_policy.gd'
$cameraControllerPath = Join-Path $root 'src\player\camera_feel_controller.gd'
$cameraDataPath = Join-Path $root 'data\camera_feel.json'
$survivalPolicyPath = Join-Path $root 'src\survival\survival_tuning_policy.gd'
$survivalServicePath = Join-Path $root 'src\survival\survival_service.gd'
$survivalDataPath = Join-Path $root 'data\survival_tuning.json'
$settingsPolicyPath = Join-Path $root 'src\settings\game_settings_policy.gd'
$settingsPanelPath = Join-Path $root 'src\ui\settings_panel.gd'
$serviceHubPath = Join-Path $root 'src\ui\service_hub.gd'
$particlesPath = Join-Path $root 'src\harvest\block_break_particles.gd'
$mainMenuPath = Join-Path $root 'src\ui\main_menu.gd'
$testPath = Join-Path $root 'tests\qa\experience_hardening_regression.gd'
$desktopPath = Join-Path $root 'tests\qa\experience_hardening_desktop_acceptance.gd'
$workflowPath = Join-Path $root '.github\workflows\experience-hardening-tests.yml'
$runAllPath = Join-Path $root 'tests\run_all.ps1'

foreach ($path in @(
    $cameraPolicyPath,$cameraControllerPath,$cameraDataPath,$survivalPolicyPath,
    $survivalServicePath,$survivalDataPath,$settingsPolicyPath,$settingsPanelPath,
    $serviceHubPath,$particlesPath,$mainMenuPath,$testPath,$desktopPath,$workflowPath,$runAllPath
)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Experience hardening file is missing: $path" }
}

$cameraPolicy = Get-Content -Raw -Encoding UTF8 $cameraPolicyPath
$cameraController = Get-Content -Raw -Encoding UTF8 $cameraControllerPath
$survivalPolicy = Get-Content -Raw -Encoding UTF8 $survivalPolicyPath
$survivalService = Get-Content -Raw -Encoding UTF8 $survivalServicePath
$settingsPolicy = Get-Content -Raw -Encoding UTF8 $settingsPolicyPath
$settingsPanel = Get-Content -Raw -Encoding UTF8 $settingsPanelPath
$serviceHub = Get-Content -Raw -Encoding UTF8 $serviceHubPath
$particles = Get-Content -Raw -Encoding UTF8 $particlesPath
$mainMenu = Get-Content -Raw -Encoding UTF8 $mainMenuPath
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
$runAll = Get-Content -Raw -Encoding UTF8 $runAllPath
$cameraData = Get-Content -Raw -Encoding UTF8 $cameraDataPath | ConvertFrom-Json
$survivalData = Get-Content -Raw -Encoding UTF8 $survivalDataPath | ConvertFrom-Json

if ([int]$cameraData.schema_version -ne 1) { throw 'Camera feel data schema must remain version one' }
if ($cameraPolicy -notmatch 'class_name\s+CameraFeelPolicy' -or $cameraPolicy -notmatch 'static func\s+normalize\s*\(') {
    throw 'Camera feel must use one pure normalization policy'
}
if ($cameraController -notmatch 'PolicyScript\.normalize\(raw\)' -or $cameraController -match 'config\.merge\(parsed') {
    throw 'Camera feel controller must consume the strict policy instead of raw JSON merge'
}
foreach ($method in @('_disconnect_harvest_service','_disconnect_player_damage','get_snapshot')) {
    if ($cameraController -notmatch "func\s+$method\s*\(") { throw "Camera feel lifecycle method is missing: $method" }
}
if ($cameraController -notmatch 'func\s+_exit_tree\s*\(') { throw 'Camera feel must disconnect transient signals on exit' }

if ([int]$survivalData.schema_version -ne 2) { throw 'Survival tuning data must use profile schema version two' }
$profileNames = @($survivalData.profiles.PSObject.Properties.Name)
if (($profileNames -join ',') -ne 'relaxed,balanced,challenging') {
    throw "Survival profiles must be relaxed,balanced,challenging in stable order; found $($profileNames -join ',')"
}
if ([string]$survivalData.default_profile -ne 'relaxed') { throw 'Child-friendly relaxed difficulty must remain the default' }
if ($survivalPolicy -notmatch 'PROFILE_IDS.+relaxed.+balanced.+challenging') { throw 'Survival policy does not own the three stable profiles' }
if ($survivalService -notmatch 'func\s+set_difficulty_profile\s*\(' -or $survivalService -notmatch 'func\s+get_tuning_snapshot\s*\(') {
    throw 'Survival service is missing profile application or diagnostics'
}
if ($survivalService -match '"difficulty_profile"\s*:') { throw 'Difficulty preference must not be serialized into world state' }

if ($settingsPolicy -notmatch '"survival_difficulty"\s*:\s*"relaxed"') { throw 'Game settings must persist the relaxed default difficulty' }
if ($settingsPanel -notmatch '_survival_difficulty' -or $settingsPanel -notmatch 'allowed_survival_difficulties') {
    throw 'Settings UI must expose the authoritative difficulty catalog'
}
if ($serviceHub -notmatch 'set_difficulty_profile') { throw 'Service hub must apply difficulty through the survival service port' }

if ($particles -notmatch 'MAX_PARTICLES\s*:=\s*64' -or $particles -notmatch 'MAX_MATERIALS\s*:=\s*128') {
    throw 'Block debris node and material budgets must remain explicit'
}
if ($particles -notmatch 'set_process\(false\)' -or $particles -notmatch 'func\s+get_snapshot\s*\(') {
    throw 'Block debris must stop while idle and expose bounded diagnostics'
}
if ($mainMenu -notmatch 'MenuStarfield' -or $mainMenu -match 'Minecraft-classic') {
    throw 'Main menu must preserve Star World identity instead of shipping Minecraft-copy branding'
}
foreach ($testName in @('experience_hardening_regression.gd','experience_hardening_desktop_acceptance.gd')) {
    if ($workflow -notmatch [regex]::Escape($testName) -and $runAll -notmatch [regex]::Escape($testName)) {
        throw "Experience hardening test is not permanently wired: $testName"
    }
}

Write-Host 'PASS experience hardening strict_camera=1 survival_profiles=3 particle_pool=64 material_cache=128 desktop=1'
