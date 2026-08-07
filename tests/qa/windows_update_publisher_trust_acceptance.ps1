$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) { throw 'Publisher-pinned updater acceptance requires Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Publisher-pinned updater acceptance requires PowerShell 7.' }
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$trustValidator = Join-Path $root 'src\update\windows_update_trust_validator.ps1'
$helper = Join-Path $root 'src\update\windows_update_helper.ps1'
$manifestTool = Join-Path $root 'tools\new_update_manifest.ps1'
$signTool = Join-Path $root 'tools\sign_update_manifest.ps1'
$builder = Join-Path $root 'tools\build_update_release.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('starworld-publisher-update-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $testRoot 'payload'
$output = Join-Path $testRoot 'assets'
$install = Join-Path $testRoot 'install'
$result = Join-Path $testRoot 'result.json'
$manifestCertificate = $null

function Get-CertificateSha256 {
    param([Parameter(Mandatory = $true)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Certificate.RawData))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Name, [string]$Expected = '')
    $rejected = $false
    try { & $Action } catch {
        $rejected = $true
        if (-not [string]::IsNullOrWhiteSpace($Expected) -and -not $_.Exception.Message.Contains($Expected)) {
            throw "$Name failed for the wrong reason: $($_.Exception.Message)"
        }
    }
    if (-not $rejected) { throw "$Name was not rejected." }
}
function Find-TrustedTimestampedFixture {
    $candidates = [Collections.Generic.List[string]]::new()
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwsh) { $candidates.Add($pwsh.Source) }
    $candidates.Add((Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'))
    $candidates.Add((Join-Path $env:SystemRoot 'System32\notepad.exe'))
    $observed = [Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $signature = Get-AuthenticodeSignature -LiteralPath $candidate
        $observed.Add("$candidate=$($signature.Status):timestamp=$($null -ne $signature.TimeStamperCertificate)")
        if ([string]$signature.Status -eq 'Valid' -and $null -ne $signature.SignerCertificate -and $null -ne $signature.TimeStamperCertificate) {
            return [pscustomobject]@{ Path=$candidate; Signature=$signature }
        }
    }
    throw "No trusted timestamped Authenticode fixture is available. Observed: $($observed -join ' | ')"
}
function Resolve-CSharpCompiler {
    foreach ($candidate in @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
    throw 'Windows C# compiler is unavailable.'
}
function Build-AckApp([string]$Path) {
    $sourcePath = "$Path.cs"
    @'
using System;
using System.IO;
public static class AckApp {
    public static int Main(string[] args) {
        string ack = ""; string version = "";
        foreach (string arg in args) {
            if (arg.StartsWith("--starworld-update-ack=")) ack = arg.Substring("--starworld-update-ack=".Length);
            if (arg.StartsWith("--starworld-update-version=")) version = arg.Substring("--starworld-update-version=".Length);
        }
        if (String.IsNullOrEmpty(ack)) return 2;
        File.WriteAllText(ack, "{\"ok\":true,\"version\":\"" + version + "\"}");
        return 0;
    }
}
'@ | Set-Content -LiteralPath $sourcePath -Encoding utf8
    & (Resolve-CSharpCompiler) '/nologo' '/target:exe' ("/out:$Path") $sourcePath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'ACK fixture compilation failed.' }
    Remove-Item -Force -LiteralPath $sourcePath
}
function Invoke-Helper([string]$PackagePath, [string]$PolicyBase64, [string]$LaunchExecutable, [string]$ResultPath) {
    Remove-Item -Force -LiteralPath $ResultPath -ErrorAction SilentlyContinue
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$helper,
        '-ParentProcessId','0',
        '-PackagePath',$PackagePath,
        '-ExpectedPackageSha256',(Get-Sha256 $PackagePath),
        '-InstallDirectory',$install,
        '-ExecutableName','StarWorld.exe',
        '-TargetVersion','1.1.0',
        '-ResultPath',$ResultPath,
        '-TrustValidatorPath',$trustValidator,
        '-TrustPolicyBase64',$PolicyBase64,
        '-AckTimeoutSeconds','8'
    )
    if (-not [string]::IsNullOrWhiteSpace($LaunchExecutable)) { $args += @('-LaunchExecutable',$LaunchExecutable) }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($arg in $args) { [void]$start.ArgumentList.Add([string]$arg) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Unable to launch updater helper.' }
    $outTask = $process.StandardOutput.ReadToEndAsync(); $errTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode=$process.ExitCode
        Stdout=$outTask.GetAwaiter().GetResult()
        Stderr=$errTask.GetAwaiter().GetResult()
        Result=if (Test-Path -LiteralPath $ResultPath) { Get-Content -Raw -Encoding UTF8 -LiteralPath $ResultPath } else { '' }
    }
}

try {
    New-Item -ItemType Directory -Force -Path $payload,$output,$install | Out-Null
    $trusted = Find-TrustedTimestampedFixture
    Copy-Item -LiteralPath $trusted.Path -Destination (Join-Path $payload 'StarWorld.exe')
    'publisher-bound-pck' | Set-Content -LiteralPath (Join-Path $payload 'StarWorld.pck') -Encoding ascii
    $manifestCertificate = New-SelfSignedCertificate `
        -Type Custom `
        -Subject 'CN=Star World Update Manifest CI Fixture' `
        -KeyUsage DigitalSignature `
        -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') `
        -CertStoreLocation 'Cert:\CurrentUser\My'
    $manifestSignerSha = Get-CertificateSha256 $manifestCertificate
    $publisherSha = Get-CertificateSha256 $trusted.Signature.SignerCertificate

    & $manifestTool -BuildDirectory $payload -Version '1.1.0'
    & $signTool -ManifestPath (Join-Path $payload 'update-manifest.json') -CertificateThumbprint $manifestCertificate.Thumbprint -ExpectedCertificateSha256 $manifestSignerSha

    $policy = [ordered]@{
        schema_version=1; max_active_pins=4
        manifest_signature=[ordered]@{
            required_for_release=$true; format='cms-detached'; digest='sha256'; code_signing_eku_oid='1.3.6.1.5.5.7.3.3'
            trusted_signer_certificate_sha256=@($manifestSignerSha)
        }
        executable_authenticode=[ordered]@{
            required_for_release=$true; require_trusted_timestamp=$true; code_signing_eku_oid='1.3.6.1.5.5.7.3.3'; timestamp_eku_oid='1.3.6.1.5.5.7.3.8'
            trusted_publisher_certificate_sha256=@($publisherSha)
        }
    }
    $policyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($policy | ConvertTo-Json -Depth 8 -Compress)))
    $trustText = (& $trustValidator `
        -ManifestPath (Join-Path $payload 'update-manifest.json') `
        -SignaturePath (Join-Path $payload 'update-manifest.p7s') `
        -ExecutablePath (Join-Path $payload 'StarWorld.exe') `
        -TrustPolicyBase64 $policyBase64 | Out-String).Trim()
    $trust = $trustText | ConvertFrom-Json
    if (-not [bool]$trust.valid -or [bool]$trust.reference_only) { throw 'Valid combined publisher trust fixture failed.' }
    if ([string]$trust.manifest_signer_certificate_sha256 -ne $manifestSignerSha) { throw 'Manifest signer pin did not round-trip.' }
    if ([string]$trust.publisher_certificate_sha256 -ne $publisherSha) { throw 'Publisher pin did not round-trip.' }
    if (-not [bool]$trust.trusted_timestamp_present -or -not [bool]$trust.timestamp_eku) { throw 'Trusted timestamp was not proven.' }

    $wrongManifestPolicy = $policy | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $wrongManifestPolicy.manifest_signature.trusted_signer_certificate_sha256 = @('f' * 64)
    $wrongManifestBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($wrongManifestPolicy | ConvertTo-Json -Depth 8 -Compress)))
    Assert-Rejected -Name 'Wrong manifest signer pin' -Expected 'manifest signer certificate is not pinned' -Action {
        & $trustValidator -ManifestPath (Join-Path $payload 'update-manifest.json') -SignaturePath (Join-Path $payload 'update-manifest.p7s') -ExecutablePath (Join-Path $payload 'StarWorld.exe') -TrustPolicyBase64 $wrongManifestBase64 | Out-Null
    }
    $wrongPublisherPolicy = $policy | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $wrongPublisherPolicy.executable_authenticode.trusted_publisher_certificate_sha256 = @('e' * 64)
    $wrongPublisherBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($wrongPublisherPolicy | ConvertTo-Json -Depth 8 -Compress)))
    Assert-Rejected -Name 'Wrong publisher pin' -Expected 'publisher certificate is not pinned' -Action {
        & $trustValidator -ManifestPath (Join-Path $payload 'update-manifest.json') -SignaturePath (Join-Path $payload 'update-manifest.p7s') -ExecutablePath (Join-Path $payload 'StarWorld.exe') -TrustPolicyBase64 $wrongPublisherBase64 | Out-Null
    }

    $manifestPath = Join-Path $payload 'update-manifest.json'
    $signaturePath = Join-Path $payload 'update-manifest.p7s'
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    [IO.File]::AppendAllText($manifestPath, "`n")
    Assert-Rejected -Name 'Manifest byte tamper' -Action {
        & $trustValidator -ManifestPath $manifestPath -SignaturePath $signaturePath -ExecutablePath (Join-Path $payload 'StarWorld.exe') -TrustPolicyBase64 $policyBase64 | Out-Null
    }
    [IO.File]::WriteAllBytes($manifestPath, $manifestBytes)
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    $signatureBytes[[Math]::Min(32, $signatureBytes.Length - 1)] = $signatureBytes[[Math]::Min(32, $signatureBytes.Length - 1)] -bxor 0x01
    [IO.File]::WriteAllBytes($signaturePath, $signatureBytes)
    Assert-Rejected -Name 'Detached signature tamper' -Action {
        & $trustValidator -ManifestPath $manifestPath -SignaturePath $signaturePath -ExecutablePath (Join-Path $payload 'StarWorld.exe') -TrustPolicyBase64 $policyBase64 | Out-Null
    }
    & $signTool -ManifestPath $manifestPath -CertificateThumbprint $manifestCertificate.Thumbprint -ExpectedCertificateSha256 $manifestSignerSha

    $unsigned = Join-Path $testRoot 'unsigned.ps1'; 'Write-Output unsigned' | Set-Content -LiteralPath $unsigned -Encoding utf8
    Assert-Rejected -Name 'Unsigned executable' -Expected 'Authenticode status is not Valid' -Action {
        & $trustValidator -ManifestPath $manifestPath -SignaturePath $signaturePath -ExecutablePath $unsigned -TrustPolicyBase64 $policyBase64 | Out-Null
    }

    & $builder -BuildDirectory $payload -Version '1.1.0' -OutputDirectory $output -RequirePublisherSignature
    $package = Join-Path $output 'StarWorld-Windows-x86_64.zip'
    'old-exe' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ascii
    'old-pck' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ascii
    'old-marker' | Set-Content -LiteralPath (Join-Path $install 'old-only.txt') -Encoding ascii
    $ackExe = Join-Path $testRoot 'ack.exe'; Build-AckApp $ackExe
    $successRun = Invoke-Helper -PackagePath $package -PolicyBase64 $policyBase64 -LaunchExecutable $ackExe -ResultPath $result
    if ($successRun.ExitCode -ne 0) { throw "Authenticated helper install failed: stdout=$($successRun.Stdout) stderr=$($successRun.Stderr) result=$($successRun.Result)" }
    $success = $successRun.Result | ConvertFrom-Json
    if (-not [bool]$success.publisher_authenticated -or -not [bool]$success.trusted_timestamp_present) { throw 'Authenticated helper result omitted publisher evidence.' }
    if ((Get-Content -Raw (Join-Path $install 'StarWorld.pck')).Trim() -ne 'publisher-bound-pck') { throw 'Authenticated helper did not install the signed-manifest PCK.' }
    if (Test-Path -LiteralPath (Join-Path $install 'old-only.txt')) { throw 'Authenticated directory swap retained stale files.' }

    Remove-Item -Recurse -Force -LiteralPath $install
    New-Item -ItemType Directory -Force -Path $install | Out-Null
    'guard-exe' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.exe') -Encoding ascii
    'guard-pck' | Set-Content -LiteralPath (Join-Path $install 'StarWorld.pck') -Encoding ascii
    'pre-swap-guard' | Set-Content -LiteralPath (Join-Path $install 'guard.txt') -Encoding ascii
    $maliciousPayload = Join-Path $testRoot 'tampered-payload'
    Copy-Item -LiteralPath $payload -Destination $maliciousPayload -Recurse
    'tampered-pck-after-signing' | Set-Content -LiteralPath (Join-Path $maliciousPayload 'StarWorld.pck') -Encoding ascii
    $maliciousPackage = Join-Path $testRoot 'tampered.zip'
    Compress-Archive -Path (Join-Path $maliciousPayload '*') -DestinationPath $maliciousPackage
    $failureRun = Invoke-Helper -PackagePath $maliciousPackage -PolicyBase64 $policyBase64 -LaunchExecutable $ackExe -ResultPath $result
    if ($failureRun.ExitCode -eq 0) { throw 'PCK tamper should fail before installation.' }
    $failure = $failureRun.Result | ConvertFrom-Json
    if ([bool]$failure.rolled_back) { throw 'PCK tamper reached directory swap before rejection.' }
    if (-not (Test-Path -LiteralPath (Join-Path $install 'guard.txt'))) { throw 'PCK tamper mutated the current install before rejection.' }

    Write-Host "PASS publisher_pinned_auto_update cms=1 authenticode=1 timestamp=1 manifest_pin=$manifestSignerSha publisher_pin=$publisherSha tamper_cases=6 pre_swap_pck_rejection=1"
}
finally {
    if ($null -ne $manifestCertificate) {
        Remove-Item -Force -LiteralPath ("Cert:\CurrentUser\My\$($manifestCertificate.Thumbprint)") -ErrorAction SilentlyContinue
    }
    Remove-Item -Recurse -Force -LiteralPath $testRoot -ErrorAction SilentlyContinue
}
