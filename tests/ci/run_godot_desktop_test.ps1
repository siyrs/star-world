param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$RenderingMethod = 'gl_compatibility',
    [int]$TimeoutMilliseconds = 60000,
    [string]$UserDataDirectory = ''
)

$ErrorActionPreference = 'Stop'

$projectFullPath = [System.IO.Path]::GetFullPath($ProjectRoot)
# Callers may pass either a project-relative output path (CI jobs) or an
# already-rooted evidence path (local aggregate runners). Join-Path would
# concatenate a rooted path onto the project root and produce an illegal
# doubled path, so resolve rooted inputs directly.
$outputFullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $OutputPath))
}
$outputDirectory = Split-Path -Parent $outputFullPath
$outputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($outputFullPath)
$stdoutPath = Join-Path $outputDirectory "$outputBaseName.stdout.log"
$stderrPath = Join-Path $outputDirectory "$outputBaseName.stderr.log"

if ([string]::IsNullOrWhiteSpace($UserDataDirectory)) {
    $UserDataDirectory = Join-Path $outputDirectory "$outputBaseName.userdata"
}
$userDataFullPath = if ([System.IO.Path]::IsPathRooted($UserDataDirectory)) {
    [System.IO.Path]::GetFullPath($UserDataDirectory)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectFullPath $UserDataDirectory))
}
$allowedUserDataPrefix = $outputDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$buildRoot = [System.IO.Path]::GetFullPath((Join-Path $projectFullPath 'build'))
$allowedBuildPrefix = $buildRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$insideOutput = $userDataFullPath.StartsWith($allowedUserDataPrefix, [System.StringComparison]::OrdinalIgnoreCase)
$insideBuild = $userDataFullPath.StartsWith($allowedBuildPrefix, [System.StringComparison]::OrdinalIgnoreCase)
if (-not $insideOutput -and -not $insideBuild) {
    throw "Desktop test user-data directory must remain under the test output or project build directory: $userDataFullPath"
}
$roamingPath = Join-Path $userDataFullPath 'Roaming'
$localPath = Join-Path $userDataFullPath 'Local'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Remove-Item -LiteralPath $outputFullPath, $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $userDataFullPath) {
    Remove-Item -LiteralPath $userDataFullPath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $roamingPath, $localPath | Out-Null

# GitHub Actions jobs use isolated clean workspaces. A successful import in the
# headless regression job does not populate this desktop job's .godot cache.
# Preloaded fonts and other imported resources therefore failed to compile before
# the first desktop test. Import once per desktop job and persist a local marker so
# the remaining acceptance scripts reuse the same verified cache.
$importMarker = Join-Path $projectFullPath '.godot\desktop-import-ready'
if (-not (Test-Path -LiteralPath $importMarker)) {
    $importRunner = Join-Path $projectFullPath 'tests\ci\Invoke-Godot.ps1'
    if (-not (Test-Path -LiteralPath $importRunner)) {
        throw "Missing strict Godot import runner: $importRunner"
    }
    Write-Host 'Preparing isolated desktop acceptance import cache...'
    $previousAppData = $env:APPDATA
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $env:APPDATA = $roamingPath
        $env:LOCALAPPDATA = $localPath
        & $importRunner `
            -Godot $Godot `
            -Arguments "--headless --path `"$projectFullPath`" --editor --quit" `
            -TimeoutMilliseconds 600000
    } finally {
        $env:APPDATA = $previousAppData
        $env:LOCALAPPDATA = $previousLocalAppData
    }
    New-Item -ItemType File -Force -Path $importMarker | Out-Null
}

function Assert-NoFatalGodotLog {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $fatalPatterns = @(
        'SCRIPT ERROR',
        'Parse Error',
        'ObjectDB instances were leaked',
        'Leaked instance:',
        'Resources still in use at exit',
        'Condition "!is_inside_tree()" is true'
    )
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $matches = @(Select-String -LiteralPath $path -Pattern $fatalPatterns -SimpleMatch)
        if ($matches.Count -eq 0) {
            continue
        }
        $details = ($matches | ForEach-Object {
            "$($_.Path):$($_.LineNumber): $($_.Line)"
        }) -join [Environment]::NewLine
        throw "Fatal Godot desktop diagnostics were found:$([Environment]::NewLine)$details"
    }
}

$outputArgumentPath = $outputFullPath.Replace('\', '/')
$arguments = @(
    '--path', $projectFullPath,
    '--rendering-method', $RenderingMethod,
    '--script', $ScriptPath,
    '--',
    "--capture-output=$outputArgumentPath"
)

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $Godot
$startInfo.WorkingDirectory = $projectFullPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.Environment['APPDATA'] = $roamingPath
$startInfo.Environment['LOCALAPPDATA'] = $localPath
foreach ($argument in $arguments) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Unable to start Godot desktop test: $ScriptPath"
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = -not $process.WaitForExit($TimeoutMilliseconds)
if ($timedOut) {
    $process.Kill($true)
    $process.WaitForExit()
} else {
    $process.WaitForExit()
}

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $stdoutPath -Value $stdout -Encoding utf8
Set-Content -LiteralPath $stderrPath -Value $stderr -Encoding utf8

if (-not [string]::IsNullOrWhiteSpace($stdout)) {
    Write-Host '--- Godot desktop stdout ---'
    Write-Host $stdout
}
if (-not [string]::IsNullOrWhiteSpace($stderr)) {
    Write-Host '--- Godot desktop stderr ---'
    Write-Host $stderr
}

if ($timedOut) {
    throw "Godot desktop test timed out after $TimeoutMilliseconds ms: $ScriptPath"
}
Assert-NoFatalGodotLog -Paths @($stdoutPath, $stderrPath)
if ($process.ExitCode -ne 0) {
    throw "Godot desktop test failed: $ScriptPath (exit $($process.ExitCode)); logs=$stdoutPath,$stderrPath"
}
if (-not (Test-Path -LiteralPath $outputFullPath)) {
    throw "Desktop test did not create its requested screenshot: $outputFullPath"
}
if ((Get-Item -LiteralPath $outputFullPath).Length -le 0) {
    throw "Desktop test created an empty screenshot: $outputFullPath"
}

Write-Host "PASS desktop evidence | script=$ScriptPath | capture=$outputFullPath"
