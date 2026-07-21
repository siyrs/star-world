$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$helper = Join-Path $root 'src\update\windows_update_helper.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("starworld-updater-" + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $testRoot 'StarWorld'
$payload = Join-Path $testRoot 'payload'
$package = Join-Path $testRoot 'StarWorld-Windows-x86_64.zip'
$result = Join-Path $testRoot 'install-result.json'
$failureEvidence = Join-Path $root 'build\windows-update-helper-failure.txt'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Resolve-CSharpCompiler {
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $command = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw 'A Windows C# compiler is required for the real relaunch acceptance fixture.'
}

function Wait-ForProcessExit([int]$ProcessId, [int]$TimeoutSeconds = 10) {
    if ($ProcessId -le 0) { return }
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($null -eq (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }
        Start-Sleep -Milliseconds 100
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
}

function Remove-TreeWithRetry([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lastError = $null
    foreach ($attempt in 1..20) {
        try {
            Remove-Item -Recurse -Force -LiteralPath $Path -ErrorAction Stop
            return
        }
        catch {
            $lastError = $_
            Start-Sleep -Milliseconds 150
        }
    }
    if ($null -ne $lastError) { throw $lastError }
}

function Build-FakeApp([string]$Path, [bool]$Acknowledge) {
    $ackCode = if ($Acknowledge) {
@'
            if (!String.IsNullOrEmpty(ack)) {
                File.WriteAllText(ack, "{\"ok\":true,\"version\":\"" + version + "\"}");
            }
            File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "relaunch-marker.txt"), version);
            Thread.Sleep(500);
            return 0;
'@
    } else {
@'
            return 0;
'@
    }
    $className = 'FakeStarWorld_' + [Guid]::NewGuid().ToString('N')
    $source = @"
using System;
using System.IO;
using System.Threading;
public static class $className {
    public static int Main(string[] args) {
        string ack = "";
        string version = "";
        foreach (string arg in args) {
            if (arg.StartsWith("--starworld-update-ack=")) ack = arg.Substring("--starworld-update-ack=".Length);
            if (arg.StartsWith("--starworld-update-version=")) version = arg.Substring("--starworld-update-version=".Length);
        }
$ackCode
    }
}
"@
    $sourcePath = "$Path.cs"
    $source | Set-Content -LiteralPath $sourcePath -Encoding UTF8
    $compiler = Resolve-CSharpCompiler
    & $compiler '/nologo' '/target:exe' ("/out:$Path") $sourcePath
    $exitCode = $LASTEXITCODE
    Remove-Item -Force -LiteralPath $sourcePath -ErrorAction SilentlyContinue
    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "C# fixture compilation failed with exit $exitCode"
    }
}

function Build-Package([string]$Directory, [string]$ZipPath, [bool]$Acknowledge) {
    if (Test-Path $Directory) { Remove-TreeWithRetry $Directory }
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $exe = Join-Path $Directory 'StarWorld.exe'
    $pck = Join-Path $Directory 'StarWorld.pck'
    Build-FakeApp -Path $exe -Acknowledge $Acknowledge
    'new-pck-content' | Set-Content -LiteralPath $pck -Encoding ASCII
    $manifest = [ordered]@{
        schema_version = 1
        updater_protocol = 1
        version = '1.1.0'
        platform = 'windows-x86_64'
        executable = 'StarWorld.exe'
        files = @(
            [ordered]@{ path='StarWorld.exe'; size=(Get-Item $exe).Length; sha256=(Get-Sha256 $exe) },
            [ordered]@{ path='StarWorld.pck'; size=(Get-Item $pck).Length; sha256=(Get-Sha256 $pck) }
        )
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Directory 'update-manifest.json') -Encoding UTF8
    if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
    Compress-Archive -Path (Join-Path $Directory '*') -DestinationPath $ZipPath
}

function Invoke-UpdaterHelper([string]$PackagePath, [string]$PackageHash, [int]$AckTimeoutSeconds) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $helper,
        '-ParentProcessId', '0',
        '-PackagePath', $PackagePath,
        '-ExpectedPackageSha256', $PackageHash,
        '-InstallDirectory', $install,
        '-ExecutableName', 'StarWorld.exe',
        '-TargetVersion', '1.1.0',
        '-ResultPath', $result,
        '-AckTimeoutSeconds', [string]$AckTimeoutSeconds
    )
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    return [int]$process.ExitCode
}

try {
    New-Item -ItemType Directory -Force -Path $install | Out-Null
    'old-executable' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ASCII
    'old-pck-content' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ASCII
    'must-disappear' | Set-Content -LiteralPath (Join-Path $install 'old-only.txt') -Encoding ASCII
    Build-Package -Directory $payload -ZipPath $package -Acknowledge $true
    $hash = Get-Sha256 $package

    $successExitCode = Invoke-UpdaterHelper -PackagePath $package -PackageHash $hash -AckTimeoutSeconds 10
    if ($successExitCode -ne 0) { throw "Updater helper success scenario exited $successExitCode" }
    $success = Get-Content -Raw -Encoding UTF8 $result | ConvertFrom-Json
    if (-not [bool]$success.success -or [string]$success.phase -ne 'completed') { throw 'Updater did not report completed success' }
    if ((Get-Content -Raw $install\StarWorld.pck).Trim() -ne 'new-pck-content') { throw 'New PCK was not installed' }
    if (Test-Path $install\old-only.txt) { throw 'Directory swap retained stale old files' }
    if (-not (Test-Path $install\relaunch-marker.txt)) { throw 'Updated executable was not automatically relaunched' }
    if ((Get-Content -Raw $install\relaunch-marker.txt).Trim() -ne '1.1.0') { throw 'Relaunched app did not receive target version' }
    if (Get-ChildItem -LiteralPath $testRoot -Directory -Filter '.starworld-backup-*') { throw 'Successful update left a backup directory' }
    Wait-ForProcessExit -ProcessId ([int]$success.launched_pid) -TimeoutSeconds 10

    Remove-TreeWithRetry $install
    New-Item -ItemType Directory -Force -Path $install | Out-Null
    'rollback-executable' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ASCII
    'rollback-pck' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ASCII
    $failedPayload = Join-Path $testRoot 'failed-payload'
    $failedPackage = Join-Path $testRoot 'failed-update.zip'
    Build-Package -Directory $failedPayload -ZipPath $failedPackage -Acknowledge $false
    $failedHash = Get-Sha256 $failedPackage
    $failureExitCode = Invoke-UpdaterHelper -PackagePath $failedPackage -PackageHash $failedHash -AckTimeoutSeconds 5
    if ($failureExitCode -eq 0) { throw 'Updater helper should fail when the new app does not acknowledge startup' }
    $failure = Get-Content -Raw -Encoding UTF8 $result | ConvertFrom-Json
    if ([bool]$failure.success -or -not [bool]$failure.rolled_back) { throw 'Failed launch did not report rollback' }
    if ((Get-Content -Raw $install\StarWorld.pck).Trim() -ne 'rollback-pck') { throw 'Rollback did not restore the original install' }

    Write-Host 'PASS windows_update_helper swap=1 relaunch=1 ack=1 rollback=1'
}
catch {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $failureEvidence) | Out-Null
    @(
        "WINDOWS_UPDATE_HELPER_FAILURE=$($_.Exception.Message)",
        "STACK=$($_.ScriptStackTrace)",
        "RESULT=$((Get-Content -Raw -ErrorAction SilentlyContinue $result))"
    ) | Set-Content -LiteralPath $failureEvidence -Encoding UTF8
    throw
}
finally {
    if (Test-Path $testRoot) { Remove-TreeWithRetry $testRoot }
}
