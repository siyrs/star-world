$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\..\.."
$policyPath = Join-Path $root 'src\machine\machine_capability_policy.gd'
$proxyPath = Join-Path $root 'src\machine\machine_transfer_inventory_proxy.gd'
$routerPath = Join-Path $root 'src\machine\machine_interaction_router.gd'
$participantPath = Join-Path $root 'src\machine\machine_runtime_participant.gd'
$inventoryPath = Join-Path $root 'src\inventory\inventory_service.gd'
$runAllPath = Join-Path $root 'tests\run_all.ps1'
$workflowPath = Join-Path $root '.github\workflows\machine-capability-tests.yml'

foreach ($path in @($policyPath,$proxyPath,$routerPath,$participantPath,$inventoryPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Machine capability file is missing: $path" }
}
if (-not (Test-Path -LiteralPath $workflowPath)) { throw 'Machine capability workflow is missing' }

$policyText = Get-Content -Raw -Encoding UTF8 $policyPath
$proxyText = Get-Content -Raw -Encoding UTF8 $proxyPath
$routerText = Get-Content -Raw -Encoding UTF8 $routerPath
$participantText = Get-Content -Raw -Encoding UTF8 $participantPath
$inventoryText = Get-Content -Raw -Encoding UTF8 $inventoryPath
$runAllText = Get-Content -Raw -Encoding UTF8 $runAllPath
$workflowText = Get-Content -Raw -Encoding UTF8 $workflowPath

if ($policyText -notmatch 'class_name\s+MachineCapabilityPolicy') { throw 'Machine capability pure policy is missing' }
if ($policyText -notmatch 'MAX_TRANSFER_ITEMS\s*:=\s*64') { throw 'Machine transfer item budget must remain 64' }
foreach ($direction in @('DIRECTION_INSERT','DIRECTION_EXTRACT')) {
  if ($policyText -notmatch $direction) { throw "Machine capability direction is missing: $direction" }
}
foreach ($method in @('normalize_slot_contracts','normalize_requested_count','slot_capacity','capability_snapshot')) {
  if ($policyText -notmatch "static\s+func\s+$method\s*\(") { throw "Machine capability policy is missing method: $method" }
}
if ($policyText -notmatch 'duplicate_slot' -or $policyText -notmatch 'invalid_direction' -or $policyText -notmatch 'transaction_limit') {
  throw 'Machine capability policy must reject duplicate slots, invalid directions and over-budget transfers'
}

if ($proxyText -notmatch 'class_name\s+MachineTransferInventoryProxy') { throw 'Machine transfer inventory proxy is missing' }
if ($proxyText -notmatch 'remove_from_slot' -or $proxyText -notmatch 'transact_items') {
  throw 'Machine transfer proxy must use exact source removal and atomic inventory additions'
}
if ($proxyText -match 'add_item\(item_id, requested_count') {
  throw 'Machine extraction must not use partial InventoryService.add_item writes'
}

foreach ($method in @('get_machine_capabilities','get_slot_contract','can_insert','can_extract','insert_transaction','extract_transaction')) {
  if ($routerText -notmatch "func\s+$method\s*\(") { throw "Machine interaction router is missing capability method: $method" }
}
foreach ($signal in @('machine_transfer_completed','machine_transfer_rejected')) {
  if ($routerText -notmatch $signal) { throw "Machine capability router signal is missing: $signal" }
}
if ($routerText -notmatch 'transfer_attempt_count' -or $routerText -notmatch 'inserted_item_count' -or $routerText -notmatch 'extracted_item_count') {
  throw 'Machine capability transfers must expose bounded diagnostics'
}
if ($routerText -match 'machine_type\s*==\s*["'']furnace' -or $routerText -match 'machine_type\s*==\s*["'']stonecutter') {
  throw 'Machine capability transactions must not branch on concrete production machine types'
}
if ($routerText -notmatch 'CapabilityPolicyScript' -or $routerText -notmatch 'TransferProxyScript') {
  throw 'Machine router must delegate capability validation and atomic inventory proxying'
}

if ($participantText -notmatch 'register_machine_type' -or $participantText -notmatch 'furnace' -or $participantText -notmatch 'stonecutter') {
  throw 'Production Machine Runtime must continue registering both machine domains'
}
if ($inventoryText -notmatch 'func\s+can_transact_items\s*\(' -or $inventoryText -notmatch 'func\s+transact_items\s*\(') {
  throw 'Machine extraction requires the production atomic inventory transaction port'
}

foreach ($script in @('machine_capability_regression\.gd','machine_capability_desktop_acceptance\.gd')) {
  if ($runAllText -notmatch $script -and $workflowText -notmatch $script) {
    throw "Machine capability acceptance is not permanently wired: $script"
  }
}

Write-Host 'PASS machine_capability types=2 transfer_limit=64 atomic_extract=1 concrete_type_branches=0'
