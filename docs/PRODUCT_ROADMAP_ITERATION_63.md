# Product Roadmap · Iteration 63 · Publisher Signing Gate

Date: 2026-08-07

## Decision

Iteration 63 does not add another gameplay subsystem. Iterations 59-62 already close the repository-owned release-integrity, external-qualification, chain-of-custody and offline-promotion work. The next repository-owned gap is the boundary between an accepted Promotion Bundle and the executable that will actually be distributed to Windows users.

Authenticode signing changes the executable bytes. Therefore signing after qualification would invalidate the candidate, hardware, soak, package, bundle and promotion hashes. Commercial signing must happen before candidate identity and qualification are created.

## Scope

1. Add an explicit publisher-signing policy to `data/release_qualification.json`.
2. Require sign-before-qualification and forbid post-qualification signing for commercial candidates.
3. Validate Windows Authenticode with the OS trust engine.
4. Require the Code Signing EKU for the publisher certificate.
5. Require a trusted Authenticode timestamp and Time Stamping EKU for commercial approval.
6. Pin publisher identity with an externally retained SHA-256 of the signing certificate, not only the mutable certificate subject string or legacy SHA-1 thumbprint.
7. Compose the Iteration 62 Promotion Gate with publisher signature verification into one Distribution Gate.
8. Prove that the signed EXE bytes equal the already-qualified candidate EXE hash.
9. Record a distribution receipt outside the immutable Promotion Bundle.
10. Keep private keys, real CA certificates and real TSA interactions external to the repository.

## Acceptance

Repository acceptance requires:

- PowerShell 7 parser success;
- real Windows Authenticode fixture signing with an ephemeral Code Signing certificate;
- trusted local fixture signature validation;
- wrong external publisher certificate rejection;
- unsigned artifact rejection when a signature is required;
- commercial mode rejecting the fixture because it has no real trusted timestamp;
- unsigned reference Promotion Bundle remaining reference-only rather than falsely failing compatibility checks;
- distribution receipts remaining outside the immutable Promotion Bundle;
- strict Godot 4.7 project import;
- existing Iterations 59-62 release contracts remaining green;
- Windows Release export/run regression remaining green.

## External boundary

The repository never creates or stores the real publisher private key. It also does not claim that the fixture self-signed certificate or an untimestamped CI signature is a commercial signature.

Commercial release remains **HOLD** until the real final EXE is signed before qualification by the publisher certificate, timestamped by a trusted TSA, all external qualification evidence is collected, and the final Distribution Gate passes with both the externally retained Promotion Pin and publisher-certificate SHA-256.
