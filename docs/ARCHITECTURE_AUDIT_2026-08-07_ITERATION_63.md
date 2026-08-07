# Architecture Audit · Iteration 63 · Publisher Signing Gate

Date: 2026-08-07

## Audit question

Can the repository verify that the Windows executable selected by the release owner is the same signed and timestamped executable that was qualified, without importing the real publisher private key into the repository or weakening the existing Iterations 60-62 evidence chain?

## Findings

### 1. Signing after qualification would invalidate the evidence chain

Authenticode changes `StarWorld.exe` bytes. Iterations 60-62 bind the executable with SHA-256. Therefore a workflow that qualifies an unsigned EXE and signs it afterward would distribute bytes that were never hardware-qualified or soaked.

Decision: commercial policy requires sign-before-qualification and explicitly forbids post-qualification signing.

### 2. Certificate subject strings are not a sufficient identity pin

A subject such as `CN=Publisher` is descriptive, not a unique cryptographic identity. Windows certificate thumbprints are commonly SHA-1.

Decision: external approval retains SHA-256 of the signer certificate DER bytes. Subject, issuer and thumbprint remain diagnostics only.

### 3. Promotion identity and publisher identity are independent roots

Iteration 62 prevents selecting the wrong internally consistent candidate by requiring an externally retained `ExpectedPinId`. It does not authenticate the Windows publisher.

Decision: commercial Distribution Gate requires both:

- externally retained Promotion Pin;
- externally retained publisher-certificate SHA-256.

Neither can be inferred solely from mutable bundle content.

### 4. Repository CI should verify signatures, not simulate the publisher private key

The repository owns verification logic, not the real publisher signing operation. Generating a local signing key inside CI would blur that boundary and does not prove trusted timestamp handling.

Decision: the permanent Windows gate discovers a real trusted, timestamped Authenticode binary already present on the hosted Windows image, derives its signer-certificate SHA-256 and sends it through the same validator used for releases. This exercises Windows trust, Code Signing EKU, certificate pinning, trusted timestamp presence and Time Stamping EKU without creating a Star World signing key.

The fixture is not a Star World release artifact and the surrounding Promotion Bundle remains reference-only, so it can never close the commercial gate.

### 5. Reference fixtures must not parse placeholder EXE bytes as Authenticode

The retained qualification fixture uses placeholder `StarWorld.exe` bytes only to exercise the hash/evidence contracts. Treating that placeholder as a Windows executable adds no security value and can create OS-parser-dependent behavior.

Decision: reference Distribution validation skips Authenticode unless an external publisher certificate pin or `-RequireReleaseGate` is supplied. It returns an explicit unsigned reference state instead.

### 6. Distribution receipt must remain outside the immutable bundle

Writing validation output into the Promotion Bundle would mutate the payload being described and change its inventory/hash contract.

Decision: Distribution Receipts are append-only external records, following the same immutability principle introduced by Iteration 62.

## Architecture

```text
Signed + timestamped StarWorld.exe
            │
            ▼
Candidate / external qualification / chain / promotion
            │
            ▼
Promotion Bundle + externally retained ExpectedPinId
            │
            ├── frozen release signing policy
            └── candidate-chain/binary/StarWorld.exe
                         │
                         ▼
Windows Authenticode validator
            │
            ├── OS trust status = Valid
            ├── Code Signing EKU
            ├── external publisher certificate SHA-256
            └── trusted timestamp + Time Stamping EKU
                         │
                         ▼
Distribution Gate
                         │
                         ▼
External Distribution Receipt
```

## Compatibility

Iteration 63 does not change the Iteration 60 package schema, Iteration 61 19-file candidate chain or Iteration 62 Promotion Bundle schema. The publisher-signing policy is an additive field in `data/release_qualification.json`, which is already frozen and hashed by the existing candidate/promotion contracts.

Unsigned retained fixtures remain valid reference evidence but can never close the commercial Distribution Gate.

## Risk review

- Private-key leakage: avoided; repository tests do not create or import a Star World publisher key.
- Wrong trusted publisher: prevented by external certificate SHA-256 pin.
- Post-qualification signing: prevented by executable hash equality plus explicit policy.
- Missing timestamp: commercial mode fails closed.
- Signed-binary tamper: Authenticode trust validation fails after byte mutation.
- Fixture promoted as real: impossible because the Star World Promotion fixture remains reference-only.
- Checkout drift: already handled by Iteration 62 frozen contract snapshots.

## Conclusion

The repository-owned signing-validation boundary is suitable for merge once the permanent Windows/Godot workflow and all affected release regressions pass. Real publisher signing, CA trust enrollment and TSA issuance remain external controls and must not be marked complete by CI.
