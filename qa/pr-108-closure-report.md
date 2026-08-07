# PR #108 Review Closure · Iteration 63 Publisher Signing Gate

Date: 2026-08-07

## Scope reviewed

This review covers the repository-owned publisher-signing and final-distribution boundary introduced after Iteration 62. It does not claim that a real Star World publisher private key, CA certificate, trusted timestamp or physical qualification evidence exists.

## Task-list reconciliation

- [x] Commercial policy requires Authenticode signing before candidate identity and external qualification.
- [x] Post-qualification signing is explicitly forbidden because it changes the qualified EXE bytes.
- [x] Windows Authenticode trust is validated with the operating-system trust engine.
- [x] Publisher certificates require the Code Signing EKU.
- [x] Commercial validation requires a trusted timestamp and Time Stamping EKU.
- [x] Publisher identity is pinned with an externally retained SHA-256 of the DER certificate bytes.
- [x] Distribution Gate composes the Iteration 62 Promotion Gate with publisher-signature validation.
- [x] Distributed EXE SHA-256 must remain identical to the qualified candidate EXE SHA-256.
- [x] Reference-only placeholder EXE bytes remain explicitly unsigned and are not parsed as commercial Authenticode evidence.
- [x] Distribution Receipts remain outside the immutable Promotion Bundle.
- [x] `data/release_qualification.json`, main roadmap, full test runner, readiness gates and feature status board include the Iteration 63 contract.
- [x] Permanent Windows/Godot workflow owns the signing-verifier regression.
- [ ] Real Star World publisher private-key signing — external execution only.
- [ ] Real CA-issued publisher certificate retained by the release organization — external execution only.
- [ ] Real trusted TSA timestamp on the final Star World EXE — external execution only.
- [ ] Independent E4-H, both physical hardware tiers, strict 7,200-second target-hardware soak and real HDD/antivirus/power-loss evidence — external execution only.

## Review-found corrections

1. The first cleanup implementation used inline `if` expressions inside an array and failed PowerShell parsing. Cleanup now uses an explicit typed list.
2. The signing workflow was split into static, Promotion-fixture and Authenticode phases so failures are attributable.
3. Reference Promotion fixtures no longer send placeholder EXE bytes through Authenticode; publisher verification activates only when a publisher certificate pin or the commercial gate is requested.
4. CI no longer creates a simulated Star World signing key. It verifies a real trusted, timestamped Windows binary already present on the hosted runner and dynamically pins its signer certificate SHA-256.
5. Documentation was reconciled to the final verifier-only architecture.

## Security boundary

The repository verifies signatures and evidence identity. It does not own the publisher private key, certificate issuance, trusted timestamp authority or the physical/human events required for commercial release.

Commercial release therefore remains **HOLD** until the external items above are genuinely produced and the final Distribution Gate passes with both the retained Promotion Pin and retained publisher-certificate SHA-256.
