$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path "$PSScriptRoot\..\.."
$helper = Join-Path $root 'src\update\windows_update_helper.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("starworld-updater-" + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $testRoot 'StarWorld'
$payload = Join-Path $testRoot 'payload'
$package = Join-Path $testRoot 'StarWorld-Windows-x86_64.zip'
$result = Join-Path $testRoot 'install-result.json'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Build-FakeApp([string]$Path, [bool]$Acknowledge) {
    $ackCode = if ($Acknowledge) {
@'
            if (!String.IsNullOrEmpty(ack)) {
                File.WriteAllText(ack, "{\"ok\":true,\"version\":\"" + version + "\"}");
            }
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "relaunch-marker.txt"), version);
            Thread.Sleep(500);
            return 0;
'@
    } else {
@'
            return 0;
'@
    }
    $source = @"
using System;
using System.IO;
using System.Threading;
public static class FakeStarWorld {
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
    Add-Type -TypeDefinition $source -OutputAssembly $Path -OutputType ConsoleApplication
}

function Build-Package([string]$Directory, [string]$ZipPath, [bool]$Acknowledge) {
    if (Test-Path $Directory) { Remove-Item -Recurse -Force $Directory }
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

try {
    New-Item -ItemType Directory -Force -Path $install | Out-Null
    'old-executable' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ASCII
    'old-pck-content' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ASCII
    'must-disappear' | Set-Content -LiteralPath (Join-Path $install 'old-only.txt') -Encoding ASCII
    Build-Package -Directory $payload -ZipPath $package -Acknowledge $true
    $hash = Get-Sha256 $package

    & $helper `
        -ParentProcessId 0 `
        -PackagePath $package `
        -ExpectedPackageSha256 $hash `
        -InstallDirectory $install `
        -ExecutableName 'StarWorld.exe' `
        -TargetVersion '1.1.0' `
        -ResultPath $result `
        -AckTimeoutSeconds 10
    if ($LASTEXITCODE -ne 0) { throw "Updater helper success scenario exited $LASTEXITCODE" }
    $success = Get-Content -Raw -Encoding UTF8 $result | ConvertFrom-Json
    if (-not [bool]$success.success -or [string]$success.phase -ne 'completed') { throw 'Updater did not report completed success' }
    if ((Get-Content -Raw $install\StarWorld.pck).Trim() -ne 'new-pck-content') { throw 'New PCK was not installed' }
    if (Test-Path $install\old-only.txt) { throw 'Directory swap retained stale old files' }
    if (-not (Test-Path $install\relaunch-marker.txt)) { throw 'Updated executable was not automatically relaunched' }
    if ((Get-Content -Raw $install\relaunch-marker.txt).Trim() -ne '1.1.0') { throw 'Relaunched app did not receive target version' }
    if (Get-ChildItem -LiteralPath $testRoot -Directory -Filter '.starworld-backup-*') { throw 'Successful update left a backup directory' }

    Remove-Item -Recurse -Force $install
    New-Item -ItemType Directory -Force -Path $install | Out-Null
    'rollback-executable' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ASCII
    'rollback-pck' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ASCII
    $failedPayload = Join-Path $testRoot 'failed-payload'
    $failedPackage = Join-Path $testRoot 'failed-update.zip'
    Build-Package -Directory $failedPayload -ZipPath $failedPackage -Acknowledge $false
    $failedHash = Get-Sha256 $failedPackage
    & $helper `
        -ParentProcessId 0 `
        -PackagePath $failedPackage `
        -ExpectedPackageSha256 $failedHash `
        -InstallDirectory $install `
        -ExecutableName 'StarWorld.exe' `
        -TargetVersion '1.1.0' `
        -ResultPath $result `
        -AckTimeoutSeconds 5
    if ($LASTEXITCODE -eq 0) { throw 'Updater helper should fail when the new app does not acknowledge startup' }
    $failure = Get-Content -Raw -Encoding UTF8 $result | ConvertFrom-Json
    if ([bool]$failure.success -or -not [bool]$failure.rolled_back) { throw 'Failed launch did not report rollback' }
    if ((Get-Content -Raw $install\StarWorld.pck).Trim() -ne 'rollback-pck') { throw 'Rollback did not restore the original install' }

    Write-Host 'PASS windows_update_helper swap=1 relaunch=1 ack=1 rollback=1'
}
finally {
    if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
}
