# Release Publisher Signing Gate

Iteration 63 adds the final repository-owned Windows distribution validation layer above the accepted Iteration 62 Promotion Bundle.

## 1. Signing order is mandatory

Authenticode modifies the EXE bytes. Therefore the commercial sequence is:

```text
Export final Windows EXE/PCK
        ↓
Publisher signs StarWorld.exe
        ↓
Trusted TSA timestamps the signature
        ↓
Create candidate_id from the signed EXE/PCK
        ↓
Run minimum/recommended hardware qualification
        ↓
Run strict 7,200-second soak and fault experiments
        ↓
Assemble Iteration 60 package
        ↓
Assemble Iteration 61 candidate chain
        ↓
Create Iteration 62 Promotion Pin/Bundle
        ↓
Run Iteration 63 Distribution Gate
```

Do not sign the EXE after qualification. A post-qualification signature changes SHA-256 and invalidates the evidence chain.

## 2. Publisher identity root

For a real release, retain the SHA-256 digest of the DER-encoded publisher signing certificate outside the Promotion Bundle. This is stronger than relying on the certificate subject string and avoids treating the legacy SHA-1 certificate thumbprint as the release identity root.

The repository never stores the publisher private key.

## 3. Validate Authenticode directly

```powershell
pwsh -NoProfile -File tests/ci/validate_windows_publisher_signature.ps1 `
  -FilePath D:\promotion\star-world-v1.3.0\candidate-chain\binary\StarWorld.exe `
  -ExpectedPublisherCertificateSha256 <retained-certificate-sha256> `
  -RequireSignature `
  -RequireTrustedTimestamp
```

Commercial validation requires:

- Windows Authenticode status `Valid`;
- an actual signer certificate;
- Code Signing EKU `1.3.6.1.5.5.7.3.3`;
- certificate SHA-256 matching the externally retained value;
- a countersigning/timestamp certificate;
- Time Stamping EKU `1.3.6.1.5.5.7.3.8`.

The validator records the signer subject/issuer/thumbprint for diagnostics, but the external SHA-256 is the publisher identity pin.

## 4. Validate the complete distribution

```powershell
pwsh -NoProfile -File tests/ci/validate_release_distribution_gate.ps1 `
  -PromotionBundleDirectory D:\promotion\star-world-v1.3.0 `
  -ExpectedPinId <retained-promotion-pin> `
  -ExpectedPublisherCertificateSha256 <retained-certificate-sha256> `
  -RequireReleaseGate
```

This composes:

1. the Iteration 62 offline Promotion Gate;
2. the externally retained Promotion Pin;
3. the frozen qualification policy;
4. the candidate EXE hash;
5. Windows Authenticode trust;
6. externally pinned publisher certificate identity;
7. trusted timestamp presence and EKU.

Because the candidate-chain manifest still hashes `StarWorld.exe`, a passing signed distribution proves that the signature was already present when the candidate identity and external qualification evidence were generated.

## 5. Record a distribution receipt

```powershell
pwsh -NoProfile -File tests/ci/new_release_distribution_receipt.ps1 `
  -PromotionBundleDirectory D:\promotion\star-world-v1.3.0 `
  -ExpectedPinId <retained-promotion-pin> `
  -ExpectedPublisherCertificateSha256 <retained-certificate-sha256> `
  -ReceiverId publisher-final-check `
  -OutputPath D:\receipts\publisher-final-check.json `
  -RequireReleaseGate
```

The receipt records the promotion/candidate/package identity, signed executable SHA-256, publisher certificate SHA-256, timestamp certificate SHA-256 and hashes of the validators used for that check.

The receipt must remain outside the immutable Promotion Bundle.

## CI boundary

The permanent Windows workflow creates an ephemeral self-signed Code Signing certificate only to prove that the operating-system Authenticode path and certificate pin logic work. It adds that certificate to the job-local current-user trust stores and deletes it afterward.

The fixture is deliberately not timestamped. Commercial timestamp enforcement must therefore reject it. This prevents CI from generating a false commercial-release pass.

## Security boundary

Iteration 63 validates signatures; it does not own signing keys, issue certificates or run a public timestamp authority. Private keys, CA enrollment, trusted timestamping and publisher release operations remain external security controls.
