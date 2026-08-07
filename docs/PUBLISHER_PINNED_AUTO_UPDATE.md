# Publisher-Pinned Auto Update Operator Guide

Iteration 64 makes the in-game updater consume publisher trust rather than treating GitHub Release metadata as an independent trust root.

## Production prerequisites

Before a build can safely auto-update, `data/update_trust_policy.json` in the **currently installed version** must contain the approved certificate SHA-256 pins:

- `manifest_signature.trusted_signer_certificate_sha256`: detached CMS Manifest signer certificate(s);
- `executable_authenticode.trusted_publisher_certificate_sha256`: Windows Authenticode publisher certificate(s).

The SHA-256 value is calculated from the DER-encoded certificate bytes. Do not use the subject string or SHA-1 certificate thumbprint as the identity root.

The repository intentionally commits empty pin arrays. Real pins are an external release input and must be present before the production PCK is exported/qualified.

## Bootstrap

A client with no existing trusted pin cannot securely learn its first pin from the package it is trying to authenticate. Therefore the first publisher-pinned production baseline must be distributed via an already trusted/manual channel.

After that baseline is installed, normal GitHub Release auto-update can be used.

## Certificate rotation

Use overlap:

1. Current release trusts old signer A.
2. Ship a release, authenticated by A, whose current-install trust policy includes A + future signer B.
3. Confirm the overlap release is deployed.
4. Publish subsequent releases with B.
5. Only after the migration window, ship a B-authenticated release that removes A.

Each trust domain permits at most four pins. The target package cannot change the pins used for its own authentication; new pins only become active after that package has already passed the old trust policy and launched successfully.

## Build/sign sequence

The executable must already satisfy Iteration 63 before the updater Manifest is generated:

```text
Export EXE/PCK with production trust policy
→ Authenticode-sign StarWorld.exe
→ obtain trusted TSA timestamp
→ run release qualification / candidate process on those exact bytes
→ generate update-manifest.json schema 2
→ detached-sign update-manifest.json to update-manifest.p7s
→ self-validate Manifest signer + EXE publisher + TSA
→ package without regenerating Manifest
→ publish ZIP + .sha256
```

Do not modify EXE, PCK or any listed payload after generating the Manifest. Do not modify the Manifest after generating `update-manifest.p7s`.

## Generate the Manifest

```powershell
pwsh -NoProfile -File tools/new_update_manifest.ps1 `
  -BuildDirectory D:\release\star-world `
  -Version 1.3.0
```

This creates deterministic schema/protocol 2 metadata and removes any stale detached signature before regeneration.

## Sign the Manifest

```powershell
pwsh -NoProfile -File tools/sign_update_manifest.ps1 `
  -ManifestPath D:\release\star-world\update-manifest.json `
  -CertificateThumbprint <manifest-signing-thumbprint> `
  -ExpectedCertificateSha256 <approved-manifest-certificate-sha256>
```

The tool reads the certificate/private key from `Cert:\CurrentUser\My`; no private-key file is accepted by repository tooling.

## Package only after signing

```powershell
pwsh -NoProfile -File tools/build_update_release.ps1 `
  -BuildDirectory D:\release\star-world `
  -Version 1.3.0 `
  -OutputDirectory D:\release\assets `
  -RequirePublisherSignature
```

Signed mode verifies that the already signed Manifest covers the exact payload and refuses to regenerate or edit it.

## Publish from the controlled signing workstation

The preferred one-command orchestration is:

```powershell
pwsh -NoProfile -File tools/publish_signed_update_release.ps1 `
  -BuildDirectory D:\release\star-world `
  -Version 1.3.0 `
  -ManifestSigningCertificateThumbprint <manifest-signing-thumbprint> `
  -ExpectedManifestSignerCertificateSha256 <manifest-cert-sha256> `
  -ExpectedPublisherCertificateSha256 <authenticode-publisher-cert-sha256>
```

Before `gh release` is invoked, the tool verifies:

- checkout HEAD equals `v<version>`;
- `StarWorld.exe` Authenticode is `Valid`;
- publisher cert SHA-256 matches the explicit expected pin;
- trusted timestamp and EKU are present;
- Manifest signer cert SHA-256 matches the explicit expected pin;
- detached CMS verifies the exact Manifest bytes;
- signed Manifest covers the exact payload;
- signed builder leaves Manifest bytes untouched.

## Client-side install sequence

The game loads trust pins from its current PCK before starting download/install. The external helper then:

1. validates ZIP SHA-256;
2. extracts with Zip Slip protection;
3. validates exact Manifest file set and SHA-256 values;
4. validates Manifest CMS against current-install Manifest signer pins;
5. validates staged EXE Authenticode/TSA against current-install publisher pins;
6. only then swaps directories;
7. waits for the existing update ACK;
8. rolls back if launch/ACK fails.

## Hosted CI boundary

`.github/workflows/publish-windows-release.yml` is reference-only. It is intentionally unable to create/update commercial GitHub Release assets.

CI may generate ephemeral certificates and use pre-signed Microsoft binaries to prove validator behavior, but those artifacts and pins are never committed as Star World production trust.
