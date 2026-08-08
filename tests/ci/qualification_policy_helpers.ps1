function Get-QualificationField {
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

function Test-QualificationFiniteNumber {
    param([object]$Value)
    try {
        $number = [double]$Value
        return [double]::IsFinite($number)
    } catch {
        return $false
    }
}

function Get-ReleaseQualificationPolicyContext {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)
    $path = Join-Path $root 'data\release_qualification.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Qualification policy missing: $path"
    }
    $policy = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 30
    if ([int](Get-QualificationField $policy 'schema_version' 0) -le 0) {
        throw 'Qualification policy schema_version must be positive.'
    }
    foreach ($tier in @('minimum', 'recommended')) {
        $tierPolicy = Get-QualificationField (Get-QualificationField $policy 'tiers' $null) $tier $null
        if ($null -eq $tierPolicy) { throw "Qualification policy tier missing: $tier" }
        $metrics = Get-QualificationField $tierPolicy 'metrics' $null
        foreach ($name in @(
            'avg_fps_min',
            'one_percent_low_fps_min',
            'frame_ms_p95_max',
            'frame_ms_p99_max',
            'frame_budget_miss_30fps_percent_max',
            'profile_load_ms_max',
            'working_set_p95_mib_max'
        )) {
            if (-not (Test-QualificationFiniteNumber (Get-QualificationField $metrics $name $null))) {
                throw "Qualification policy metric is missing or non-finite: $tier.$name"
            }
        }
    }
    $soak = Get-QualificationField $policy 'soak' $null
    foreach ($name in @(
        'duration_seconds_min',
        'minimum_completed_routes',
        'fatal_diagnostics_max',
        'memory_growth_percent_max',
        'route_transport_after_spawn_max'
    )) {
        if (-not (Test-QualificationFiniteNumber (Get-QualificationField $soak $name $null))) {
            throw "Qualification soak policy is missing or non-finite: $name"
        }
    }
    return [pscustomobject]@{
        ProjectRoot = $root
        Path = $path
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        Policy = $policy
    }
}

function New-HardwareQualificationPolicySnapshot {
    param(
        [Parameter(Mandatory = $true)][object]$PolicyContext,
        [Parameter(Mandatory = $true)][ValidateSet('minimum', 'recommended')][string]$Tier
    )
    $policy = $PolicyContext.Policy
    $tierPolicy = $policy.tiers.$Tier
    return [ordered]@{
        schema_version = [int]$policy.schema_version
        sha256 = [string]$PolicyContext.Sha256
        product = [string]$policy.product
        platform = [string]$policy.platform
        rendering_method = [string]$policy.rendering_method
        resolution = @($policy.resolution | ForEach-Object { [int]$_ })
        tier = $Tier
        metrics = [ordered]@{
            avg_fps_min = [double]$tierPolicy.metrics.avg_fps_min
            one_percent_low_fps_min = [double]$tierPolicy.metrics.one_percent_low_fps_min
            frame_ms_p95_max = [double]$tierPolicy.metrics.frame_ms_p95_max
            frame_ms_p99_max = [double]$tierPolicy.metrics.frame_ms_p99_max
            frame_budget_miss_30fps_percent_max = [double]$tierPolicy.metrics.frame_budget_miss_30fps_percent_max
            profile_load_ms_max = [double]$tierPolicy.metrics.profile_load_ms_max
            working_set_p95_mib_max = [double]$tierPolicy.metrics.working_set_p95_mib_max
        }
    }
}

function New-StrictSoakPolicySnapshot {
    param([Parameter(Mandatory = $true)][object]$PolicyContext)
    $policy = $PolicyContext.Policy
    return [ordered]@{
        schema_version = [int]$policy.schema_version
        sha256 = [string]$PolicyContext.Sha256
        duration_seconds_min = [int]$policy.soak.duration_seconds_min
        all_profiles_required = [bool]$policy.soak.all_profiles_required
        minimum_completed_routes = [int]$policy.soak.minimum_completed_routes
        fatal_diagnostics_max = [int]$policy.soak.fatal_diagnostics_max
        memory_growth_percent_max = [double]$policy.soak.memory_growth_percent_max
        route_transport_after_spawn_max = [int]$policy.soak.route_transport_after_spawn_max
    }
}

function Test-QualificationNumberEqual {
    param([object]$Actual, [object]$Expected)
    if (-not (Test-QualificationFiniteNumber $Actual) -or -not (Test-QualificationFiniteNumber $Expected)) {
        return $false
    }
    return [math]::Abs(([double]$Actual) - ([double]$Expected)) -le 0.000001
}

function Get-HardwarePolicySnapshotErrors {
    param(
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][object]$Expected
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('schema_version', 'sha256', 'product', 'platform', 'rendering_method', 'tier')) {
        if ([string](Get-QualificationField $Snapshot $name '') -ne [string](Get-QualificationField $Expected $name '')) {
            $errors.Add("hardware qualification policy $name does not match repository policy")
        }
    }
    $actualResolution = @((Get-QualificationField $Snapshot 'resolution' @()) | ForEach-Object { [int]$_ })
    $expectedResolution = @((Get-QualificationField $Expected 'resolution' @()) | ForEach-Object { [int]$_ })
    if (($actualResolution -join 'x') -ne ($expectedResolution -join 'x')) {
        $errors.Add('hardware qualification policy resolution does not match repository policy')
    }
    $actualMetrics = Get-QualificationField $Snapshot 'metrics' $null
    $expectedMetrics = Get-QualificationField $Expected 'metrics' $null
    foreach ($name in @(
        'avg_fps_min',
        'one_percent_low_fps_min',
        'frame_ms_p95_max',
        'frame_ms_p99_max',
        'frame_budget_miss_30fps_percent_max',
        'profile_load_ms_max',
        'working_set_p95_mib_max'
    )) {
        if (-not (Test-QualificationNumberEqual (Get-QualificationField $actualMetrics $name $null) (Get-QualificationField $expectedMetrics $name $null))) {
            $errors.Add("hardware qualification policy metric $name does not match repository policy")
        }
    }
    return @($errors)
}

function Get-StrictSoakPolicySnapshotErrors {
    param(
        [Parameter(Mandatory = $true)][object]$Snapshot,
        [Parameter(Mandatory = $true)][object]$Expected
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('schema_version', 'sha256', 'all_profiles_required')) {
        if ([string](Get-QualificationField $Snapshot $name '') -ne [string](Get-QualificationField $Expected $name '')) {
            $errors.Add("strict soak policy $name does not match repository policy")
        }
    }
    foreach ($name in @(
        'duration_seconds_min',
        'minimum_completed_routes',
        'fatal_diagnostics_max',
        'memory_growth_percent_max',
        'route_transport_after_spawn_max'
    )) {
        if (-not (Test-QualificationNumberEqual (Get-QualificationField $Snapshot $name $null) (Get-QualificationField $Expected $name $null))) {
            $errors.Add("strict soak policy $name does not match repository policy")
        }
    }
    return @($errors)
}

function Get-HardwareMetricEvaluation {
    param(
        [Parameter(Mandatory = $true)][object[]]$ProfileRecords,
        [Parameter(Mandatory = $true)][object]$MetricPolicy,
        [Parameter(Mandatory = $true)][string[]]$RequiredProfiles
    )

    $rules = @(
        [pscustomobject]@{ Evidence = 'avg_fps'; Policy = 'avg_fps_min'; Direction = 'min' },
        [pscustomobject]@{ Evidence = 'one_percent_low_fps'; Policy = 'one_percent_low_fps_min'; Direction = 'min' },
        [pscustomobject]@{ Evidence = 'frame_ms_p95'; Policy = 'frame_ms_p95_max'; Direction = 'max' },
        [pscustomobject]@{ Evidence = 'frame_ms_p99'; Policy = 'frame_ms_p99_max'; Direction = 'max' },
        [pscustomobject]@{ Evidence = 'frame_budget_miss_30fps_percent'; Policy = 'frame_budget_miss_30fps_percent_max'; Direction = 'max' },
        [pscustomobject]@{ Evidence = 'world_start_ms'; Policy = 'profile_load_ms_max'; Direction = 'max' },
        [pscustomobject]@{ Evidence = 'working_set_p95_mib'; Policy = 'working_set_p95_mib_max'; Direction = 'max' }
    )
    $violations = [System.Collections.Generic.List[string]]::new()
    $evaluated = [System.Collections.Generic.List[object]]::new()
    foreach ($profileId in $RequiredProfiles) {
        $matches = @($ProfileRecords | Where-Object { [string](Get-QualificationField $_ 'profile_id' '') -eq $profileId })
        if ($matches.Count -ne 1) {
            $violations.Add("$profileId`: expected exactly one metric record, got $($matches.Count)")
            continue
        }
        $record = $matches[0]
        $assertions = [ordered]@{}
        $metricValues = [ordered]@{ profile_id = $profileId }
        $profilePass = $true
        foreach ($rule in $rules) {
            $actualValue = Get-QualificationField $record $rule.Evidence $null
            $thresholdValue = Get-QualificationField $MetricPolicy $rule.Policy $null
            $valid = (Test-QualificationFiniteNumber $actualValue) -and (Test-QualificationFiniteNumber $thresholdValue)
            $passed = $false
            if ($valid) {
                $actual = [double]$actualValue
                $threshold = [double]$thresholdValue
                $passed = $actual -ge 0.0 -and $(if ($rule.Direction -eq 'min') { $actual -ge $threshold } else { $actual -le $threshold })
                $metricValues[$rule.Evidence] = $actual
            } else {
                $metricValues[$rule.Evidence] = $null
            }
            $assertions[$rule.Policy] = $passed
            if (-not $passed) {
                $profilePass = $false
                $violations.Add("$profileId`: $($rule.Evidence) violates $($rule.Policy)")
            }
        }
        $metricValues['assertions'] = $assertions
        $metricValues['pass'] = $profilePass
        $evaluated.Add([pscustomobject]$metricValues)
    }
    return [pscustomobject][ordered]@{
        profile_count = $evaluated.Count
        assertion_count = $evaluated.Count * $rules.Count
        failure_count = $violations.Count
        passed = $violations.Count -eq 0 -and $evaluated.Count -eq $RequiredProfiles.Count
        violations = @($violations)
        profiles = @($evaluated)
    }
}

function Get-HardwareMetricEvaluationErrors {
    param(
        [Parameter(Mandatory = $true)][object]$RecordedEvaluation,
        [Parameter(Mandatory = $true)][object]$MetricPolicy,
        [Parameter(Mandatory = $true)][string[]]$RequiredProfiles
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $recordedProfiles = @((Get-QualificationField $RecordedEvaluation 'profiles' @()))
    $computed = Get-HardwareMetricEvaluation -ProfileRecords $recordedProfiles -MetricPolicy $MetricPolicy -RequiredProfiles $RequiredProfiles
    if (-not [bool]$computed.passed) {
        foreach ($violation in @($computed.violations)) { $errors.Add("hardware metric threshold failed: $violation") }
    }
    foreach ($name in @('profile_count', 'assertion_count', 'failure_count')) {
        if ([int](Get-QualificationField $RecordedEvaluation $name -1) -ne [int](Get-QualificationField $computed $name -2)) {
            $errors.Add("hardware metric evaluation $name does not match recomputed evidence")
        }
    }
    if ([bool](Get-QualificationField $RecordedEvaluation 'passed' $false) -ne [bool]$computed.passed) {
        $errors.Add('hardware metric evaluation passed does not match recomputed evidence')
    }
    if (@((Get-QualificationField $RecordedEvaluation 'violations' @())).Count -ne [int]$computed.failure_count) {
        $errors.Add('hardware metric evaluation violations do not match recomputed evidence')
    }
    foreach ($computedProfile in @($computed.profiles)) {
        $profileId = [string]$computedProfile.profile_id
        $matches = @($recordedProfiles | Where-Object { [string](Get-QualificationField $_ 'profile_id' '') -eq $profileId })
        if ($matches.Count -ne 1) { continue }
        $recordedAssertions = Get-QualificationField $matches[0] 'assertions' $null
        foreach ($assertion in $computedProfile.assertions.GetEnumerator()) {
            if ([bool](Get-QualificationField $recordedAssertions $assertion.Key $false) -ne [bool]$assertion.Value) {
                $errors.Add("hardware metric assertion $profileId.$($assertion.Key) does not match recomputed evidence")
            }
        }
        if ([bool](Get-QualificationField $matches[0] 'pass' $false) -ne [bool]$computedProfile.pass) {
            $errors.Add("hardware metric profile result does not match recomputed evidence: $profileId")
        }
    }
    return @($errors)
}

function Get-AuthoritativeLifecycleEvidence {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Lifecycle report not found: $resolved"
    }
    $report = Get-Content -LiteralPath $resolved -Raw | ConvertFrom-Json -Depth 50
    $errors = [System.Collections.Generic.List[string]]::new()
    $firstWorld = Get-QualificationField $report 'first_world' $null
    $firstSave = Get-QualificationField $report 'first_save' $null
    $quit = Get-QualificationField $report 'quit' $null
    $timings = Get-QualificationField $report 'timings' $null
    $serviceHub = Get-QualificationField $quit 'service_hub' $null
    $game = Get-QualificationField $quit 'game' $null
    $worldId = ([string](Get-QualificationField $firstWorld 'world_id' '')).Trim()
    $profileId = ([string](Get-QualificationField $firstWorld 'profile_id' '')).Trim()
    $saveWorldId = ([string](Get-QualificationField $firstSave 'world_id' '')).Trim()
    if ([int](Get-QualificationField $report 'schema_version' 0) -ne 1) { $errors.Add('lifecycle schema_version must equal 1') }
    if (-not [bool](Get-QualificationField $report 'release_build' $false)) { $errors.Add('lifecycle report must come from a release build') }
    if ([long](Get-QualificationField $report 'captured_unix' 0) -le 0) { $errors.Add('lifecycle captured_unix must be positive') }
    if ([string]::IsNullOrWhiteSpace([string](Get-QualificationField $report 'engine_version' ''))) { $errors.Add('lifecycle engine_version is required') }
    if ($profileId -notin @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')) { $errors.Add('lifecycle first world profile is not formal') }
    if ([string]::IsNullOrWhiteSpace($worldId)) { $errors.Add('lifecycle first world id is required') }
    if (-not [bool](Get-QualificationField $firstSave 'success' $false)) { $errors.Add('lifecycle first save must succeed') }
    if ([long](Get-QualificationField $firstSave 'bytes' 0) -le 0) { $errors.Add('lifecycle first save must persist bytes') }
    if ($saveWorldId -ne $worldId -or [string]::IsNullOrWhiteSpace($saveWorldId)) { $errors.Add('lifecycle first save world must match first playable world') }
    $timingNames = @(
        'service_ready_milliseconds',
        'scene_ready_milliseconds',
        'first_world_playable_milliseconds',
        'first_save_milliseconds',
        'quit_requested_milliseconds',
        'quit_completed_milliseconds'
    )
    $timingValues = @($timingNames | ForEach-Object { [double](Get-QualificationField $timings $_ -1.0) })
    $timingsMonotonic = $true
    for ($index = 0; $index -lt $timingValues.Count; $index++) {
        if (-not [double]::IsFinite($timingValues[$index]) -or $timingValues[$index] -lt 0.0) { $timingsMonotonic = $false }
        if ($index -gt 0 -and $timingValues[$index] -lt $timingValues[$index - 1]) { $timingsMonotonic = $false }
    }
    if (-not $timingsMonotonic) { $errors.Add('lifecycle timings must be finite, non-negative and monotonic') }
    if ([int](Get-QualificationField $quit 'attempt_count' 0) -lt 1) { $errors.Add('lifecycle authoritative quit must be attempted') }
    if ([string]::IsNullOrWhiteSpace([string](Get-QualificationField $quit 'source' ''))) { $errors.Add('lifecycle authoritative quit source is required') }
    if (-not [bool](Get-QualificationField $quit 'prepared' $false)) { $errors.Add('lifecycle authoritative quit must be prepared') }
    if ([string](Get-QualificationField $quit 'termination_reason' '') -ne 'prepared_quit') { $errors.Add('lifecycle termination_reason must equal prepared_quit') }
    foreach ($pair in @(
        [pscustomobject]@{ Label = 'service_hub'; Value = $serviceHub },
        [pscustomobject]@{ Label = 'game'; Value = $game }
    )) {
        if ([int](Get-QualificationField $pair.Value 'request_count' 0) -lt 1) { $errors.Add("lifecycle $($pair.Label) quit request_count must be positive") }
        if ([int](Get-QualificationField $pair.Value 'success_count' 0) -lt 1) { $errors.Add("lifecycle $($pair.Label) quit success_count must be positive") }
        if ([int](Get-QualificationField $pair.Value 'failure_count' -1) -ne 0) { $errors.Add("lifecycle $($pair.Label) quit failure_count must be zero") }
    }
    $summary = [ordered]@{
        schema_version = [int](Get-QualificationField $report 'schema_version' 0)
        release_build = [bool](Get-QualificationField $report 'release_build' $false)
        engine_version = [string](Get-QualificationField $report 'engine_version' '')
        captured_unix = [long](Get-QualificationField $report 'captured_unix' 0)
        first_world_profile_id = $profileId
        first_world_id = $worldId
        first_save_success = [bool](Get-QualificationField $firstSave 'success' $false)
        first_save_world_id = $saveWorldId
        first_save_bytes = [long](Get-QualificationField $firstSave 'bytes' 0)
        world_save_identity_matches = $saveWorldId -eq $worldId -and -not [string]::IsNullOrWhiteSpace($worldId)
        timings_monotonic = $timingsMonotonic
        quit_attempt_count = [int](Get-QualificationField $quit 'attempt_count' 0)
        quit_source = [string](Get-QualificationField $quit 'source' '')
        quit_prepared = [bool](Get-QualificationField $quit 'prepared' $false)
        termination_reason = [string](Get-QualificationField $quit 'termination_reason' '')
        service_hub_request_count = [int](Get-QualificationField $serviceHub 'request_count' 0)
        service_hub_success_count = [int](Get-QualificationField $serviceHub 'success_count' 0)
        service_hub_failure_count = [int](Get-QualificationField $serviceHub 'failure_count' -1)
        game_request_count = [int](Get-QualificationField $game 'request_count' 0)
        game_success_count = [int](Get-QualificationField $game 'success_count' 0)
        game_failure_count = [int](Get-QualificationField $game 'failure_count' -1)
        authoritative_clean_quit = $errors.Count -eq 0
    }
    return [pscustomobject]@{
        Path = $resolved
        Sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
        Valid = $errors.Count -eq 0
        Errors = @($errors)
        Summary = [pscustomobject]$summary
    }
}

function Get-LifecycleSummaryErrors {
    param([Parameter(Mandatory = $true)][object]$Summary)
    $errors = [System.Collections.Generic.List[string]]::new()
    if ([int](Get-QualificationField $Summary 'schema_version' 0) -ne 1) { $errors.Add('strict soak lifecycle schema_version must equal 1') }
    if (-not [bool](Get-QualificationField $Summary 'release_build' $false)) { $errors.Add('strict soak lifecycle must come from a release build') }
    if ([long](Get-QualificationField $Summary 'captured_unix' 0) -le 0) { $errors.Add('strict soak lifecycle captured_unix must be positive') }
    if ([string]::IsNullOrWhiteSpace([string](Get-QualificationField $Summary 'engine_version' ''))) { $errors.Add('strict soak lifecycle engine_version is required') }
    if ([string](Get-QualificationField $Summary 'first_world_profile_id' '') -notin @('star_continent', 'desert_ruins', 'frozen_wastes', 'sky_islands', 'abyss_world')) { $errors.Add('strict soak lifecycle first world profile is not formal') }
    $worldId = ([string](Get-QualificationField $Summary 'first_world_id' '')).Trim()
    if ([string]::IsNullOrWhiteSpace($worldId)) { $errors.Add('strict soak lifecycle first world id is required') }
    if (-not [bool](Get-QualificationField $Summary 'first_save_success' $false)) { $errors.Add('strict soak lifecycle first save must succeed') }
    if ([long](Get-QualificationField $Summary 'first_save_bytes' 0) -le 0) { $errors.Add('strict soak lifecycle first save must persist bytes') }
    if (-not [bool](Get-QualificationField $Summary 'world_save_identity_matches' $false) -or [string](Get-QualificationField $Summary 'first_save_world_id' '') -ne $worldId) { $errors.Add('strict soak lifecycle world/save identity must match') }
    if (-not [bool](Get-QualificationField $Summary 'timings_monotonic' $false)) { $errors.Add('strict soak lifecycle timings must be monotonic') }
    if ([int](Get-QualificationField $Summary 'quit_attempt_count' 0) -lt 1) { $errors.Add('strict soak lifecycle authoritative quit must be attempted') }
    if ([string]::IsNullOrWhiteSpace([string](Get-QualificationField $Summary 'quit_source' ''))) { $errors.Add('strict soak lifecycle quit_source is required') }
    if (-not [bool](Get-QualificationField $Summary 'quit_prepared' $false)) { $errors.Add('strict soak lifecycle authoritative quit must be prepared') }
    if ([string](Get-QualificationField $Summary 'termination_reason' '') -ne 'prepared_quit') { $errors.Add('strict soak lifecycle termination_reason must equal prepared_quit') }
    foreach ($prefix in @('service_hub', 'game')) {
        if ([int](Get-QualificationField $Summary "${prefix}_request_count" 0) -lt 1) { $errors.Add("strict soak lifecycle $prefix request_count must be positive") }
        if ([int](Get-QualificationField $Summary "${prefix}_success_count" 0) -lt 1) { $errors.Add("strict soak lifecycle $prefix success_count must be positive") }
        if ([int](Get-QualificationField $Summary "${prefix}_failure_count" -1) -ne 0) { $errors.Add("strict soak lifecycle $prefix failure_count must be zero") }
    }
    if (-not [bool](Get-QualificationField $Summary 'authoritative_clean_quit' $false)) { $errors.Add('strict soak lifecycle authoritative_clean_quit must be true') }
    return @($errors)
}
