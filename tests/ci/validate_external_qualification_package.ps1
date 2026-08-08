param(
    [string]$PackagePath = '',
    # Optional policy source root. When empty, the live repository checkout
    # provides data\release_qualification.json (validation-time anti-forgery).
    # Immutable bundle validation passes the extracted snapshot root instead so
    # the pinned bundle remains the only trusted contract source.
    [string]$PolicyRoot = '',
    [switch]$RequireReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = if ([string]::IsNullOrWhiteSpace($PolicyRoot)) {
    (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
} else {
    [System.IO.Path]::GetFullPath($PolicyRoot)
}
$policyHelpers = Join-Path $PSScriptRoot 'qualification_policy_helpers.ps1'
if (-not (Test-Path -LiteralPath $policyHelpers -PathType Leaf)) {
    throw "Qualification policy helpers not found: $policyHelpers"
}
. $policyHelpers
$PolicyContext = Get-ReleaseQualificationPolicyContext -ProjectRoot $ProjectRoot
$HardwarePolicies = @{
    minimum = New-HardwareQualificationPolicySnapshot -PolicyContext $PolicyContext -Tier 'minimum'
    recommended = New-HardwareQualificationPolicySnapshot -PolicyContext $PolicyContext -Tier 'recommended'
}
$StrictSoakPolicy = New-StrictSoakPolicySnapshot -PolicyContext $PolicyContext
$SchemaVersion = 2
$StrictSoakSeconds = [int]$StrictSoakPolicy.duration_seconds_min
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
    $value = ([string](Get-Field $Object $Name '')).Trim()
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

function Add-ExpectedValueError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Actual,
        [string]$Expected,
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Actual) -or $Actual -ne $Expected) {
        $Errors.Add("$Label does not match package build")
    }
}

function Add-ChildConsistencyErrors {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [object]$Child,
        [string]$Source,
        [bool]$ReferenceOnly,
        [string]$Label
    )
    if ([string](Get-Field $Child 'evidence_source' '') -ne $Source) {
        $Errors.Add("$Label evidence_source does not match package")
    }
    if ([bool](Get-Field $Child 'reference_only' (-not $ReferenceOnly)) -ne $ReferenceOnly) {
        $Errors.Add("$Label reference_only does not match package")
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
    $commitSha = ([string](Get-Field $build 'commit_sha' '')).Trim().ToLowerInvariant()
    $executableSha = ([string](Get-Field $build 'executable_sha256' '')).Trim().ToLowerInvariant()
    $pckSha = ([string](Get-Field $build 'pck_sha256' '')).Trim().ToLowerInvariant()

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
    $reviewBuild = Get-Field $review 'build' $null
    Add-ExpectedValueError $errors ([string](Get-Field $reviewBuild 'commit_sha' '')) $commitSha 'review commit'
    Add-ExpectedValueError $errors ([string](Get-Field $reviewBuild 'executable_sha256' '')) $executableSha 'review executable'
    Add-ExpectedValueError $errors ([string](Get-Field $reviewBuild 'pck_sha256' '')) $pckSha 'review PCK'

    $requireReal = $source -eq 'target_hardware'
    $hardwareEntries = @(Get-Field $Package 'hardware_qualification' @())
    $seenTiers = @{}
    foreach ($entry in $hardwareEntries) {
        $tier = [string](Get-Field $entry 'tier' '')
        if ($tier -notin $RequiredTiers) {
            $errors.Add("hardware tier is unsupported: $tier")
            continue
        }
        if ($seenTiers.ContainsKey($tier)) { $errors.Add("hardware tier is duplicated: $tier") }
        $seenTiers[$tier] = $true
        Add-ChildConsistencyErrors $errors $entry $source $referenceOnly 'hardware'
        if ([int](Get-Field $entry 'schema_version' 0) -ne 2) {
            $errors.Add("hardware $tier schema_version must equal 2")
        }
        if (-not [bool](Get-Field $entry 'exact_final_package_reused' $false)) {
            $errors.Add("hardware $tier must attest exact final package reuse")
        }
        $expectedHardwarePolicy = $HardwarePolicies[$tier]
        foreach ($policyError in @(Get-HardwarePolicySnapshotErrors `
            -Snapshot (Get-Field $entry 'qualification_policy' $null) `
            -Expected $expectedHardwarePolicy)) {
            $errors.Add("hardware $tier`: $policyError")
        }
        foreach ($metricError in @(Get-HardwareMetricEvaluationErrors `
            -RecordedEvaluation (Get-Field $entry 'metric_evaluation' $null) `
            -MetricPolicy $expectedHardwarePolicy.metrics `
            -RequiredProfiles $RequiredProfiles)) {
            $errors.Add("hardware $tier`: $metricError")
        }
        Add-RequiredTextError $errors $entry 'operator_id'
        Add-RequiredHashError $errors $entry 'machine_fingerprint_sha256' 64
        Add-RequiredTextError $errors $entry 'cpu'
        Add-RequiredTextError $errors $entry 'gpu'
        Add-RequiredTextError $errors $entry 'os'
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
        Add-RequiredTextError $errors $storage 'model'
        $profiles = @{}
        foreach ($profile in @(Get-Field $entry 'profiles' @())) { $profiles[[string]$profile] = $true }
        foreach ($profile in $RequiredProfiles) {
            if (-not $profiles.ContainsKey($profile)) { $errors.Add("hardware $tier is missing profile $profile") }
        }
        $entryBuild = Get-Field $entry 'build' $null
        Add-ExpectedValueError $errors ([string](Get-Field $entryBuild 'executable_sha256' '')) $executableSha "hardware $tier executable"
        Add-ExpectedValueError $errors ([string](Get-Field $entryBuild 'pck_sha256' '')) $pckSha "hardware $tier PCK"
    }
    foreach ($tier in $RequiredTiers) {
        if (-not $seenTiers.ContainsKey($tier)) { $errors.Add("hardware qualification is missing tier: $tier") }
    }

    $soak = Get-Field $Package 'strict_soak' $null
    Add-ChildConsistencyErrors $errors $soak $source $referenceOnly 'strict soak'
    if ([int](Get-Field $soak 'schema_version' 0) -ne 2) { $errors.Add('strict soak schema_version must equal 2') }
    if (-not [bool](Get-Field $soak 'exact_final_package_reused' $false)) {
        $errors.Add('strict soak must attest exact final package reuse')
    }
    foreach ($policyError in @(Get-StrictSoakPolicySnapshotErrors `
        -Snapshot (Get-Field $soak 'qualification_policy' $null) `
        -Expected $StrictSoakPolicy)) {
        $errors.Add($policyError)
    }
    $requested = [long](Get-Field $soak 'requested_seconds' 0)
    $elapsed = [long](Get-Field $soak 'elapsed_seconds' 0)
    $soakReference = [bool](Get-Field $soak 'reference_only' $false)
    if ($requested -le 0 -or $elapsed -le 0) { $errors.Add('strict soak durations must be positive') }
    if ($requireReal) {
        if ($requested -lt $StrictSoakSeconds -or $elapsed -lt $StrictSoakSeconds) {
            $errors.Add("target-hardware soak must run for at least $StrictSoakSeconds seconds")
        }
        if ($soakReference) { $errors.Add('target-hardware soak cannot be reference_only') }
        if (-not [bool](Get-Field $soak 'target_hardware' $false)) { $errors.Add('strict soak must attest target_hardware') }
    } else {
        if (-not $soakReference) { $errors.Add('non-target soak must be reference_only') }
        if ($requested -lt $StrictSoakSeconds) { $warnings.Add("reference soak is shorter than the commercial $StrictSoakSeconds-second gate") }
    }
    $soakProfiles = @((Get-Field $soak 'profiles' @()) | ForEach-Object { [string]$_ })
    $uniqueSoakProfiles = @($soakProfiles | Sort-Object -Unique)
    foreach ($profile in $RequiredProfiles) {
        if ($profile -notin $uniqueSoakProfiles) { $errors.Add("strict soak is missing profile $profile") }
    }
    if ($uniqueSoakProfiles.Count -ne $RequiredProfiles.Count -or [int](Get-Field $soak 'profile_count' 0) -ne $RequiredProfiles.Count) {
        $errors.Add("strict soak must cover exactly $($RequiredProfiles.Count) formal profiles")
    }
    $completedRoutes = [int](Get-Field $soak 'completed_routes' 0)
    $cycleCount = [int](Get-Field $soak 'cycle_count' 0)
    if ($completedRoutes -le 0 -or $cycleCount -ne $completedRoutes) {
        $errors.Add('strict soak completed_routes must be positive and equal cycle_count')
    }
    if ($requireReal -and $completedRoutes -lt [int]$StrictSoakPolicy.minimum_completed_routes) {
        $errors.Add("target-hardware soak must complete at least $($StrictSoakPolicy.minimum_completed_routes) routes")
    } elseif (-not $requireReal -and $completedRoutes -lt $RequiredProfiles.Count) {
        $errors.Add("reference soak must complete at least $($RequiredProfiles.Count) routes")
    } elseif (-not $requireReal -and $completedRoutes -lt [int]$StrictSoakPolicy.minimum_completed_routes) {
        $warnings.Add("reference soak completed fewer than the commercial $($StrictSoakPolicy.minimum_completed_routes)-route gate")
    }
    $fatalDiagnostics = [int](Get-Field $soak 'fatal_diagnostics_count' -1)
    if ($fatalDiagnostics -lt 0 -or $fatalDiagnostics -gt [int]$StrictSoakPolicy.fatal_diagnostics_max) {
        $errors.Add('strict soak fatal diagnostics exceed policy')
    }
    $transportCount = [int](Get-Field $soak 'post_spawn_transport_count' -1)
    if ($transportCount -lt 0 -or $transportCount -gt [int]$StrictSoakPolicy.route_transport_after_spawn_max) {
        $errors.Add('strict soak post-spawn transport exceeds policy')
    }
    if ([int](Get-Field $soak 'player_transform_writes' -1) -ne 0) {
        $errors.Add('strict soak player_transform_writes must be zero')
    }
    $firstWorkingSet = Get-Field $soak 'working_set_first_p95_mib' $null
    $lastWorkingSet = Get-Field $soak 'working_set_last_p95_mib' $null
    $recordedGrowth = Get-Field $soak 'memory_growth_percent' $null
    if (-not (Test-QualificationFiniteNumber $firstWorkingSet) -or [double]$firstWorkingSet -le 0.0 -or -not (Test-QualificationFiniteNumber $lastWorkingSet) -or [double]$lastWorkingSet -le 0.0 -or -not (Test-QualificationFiniteNumber $recordedGrowth)) {
        $errors.Add('strict soak Working Set growth evidence must be finite and positive')
    } else {
        $computedGrowth = [math]::Round((([double]$lastWorkingSet - [double]$firstWorkingSet) / [double]$firstWorkingSet) * 100.0, 4)
        if ([math]::Abs($computedGrowth - [double]$recordedGrowth) -gt 0.0001) {
            $errors.Add('strict soak memory_growth_percent does not match Working Set evidence')
        }
        if ([double]$recordedGrowth -gt [double]$StrictSoakPolicy.memory_growth_percent_max) {
            $errors.Add('strict soak Working Set growth exceeds policy')
        }
    }
    $lifecycleSummary = Get-Field $soak 'lifecycle' $null
    foreach ($lifecycleError in @(Get-LifecycleSummaryErrors -Summary $lifecycleSummary)) {
        $errors.Add($lifecycleError)
    }
    if ([int](Get-Field $soak 'authoritative_cycle_lifecycle_count' -1) -ne $completedRoutes) {
        $errors.Add('strict soak authoritative cycle lifecycle count must equal completed routes')
    }
    if (-not [bool](Get-Field $soak 'clean_exit' $false)) { $errors.Add('strict soak must end with a clean exit') }
    if ([int](Get-Field $soak 'crash_count' -1) -ne 0) { $errors.Add('strict soak crash_count must be zero') }
    if ([bool](Get-Field $soak 'timed_out' $true)) { $errors.Add('strict soak must not time out') }
    if ([string](Get-Field $soak 'result' '') -ne 'pass') { $errors.Add('strict soak result must be pass') }
    Add-RequiredHashError $errors $soak 'lifecycle_report_sha256' 64
    Add-RequiredHashError $errors $soak 'soak_report_sha256' 64
    Add-RequiredHashError $errors $soak 'progress_journal_sha256' 64
    Add-ExpectedValueError $errors ([string](Get-Field $soak 'executable_sha256' '')) $executableSha 'strict soak executable'
    Add-ExpectedValueError $errors ([string](Get-Field $soak 'pck_sha256' '')) $pckSha 'strict soak PCK'

    $faultLab = Get-Field $Package 'fault_lab' $null
    Add-RequiredTextError $errors $faultLab 'operator_id'
    $faultOperator = ([string](Get-Field $faultLab 'operator_id' '')).Trim()
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
        Add-ChildConsistencyErrors $errors $scenario $source $referenceOnly 'fault scenario'
        Add-RequiredTextError $errors $scenario 'operator_id'
        if (([string](Get-Field $scenario 'operator_id' '')).Trim() -ne $faultOperator) {
            $errors.Add("fault scenario operator does not match fault lab: $scenarioType")
        }
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
        Add-RequiredHashError $errors $scenario 'before_world_sha256' 64
        Add-RequiredHashError $errors $scenario 'after_world_sha256' 64
        $scenarioBuild = Get-Field $scenario 'build' $null
        Add-ExpectedValueError $errors ([string](Get-Field $scenarioBuild 'executable_sha256' '')) $executableSha "fault $scenarioType executable"
        Add-ExpectedValueError $errors ([string](Get-Field $scenarioBuild 'pck_sha256' '')) $pckSha "fault $scenarioType PCK"
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
        Add-RequiredTextError $errors $owner 'owner_id'
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
    $commit = 'a' * 40
    $exe = '1' * 64
    $pck = '2' * 64
    $hardware = foreach ($tier in $RequiredTiers) {
        $tierPolicy = $HardwarePolicies[$tier]
        $metricProfiles = foreach ($profile in $RequiredProfiles) {
            [pscustomobject][ordered]@{
                profile_id = $profile
                avg_fps = [double]$tierPolicy.metrics.avg_fps_min + 10.0
                one_percent_low_fps = [double]$tierPolicy.metrics.one_percent_low_fps_min + 5.0
                frame_ms_p95 = [double]$tierPolicy.metrics.frame_ms_p95_max * 0.8
                frame_ms_p99 = [double]$tierPolicy.metrics.frame_ms_p99_max * 0.8
                frame_budget_miss_30fps_percent = [double]$tierPolicy.metrics.frame_budget_miss_30fps_percent_max * 0.5
                world_start_ms = [double]$tierPolicy.metrics.profile_load_ms_max * 0.8
                working_set_p95_mib = [double]$tierPolicy.metrics.working_set_p95_mib_max * 0.8
            }
        }
        [pscustomobject]@{
            schema_version = 2; exact_final_package_reused = $true
            tier = $tier; evidence_source = $Source; reference_only = $ReferenceOnly
            operator_id = "operator-$tier"; operator_attested = $false
            machine_fingerprint_sha256 = 'b' * 64; cpu = 'fixture cpu'; gpu = 'fixture gpu'
            ram_gib = 16; os = 'Windows fixture'
            storage = [pscustomobject]@{ drive_type = 'ssd'; model = 'fixture storage' }
            profiles = @($RequiredProfiles); started_at_unix = 1000; completed_at_unix = 1050; result = 'pass'
            qualification_policy = $tierPolicy
            metric_evaluation = Get-HardwareMetricEvaluation -ProfileRecords @($metricProfiles) -MetricPolicy $tierPolicy.metrics -RequiredProfiles $RequiredProfiles
            build = [pscustomobject]@{ executable_sha256 = $exe; pck_sha256 = $pck }
        }
    }
    $scenarios = foreach ($scenarioType in $RequiredFaultScenarios) {
        [pscustomobject]@{
            type = $scenarioType; evidence_source = $Source; reference_only = $ReferenceOnly
            operator_id = 'fault-operator'; attested_real = $false
            interruption_observed = $true; recovery_verified = $true; world_integrity_verified = $true
            before_world_sha256 = 'd' * 64; after_world_sha256 = 'e' * 64
            build = [pscustomobject]@{ executable_sha256 = $exe; pck_sha256 = $pck }
        }
    }
    return [pscustomobject]@{
        schema_version = $SchemaVersion; package_id = 'qualification-fixture'
        fixture_mode = $FixtureMode; reference_only = $ReferenceOnly
        evidence_source = $Source; hosted_runner = $Source -eq 'hosted_reference'
        build = [pscustomobject]@{ commit_sha = $commit; executable_sha256 = $exe; pck_sha256 = $pck; version = 'fixture' }
        experiential_review = [pscustomobject]@{
            reviewer_id = 'reviewer-b'; implementer_id = 'implementer-a'; independent = $true
            signed_at_unix = 2000; result = 'pass'; blockers = @()
            checklist = [pscustomobject]@{
                fresh_install = $true; new_world = $true; save_reload = $true
                five_profiles = $true; input_and_ui = $true; quit_and_restart = $true
            }
            build = [pscustomobject]@{ commit_sha = $commit; executable_sha256 = $exe; pck_sha256 = $pck }
        }
        hardware_qualification = @($hardware)
        strict_soak = [pscustomobject]@{
            schema_version = 2; exact_final_package_reused = $true
            evidence_source = $Source; reference_only = $ReferenceOnly; target_hardware = $false
            requested_seconds = 600; elapsed_seconds = 600; clean_exit = $true
            crash_count = 0; timed_out = $false; result = 'pass'
            qualification_policy = $StrictSoakPolicy
            cycle_count = 5; completed_routes = 5; profile_count = 5; profiles = @($RequiredProfiles)
            fatal_diagnostics_count = 0; post_spawn_transport_count = 0; player_transform_writes = 0
            working_set_first_p95_mib = 100.0; working_set_last_p95_mib = 110.0; memory_growth_percent = 10.0
            authoritative_cycle_lifecycle_count = 5
            lifecycle = [pscustomobject]@{
                schema_version = 1; release_build = $true; engine_version = '4.7.fixture'; captured_unix = 1500
                first_world_profile_id = 'star_continent'; first_world_id = 'fixture-world'
                first_save_success = $true; first_save_world_id = 'fixture-world'; first_save_bytes = 1024
                world_save_identity_matches = $true; timings_monotonic = $true
                quit_attempt_count = 1; quit_source = 'release_smoke'; quit_prepared = $true
                termination_reason = 'prepared_quit'; service_hub_request_count = 1
                service_hub_success_count = 1; service_hub_failure_count = 0
                game_request_count = 1; game_success_count = 1; game_failure_count = 0
                authoritative_clean_quit = $true
            }
            executable_sha256 = $exe; pck_sha256 = $pck
            lifecycle_report_sha256 = '3' * 64; soak_report_sha256 = '4' * 64; progress_journal_sha256 = '5' * 64
        }
        fault_lab = [pscustomobject]@{ operator_id = 'fault-operator'; result = 'pass'; scenarios = @($scenarios) }
        findings = @()
    }
}

function ConvertTo-RealPackage {
    param([object]$Package)
    $Package.evidence_source = 'target_hardware'; $Package.reference_only = $false; $Package.fixture_mode = $false; $Package.hosted_runner = $false
    foreach ($entry in @($Package.hardware_qualification)) {
        $entry.evidence_source = 'target_hardware'; $entry.reference_only = $false; $entry.operator_attested = $true
    }
    $Package.strict_soak.evidence_source = 'target_hardware'; $Package.strict_soak.reference_only = $false
    $Package.strict_soak.target_hardware = $true
    $Package.strict_soak.requested_seconds = [int]$StrictSoakPolicy.duration_seconds_min
    $Package.strict_soak.elapsed_seconds = [int]$StrictSoakPolicy.duration_seconds_min
    $Package.strict_soak.cycle_count = [int]$StrictSoakPolicy.minimum_completed_routes
    $Package.strict_soak.completed_routes = [int]$StrictSoakPolicy.minimum_completed_routes
    $Package.strict_soak.authoritative_cycle_lifecycle_count = [int]$StrictSoakPolicy.minimum_completed_routes
    foreach ($scenario in @($Package.fault_lab.scenarios)) {
        $scenario.evidence_source = 'target_hardware'; $scenario.reference_only = $false; $scenario.attested_real = $true
    }
    $Package | Add-Member -NotePropertyName release_owner_attestation -NotePropertyValue ([pscustomobject]@{
        owner_id = 'release-owner'; signed_at_unix = 3000
        all_artifacts_attached = $true; approved_for_release = $true
    }) -Force
}

function Assert-Invalid {
    param([object]$Package, [string]$Fragment, [string]$Name)
    $result = Test-ExternalQualificationPackage $Package
    if ($result.contract_valid -or (($result.errors -join ' | ') -notmatch [regex]::Escape($Fragment))) {
        throw "$Name rejection self-test failed: $($result.errors -join '; ')"
    }
}

function Invoke-SelfTest {
    $fixture = New-FixturePackage
    $fixtureResult = Test-ExternalQualificationPackage $fixture
    if (-not $fixtureResult.contract_valid -or $fixtureResult.release_gate_passed) { throw 'Fixture contract self-test failed.' }

    $hosted = New-FixturePackage -Source 'hosted_reference' -FixtureMode $false -ReferenceOnly $true
    $hostedResult = Test-ExternalQualificationPackage $hosted
    if (-not $hostedResult.contract_valid -or $hostedResult.release_gate_passed) { throw 'Hosted reference self-test failed.' }

    $real = New-FixturePackage
    ConvertTo-RealPackage $real
    $realResult = Test-ExternalQualificationPackage $real
    if (-not $realResult.contract_valid -or -not $realResult.release_gate_passed) { throw "Real-package self-test failed: $($realResult.errors -join '; ')" }

    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.experiential_review.reviewer_id = $copy.experiential_review.implementer_id
    Assert-Invalid $copy 'independent' 'self-review'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.requested_seconds = 600; $copy.strict_soak.elapsed_seconds = 600
    Assert-Invalid $copy '7200' 'short-soak'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.hosted_runner = $true
    Assert-Invalid $copy 'hosted runner' 'hosted-target'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.experiential_review.build.commit_sha = 'f' * 40
    Assert-Invalid $copy 'review commit' 'tampered-review'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.hardware_qualification[0].build.executable_sha256 = 'f' * 64
    Assert-Invalid $copy 'hardware minimum executable' 'tampered-hardware'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.reference_only = $true
    Assert-Invalid $copy 'reference_only does not match' 'mixed-reference'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.fault_lab.scenarios[0].operator_id = 'another-operator'
    Assert-Invalid $copy 'operator does not match' 'mixed-fault-operator'

    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.hardware_qualification[0].metric_evaluation.profiles[0].avg_fps = 0.0
    Assert-Invalid $copy 'hardware metric threshold failed' 'forged-performance-pass'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.hardware_qualification[1].qualification_policy.sha256 = 'f' * 64
    Assert-Invalid $copy 'does not match repository policy' 'forged-policy'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.completed_routes = [int]$StrictSoakPolicy.minimum_completed_routes - 1
    $copy.strict_soak.cycle_count = $copy.strict_soak.completed_routes
    $copy.strict_soak.authoritative_cycle_lifecycle_count = $copy.strict_soak.completed_routes
    Assert-Invalid $copy 'complete at least' 'short-route-count'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.working_set_last_p95_mib = 140.0
    $copy.strict_soak.memory_growth_percent = 40.0
    Assert-Invalid $copy 'Working Set growth exceeds policy' 'memory-growth'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.fatal_diagnostics_count = 1
    Assert-Invalid $copy 'fatal diagnostics exceed policy' 'fatal-diagnostic'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.strict_soak.lifecycle.termination_reason = 'scene_exit_without_prepared_quit'
    $copy.strict_soak.lifecycle.quit_prepared = $false
    $copy.strict_soak.lifecycle.authoritative_clean_quit = $false
    Assert-Invalid $copy 'termination_reason must equal prepared_quit' 'dirty-lifecycle'
    $copy = $real | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.hardware_qualification[0].exact_final_package_reused = $false
    Assert-Invalid $copy 'exact final package reuse' 'package-reexport'

    Write-Host 'EXTERNAL QUALIFICATION PACKAGE VALIDATOR PASS | schema=2 | fixture=reference-only | real-algorithm=pass | rejection-cases=14'
}

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    Invoke-SelfTest
    return
}

$resolvedPath = [System.IO.Path]::GetFullPath($PackagePath)
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { throw "Package not found: $resolvedPath" }
$package = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 100
$result = Test-ExternalQualificationPackage $package
$result | ConvertTo-Json -Depth 10
if (-not $result.contract_valid) { throw "Qualification package is invalid: $($result.errors -join '; ')" }
if ($RequireReleaseGate -and -not $result.release_gate_passed) {
    throw "Qualification package is valid but non-qualifying: $($result.status)"
}
