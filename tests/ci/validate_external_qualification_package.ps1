param(
    [string]$PackagePath = '',
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SchemaVersion = 1
$StrictSoakSeconds = 7200
$RequiredProfiles = @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')
$RequiredTiers = @('minimum', 'recommended')
$RequiredFaultScenarios = @('hdd', 'antivirus', 'power_loss')
$RequiredReviewChecks = @('fresh_install', 'new_world', 'save_reload', 'five_profiles', 'input_and_ui', 'quit_and_restart')
$AllowedSources = @('target_hardware', 'hosted_reference', 'fixture')
$AllowedStorageTypes = @('hdd', 'ssd', 'nvme')

function Get-Field {
    param([object]$Object, [string]$Name, [object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Test-HexDigest {
    param([string]$Value, [int]$Length)
    return $Value.Length -eq $Length -and $Value -cmatch "^[0-9a-f]{$Length}$"
}

function Add-RequiredTextError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [object]$Object,
        [string]$Name
    )
    $value = [string](Get-Field $Object $Name '')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $Errors.Add("$Name is required")
    } elseif ($value.Length -gt 256) {
        $Errors.Add("$Name exceeds the maximum length")
    }
}

function Add-RequiredHashError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [object]$Object,
        [string]$Name,
        [int]$Length
    )
    $value = ([string](Get-Field $Object $Name '')).Trim().ToLowerInvariant()
    if (-not (Test-HexDigest -Value $value -Length $Length)) {
        $Errors.Add("$Name must be a $Length-character hexadecimal digest")
    }
}

function Test-ExternalQualificationPackage {
    param([Parameter(Mandatory = $true)][object]$Package)

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    if ([int](Get-Field $Package 'schema_version' 0) -ne $SchemaVersion) {
        $errors.Add("schema_version must equal $SchemaVersion")
    }
    Add-RequiredTextError -Errors $errors -Object $Package -Name 'package_id'

    $source = ([string](Get-Field $Package 'evidence_source' '')).Trim()
    $fixtureMode = [bool](Get-Field $Package 'fixture_mode' $false)
    $referenceOnly = [bool](Get-Field $Package 'reference_only' $false)
    $hostedRunner = [bool](Get-Field $Package 'hosted_runner' $false)
    if ($source -notin $AllowedSources) { $errors.Add('evidence_source is unsupported') }
    if ($source -eq 'target_hardware' -and $hostedRunner) {
        $errors.Add('target_hardware evidence cannot be produced by a hosted runner')
    }
    if ($source -eq 'target_hardware' -and $referenceOnly) {
        $errors.Add('target_hardware evidence cannot be reference_only')
    }
    if ($source -ne 'target_hardware' -and -not $referenceOnly) {
        $errors.Add('non-target evidence must be reference_only')
    }
    if ($fixtureMode -ne ($source -eq 'fixture')) {
        $errors.Add('fixture_mode and fixture evidence_source must be used together')
    }

    $build = Get-Field $Package 'build' $null
    Add-RequiredHashError -Errors $errors -Object $build -Name 'commit_sha' -Length 40
    Add-RequiredHashError -Errors $errors -Object $build -Name 'executable_sha256' -Length 64
    Add-RequiredHashError -Errors $errors -Object $build -Name 'pck_sha256' -Length 64
    Add-RequiredTextError -Errors $errors -Object $build -Name 'version'

    $review = Get-Field $Package 'experiential_review' $null
    Add-RequiredTextError -Errors $errors -Object $review -Name 'reviewer_id'
    Add-RequiredTextError -Errors $errors -Object $review -Name 'implementer_id'
    $reviewer = ([string](Get-Field $review 'reviewer_id' '')).Trim()
    $implementer = ([string](Get-Field $review 'implementer_id' '')).Trim()
    if ($reviewer -and $reviewer -eq $implementer) {
        $errors.Add('experiential reviewer must be independent from the implementer')
    }
    if (-not [bool](Get-Field $review 'independent' $false)) {
        $errors.Add('experiential review must attest independence')
    }
    if ([long](Get-Field $review 'signed_at_unix' 0) -le 0) {
        $errors.Add('experiential review signed_at_unix must be positive')
    }
    if ([string](Get-Field $review 'result' '') -ne 'pass') {
        $errors.Add('experiential review result must be pass')
    }
    $checklist = Get-Field $review 'checklist' $null
    foreach ($check in $RequiredReviewChecks) {
        if (-not [bool](Get-Field $checklist $check $false)) {
            $errors.Add("experiential review checklist is incomplete: $check")
        }
    }
    if (@(Get-Field $review 'blockers' @()).Count -ne 0) {
        $errors.Add('experiential review contains unresolved blockers')
    }

    $requireReal = $source -eq 'target_hardware'
    $seenTiers = @{}
    foreach ($entry in @(Get-Field $Package 'hardware_qualification' @())) {
        $tier = [string](Get-Field $entry 'tier' '')
        if ($tier -notin $RequiredTiers) {
            $errors.Add("hardware tier is unsupported: $tier")
            continue
        }
        if ($seenTiers.ContainsKey($tier)) { $errors.Add("hardware tier is duplicated: $tier") }
        $seenTiers[$tier] = $true
        Add-RequiredTextError -Errors $errors -Object $entry -Name 'operator_id'
        Add-RequiredHashError -Errors $errors -Object $entry -Name 'machine_fingerprint_sha256' -Length 64
        Add-RequiredTextError -Errors $errors -Object $entry -Name 'cpu'
        Add-RequiredTextError -Errors $errors -Object $entry -Name 'gpu'
        Add-RequiredTextError -Errors $errors -Object $entry -Name 'os'
        if ([double](Get-Field $entry 'ram_gib' 0) -le 0) { $errors.Add("hardware $tier ram_gib must be positive") }
        $started = [long](Get-Field $entry 'started_at_unix' 0)
        $completed = [long](Get-Field $entry 'completed_at_unix' 0)
        if ($started -le 0 -or $completed -lt $started) { $errors.Add("hardware $tier timestamps are invalid") }
        if ([string](Get-Field $entry 'result' '') -ne 'pass') { $errors.Add("hardware $tier result must be pass") }
        if ($requireReal -and -not [bool](Get-Field $entry 'operator_attested' $false)) {
            $errors.Add("hardware $tier requires real operator attestation")
        }
        $storage = Get-Field $entry 'storage' $null
        if ([string](Get-Field $storage 'drive_type' '') -notin $AllowedStorageTypes) {
            $errors.Add("hardware $tier storage drive_type is invalid")
        }
        Add-RequiredTextError -Errors $errors -Object $storage -Name 'model'
        $profiles = @{}
        foreach ($profile in @(Get-Field $entry 'profiles' @())) { $profiles[[string]$profile] = $true }
        foreach ($profile in $RequiredProfiles) {
            if (-not $profiles.ContainsKey($profile)) { $errors.Add("hardware $tier is missing profile $profile") }
        }
    }
    foreach ($tier in $RequiredTiers) {
        if (-not $seenTiers.ContainsKey($tier)) { $errors.Add("hardware qualification is missing tier: $tier") }
    }

    $soak = Get-Field $Package 'strict_soak' $null
    $requested = [long](Get-Field $soak 'requested_seconds' 0)
    $elapsed = [long](Get-Field $soak 'elapsed_seconds' 0)
    $soakReference = [bool](Get-Field $soak 'reference_only' $false)
    if ($requested -le 0 -or $elapsed -le 0) { $errors.Add('strict soak durations must be positive') }
    if ($elapsed -gt $requested + 600) { $errors.Add('strict soak elapsed_seconds exceeds the requested window unexpectedly') }
    if ($requireReal) {
        if ($requested -lt $StrictSoakSeconds -or $elapsed -lt $StrictSoakSeconds) {
            $errors.Add('target-hardware soak must run for at least 7200 seconds')
        }
        if ($soakReference) { $errors.Add('target-hardware soak cannot be reference_only') }
        if (-not [bool](Get-Field $soak 'target_hardware' $false)) { $errors.Add('strict soak must attest target_hardware') }
    } else {
        if (-not $soakReference) { $errors.Add('non-target soak must be reference_only') }
        if ($requested -lt $StrictSoakSeconds) { $warnings.Add('reference soak is shorter than the commercial 7200-second gate') }
    }
    if (-not [bool](Get-Field $soak 'clean_exit' $false)) { $errors.Add('strict soak must end with a clean exit') }
    if ([int](Get-Field $soak 'crash_count' -1) -ne 0) { $errors.Add('strict soak crash_count must be zero') }
    if ([bool](Get-Field $soak 'timed_out' $true)) { $errors.Add('strict soak must not time out') }
    if ([string](Get-Field $soak 'result' '') -ne 'pass') { $errors.Add('strict soak result must be pass') }
    Add-RequiredHashError -Errors $errors -Object $soak -Name 'lifecycle_report_sha256' -Length 64
    Add-RequiredHashError -Errors $errors -Object $soak -Name 'soak_report_sha256' -Length 64

    $faultLab = Get-Field $Package 'fault_lab' $null
    Add-RequiredTextError -Errors $errors -Object $faultLab -Name 'operator_id'
    if ([string](Get-Field $faultLab 'result' '') -ne 'pass') { $errors.Add('fault lab result must be pass') }
    $seenScenarios = @{}
    foreach ($scenario in @(Get-Field $faultLab 'scenarios' @())) {
        $scenarioType = [string](Get-Field $scenario 'type' '')
        if ($scenarioType -notin $RequiredFaultScenarios) {
            $errors.Add("fault scenario is unsupported: $scenarioType")
            continue
        }
        if ($seenScenarios.ContainsKey($scenarioType)) { $errors.Add("fault scenario is duplicated: $scenarioType") }
        $seenScenarios[$scenarioType] = $true
        if (-not [bool](Get-Field $scenario 'interruption_observed' $false)) {
            $errors.Add("fault scenario did not observe interruption: $scenarioType")
        }
        if (-not [bool](Get-Field $scenario 'recovery_verified' $false)) {
            $errors.Add("fault scenario did not verify recovery: $scenarioType")
        }
        if (-not [bool](Get-Field $scenario 'world_integrity_verified' $false)) {
            $errors.Add("fault scenario did not verify world integrity: $scenarioType")
        }
        if ($requireReal -and -not [bool](Get-Field $scenario 'attested_real' $false)) {
            $errors.Add("fault scenario requires real attestation: $scenarioType")
        }
        Add-RequiredHashError -Errors $errors -Object $scenario -Name 'before_world_sha256' -Length 64
        Add-RequiredHashError -Errors $errors -Object $scenario -Name 'after_world_sha256' -Length 64
    }
    foreach ($scenarioType in $RequiredFaultScenarios) {
        if (-not $seenScenarios.ContainsKey($scenarioType)) { $errors.Add("fault lab is missing scenario: $scenarioType") }
    }

    foreach ($finding in @(Get-Field $Package 'findings' @())) {
        if ([string](Get-Field $finding 'severity' '') -eq 'blocker' -and [string](Get-Field $finding 'state' 'open') -ne 'closed') {
            $errors.Add('qualification package contains an unresolved blocker')
        }
    }

    $owner = Get-Field $Package 'release_owner_attestation' $null
    if ($requireReal -or $null -ne $owner) {
        Add-RequiredTextError -Errors $errors -Object $owner -Name 'owner_id'
        if ([long](Get-Field $owner 'signed_at_unix' 0) -le 0) { $errors.Add('release owner signed_at_unix must be positive') }
        if (-not [bool](Get-Field $owner 'all_artifacts_attached' $false)) {
            $errors.Add('release owner must attest that all artifacts are attached')
        }
        if (-not [bool](Get-Field $owner 'approved_for_release' $false)) {
            $errors.Add('release owner must explicitly approve the evidence package')
        }
    }

    if ($source -eq 'hosted_reference') { $warnings.Add('hosted reference evidence cannot close commercial release gates') }
    if ($fixtureMode) { $warnings.Add('fixture evidence exercises the contract only') }

    $contractValid = $errors.Count -eq 0
    $releaseGatePassed = $contractValid -and $source -eq 'target_hardware' -and -not $hostedRunner -and -not $referenceOnly -and -not $fixtureMode
    $status = if ($releaseGatePassed) { 'external_evidence_complete' } elseif ($contractValid -and $fixtureMode) { 'fixture_contract_complete' } elseif ($contractValid) { 'reference_only' } else { 'invalid' }
    return [pscustomobject]@{
        schema_version = $SchemaVersion
        contract_valid = $contractValid
        release_gate_passed = $releaseGatePassed
        status = $status
        errors = @($errors)
        warnings = @($warnings)
        error_count = $errors.Count
        warning_count = $warnings.Count
    }
}

function New-FixturePackage {
    param([string]$Source = 'fixture', [bool]$FixtureMode = $true, [bool]$ReferenceOnly = $true)
    $profiles = @($RequiredProfiles)
    $hardware = foreach ($tier in $RequiredTiers) {
        [pscustomobject]@{
            tier = $tier
            operator_id = "operator-$tier"
            operator_attested = $false
            machine_fingerprint_sha256 = ('b' * 64)
            cpu = 'fixture cpu'
            gpu = 'fixture gpu'
            ram_gib = 16
            os = 'Windows fixture'
            storage = [pscustomobject]@{ drive_type = 'ssd'; model = 'fixture storage' }
            profiles = @($profiles)
            started_at_unix = 1000
            completed_at_unix = 1050
            result = 'pass'
        }
    }
    $scenarios = foreach ($scenarioType in $RequiredFaultScenarios) {
        [pscustomobject]@{
            type = $scenarioType
            attested_real = $false
            interruption_observed = $true
            recovery_verified = $true
            world_integrity_verified = $true
            before_world_sha256 = ('d' * 64)
            after_world_sha256 = ('e' * 64)
        }
    }
    return [pscustomobject]@{
        schema_version = 1
        package_id = 'qualification-fixture'
        fixture_mode = $FixtureMode
        reference_only = $ReferenceOnly
        evidence_source = $Source
        hosted_runner = $Source -eq 'hosted_reference'
        build = [pscustomobject]@{
            commit_sha = ('a' * 40)
            executable_sha256 = ('1' * 64)
            pck_sha256 = ('2' * 64)
            version = 'v1.3.0-fixture'
        }
        experiential_review = [pscustomobject]@{
            reviewer_id = 'reviewer-b'
            implementer_id = 'implementer-a'
            independent = $true
            signed_at_unix = 2000
            result = 'pass'
            blockers = @()
            checklist = [pscustomobject]@{
                fresh_install = $true
                new_world = $true
                save_reload = $true
                five_profiles = $true
                input_and_ui = $true
                quit_and_restart = $true
            }
        }
        hardware_qualification = @($hardware)
        strict_soak = [pscustomobject]@{
            requested_seconds = 600
            elapsed_seconds = 600
            reference_only = $true
            target_hardware = $false
            clean_exit = $true
            crash_count = 0
            timed_out = $false
            result = 'pass'
            lifecycle_report_sha256 = ('3' * 64)
            soak_report_sha256 = ('4' * 64)
        }
        fault_lab = [pscustomobject]@{ operator_id = 'fault-operator'; result = 'pass'; scenarios = @($scenarios) }
        findings = @()
    }
}

function ConvertTo-RealPackage {
    param([Parameter(Mandatory = $true)][object]$Package)
    $Package.evidence_source = 'target_hardware'
    $Package.fixture_mode = $false
    $Package.reference_only = $false
    $Package.hosted_runner = $false
    foreach ($entry in @($Package.hardware_qualification)) { $entry.operator_attested = $true }
    $Package.strict_soak.requested_seconds = 7200
    $Package.strict_soak.elapsed_seconds = 7200
    $Package.strict_soak.reference_only = $false
    $Package.strict_soak.target_hardware = $true
    foreach ($scenario in @($Package.fault_lab.scenarios)) { $scenario.attested_real = $true }
    $Package | Add-Member -NotePropertyName release_owner_attestation -NotePropertyValue ([pscustomobject]@{
        owner_id = 'release-owner'
        signed_at_unix = 3000
        all_artifacts_attached = $true
        approved_for_release = $true
    }) -Force
}

function Invoke-SelfTest {
    $fixture = New-FixturePackage
    $fixtureResult = Test-ExternalQualificationPackage -Package $fixture
    if (-not $fixtureResult.contract_valid -or $fixtureResult.release_gate_passed) { throw 'Fixture contract self-test failed.' }

    $hosted = New-FixturePackage -Source 'hosted_reference' -FixtureMode $false -ReferenceOnly $true
    $hostedResult = Test-ExternalQualificationPackage -Package $hosted
    if (-not $hostedResult.contract_valid -or $hostedResult.release_gate_passed) { throw 'Hosted reference self-test failed.' }

    $real = New-FixturePackage
    ConvertTo-RealPackage -Package $real
    $realResult = Test-ExternalQualificationPackage -Package $real
    if (-not $realResult.contract_valid -or -not $realResult.release_gate_passed) { throw "Real-package algorithm self-test failed: $($realResult.errors -join '; ')" }

    $selfReview = $real | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $selfReview.experiential_review.reviewer_id = $selfReview.experiential_review.implementer_id
    $invalid = Test-ExternalQualificationPackage -Package $selfReview
    if ($invalid.contract_valid -or (($invalid.errors -join ' | ') -notmatch 'independent')) { throw 'Self-review rejection self-test failed.' }

    $shortSoak = $real | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $shortSoak.strict_soak.requested_seconds = 600
    $shortSoak.strict_soak.elapsed_seconds = 600
    $invalid = Test-ExternalQualificationPackage -Package $shortSoak
    if ($invalid.contract_valid -or (($invalid.errors -join ' | ') -notmatch '7200')) { throw 'Short-soak rejection self-test failed.' }

    $hostedTarget = $real | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $hostedTarget.hosted_runner = $true
    $invalid = Test-ExternalQualificationPackage -Package $hostedTarget
    if ($invalid.contract_valid -or (($invalid.errors -join ' | ') -notmatch 'hosted runner')) { throw 'Hosted-target rejection self-test failed.' }

    Write-Host 'EXTERNAL QUALIFICATION PACKAGE VALIDATOR PASS | fixture=reference-only | real-algorithm=pass | rejection-cases=3'
}

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    Invoke-SelfTest
    return
}

$resolvedPath = [System.IO.Path]::GetFullPath($PackagePath)
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { throw "Package not found: $resolvedPath" }
$package = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 20
$result = Test-ExternalQualificationPackage -Package $package
$result | ConvertTo-Json -Depth 8
if (-not $result.contract_valid) { throw "Qualification package is invalid: $($result.errors -join '; ')" }
if ($RequireReleaseGate -and -not $result.release_gate_passed) {
    throw "Qualification package is valid but non-qualifying: $($result.status)"
}
