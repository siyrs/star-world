$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$paths = @{
  Policy = Join-Path $root 'src\machine\machine_automation_policy.gd'
  Service = Join-Path $root 'src\machine\machine_automation_service.gd'
  Port = Join-Path $root 'src\machine\machine_container_inventory_port.gd'
  Router = Join-Path $root 'src\machine\machine_interaction_router.gd'
  Container = Join-Path $root 'src\inventory\container_storage_service.gd'
  Registry = Join-Path $root 'src\interaction\block_interaction_registry.gd'
  ToolHub = Join-Path $root 'src\ui\tool_progression_service_hub.gd'
  Regression = Join-Path $root 'tests\qa\machine_automation_regression.gd'
  Desktop = Join-Path $root 'tests\qa\machine_automation_desktop_acceptance.gd'
  Workflow = Join-Path $root '.github\workflows\machine-automation-tests.yml'
  RunAll = Join-Path $root 'tests\run_all.ps1'
}
foreach ($entry in $paths.GetEnumerator()) {
  if (-not (Test-Path -LiteralPath $entry.Value)) {
    throw "Machine automation file is missing: $($entry.Key) $($entry.Value)"
  }
}
$text = @{}
foreach ($entry in $paths.GetEnumerator()) {
  $text[$entry.Key] = Get-Content -Raw -Encoding UTF8 $entry.Value
}

$limits = @{
  CYCLE_INTERVAL_SECONDS = '0\.5'
  MAX_MACHINES_PER_CYCLE = '16'
  MAX_ITEMS_PER_CYCLE = '64'
  MAX_ITEMS_PER_TRANSFER = '8'
  MAX_CONTAINER_SLOTS_PER_CYCLE = '256'
  MAX_TRANSFER_ATTEMPTS_PER_CYCLE = '128'
}
foreach ($name in $limits.Keys) {
  if ($text.Policy -notmatch ($name + '\s*:=\s*' + $limits[$name])) {
    throw "Machine automation hard limit is missing or changed: $name"
  }
}
if ($text.Policy -notmatch 'INPUT_OFFSET\s*:=\s*Vector3i\.UP' -or $text.Policy -notmatch 'OUTPUT_OFFSET\s*:=\s*Vector3i\.DOWN') {
  throw 'Adjacent automation must use the chest directly above for input and directly below for output'
}
if ($text.Policy -notmatch 'CONTAINER_BLOCK_ID\s*:=\s*"chest"' -or $text.Policy -notmatch 'container_id\(') {
  throw 'Adjacent automation must reuse the production chest and stable position ids'
}

foreach ($method in @('setup','attach_world','advance_machine_runtime','get_runtime_snapshot','clear','shutdown')) {
  if ($text.Service -notmatch "func\s+$method\s*\(") { throw "Automation service is missing runtime method: $method" }
}
foreach ($token in @('insert_transaction','extract_transaction','get_machine_capabilities','get_machine_service')) {
  if ($text.Service -notmatch $token) { throw "Automation must use Machine Capability: $token" }
}
if ($text.Service -notmatch 'machine_changed' -or $text.Service -notmatch 'machine_removed' -or $text.Service -match 'func\s+_collect_candidates') {
  throw 'Automation candidates must be event-maintained instead of rebuilt every cycle'
}
if ($text.Service -notmatch 'MAX_MACHINES_PER_CYCLE' -or $text.Service -notmatch 'MAX_TRANSFER_ATTEMPTS_PER_CYCLE') {
  throw 'Automation cycle must consume explicit machine and transaction budgets'
}
if ($text.Service -match 'Timer\.new\(' -or $text.Service -match 'FileAccess\.' -or $text.Service -match 'save_into\(' -or $text.Service -match 'serialize\(') {
  throw 'Automation must not create timers or persist transient tasks independently'
}
if ($text.Service -match 'get_loaded_chunk' -or $text.Service -match 'block_overrides' -or $text.Service -match 'for\s+.*WORLD_') {
  throw 'Automation must not scan loaded chunks, world overrides or global world bounds'
}

foreach ($method in @('get_slot','remove_from_slot','add_item','can_transact_items','transact_items')) {
  if ($text.Port -notmatch "func\s+$method\s*\(") { throw "Container inventory port is missing method: $method" }
}
if ($text.Container -notmatch 'InventoryTransactionPolicy' -or $text.Container -notmatch 'func\s+can_transact_items\s*\(' -or $text.Container -notmatch 'func\s+transact_items\s*\(') {
  throw 'Container storage must support the same atomic planning contract as player inventory'
}
if ($text.Registry -notmatch 'func\s+get_machine_block_id\s*\(') {
  throw 'Automation must resolve physical machine blocks through the interaction registry'
}
if ($text.ToolHub -notmatch 'MachineAutomationService' -or $text.ToolHub -notmatch 'register_domain.*MACHINE_AUTOMATION_DOMAIN' -or $text.ToolHub -notmatch 'attach_world') {
  throw 'Tool progression root must compose, schedule and bind bounded automation'
}
if ($text.ToolHub -notmatch '上方供料，下方收货') {
  throw 'Players must receive a one-time explanation of the adjacent chest convention'
}

foreach ($script in @('machine_automation_regression.gd','machine_automation_desktop_acceptance.gd')) {
  if ($text.Workflow -notmatch [regex]::Escape($script)) { throw "Machine automation workflow is missing test: $script" }
}
if ($text.RunAll -notmatch 'validate_machine_automation.ps1' -or $text.RunAll -notmatch 'machine_automation_regression.gd') {
  throw 'Machine automation tests must be wired into tests/run_all.ps1'
}

Write-Host 'PASS machine_automation interval=0.5 machines=16 items=64 transfer=8 slots=256 attempts=128 event_cache=1 atomic_chests=1 transient=1'
