# Product Roadmap · Iteration 64 · Publisher-Pinned Auto Update

Date: 2026-08-07

## Decision

Iterations 60-63 close the repository-owned commercial qualification, candidate identity, offline promotion and final Windows distribution-signature boundaries. A follow-up audit found one product path that did not yet consume that trust: the in-game GitHub Release updater.

The existing updater verified the downloaded ZIP SHA-256 and an exact file-hash manifest. Both values came from the same GitHub Release. A compromised release surface could therefore replace the ZIP, checksum and manifest together. Verifying only `StarWorld.exe` would also be insufficient because an attacker could retain a legitimately signed EXE while substituting `StarWorld.pck`.

Iteration 64 closes that gap without moving publisher private keys into GitHub Actions.

## Scope

1. Upgrade the updater package contract to schema/protocol 2.
2. Add `update-manifest.p7s`, a detached CMS/PKCS#7 signature over the exact `update-manifest.json` bytes.
3. Keep EXE/PCK/all payload hashes in the signed manifest.
4. Validate Manifest signer certificate DER SHA-256 against current-install pins.
5. Validate staged EXE Authenticode, publisher certificate DER SHA-256, Code Signing EKU, trusted timestamp and Time Stamping EKU.
6. Load all trust pins from the currently installed version before download/install; the target package cannot select the pins used to authenticate itself.
7. Permit at most four active pins per trust domain for bounded overlap rotation.
8. Perform all publisher authentication before the first install-directory move.
9. Preserve the existing atomic swap, relaunch ACK and rollback transaction unchanged after the new authentication boundary.
10. Keep legacy schema-1 fixtures explicitly reference-only for historical regression coverage.
11. Remove unsigned public GitHub Release publication from hosted CI.
12. Add an external signed-release publisher that uses certificates/private keys from the controlled Windows signing environment and validates the complete production trust chain before upload.

## Acceptance

Repository acceptance requires:

- PowerShell parser success for all new/changed signing and helper tools;
- strict Godot 4.7 import;
- schema-1 reference package compatibility without a false publisher-authenticated claim;
- schema-2 package requiring detached signature metadata and `update-manifest.p7s`;
- current repository trust policy parsing while empty real pins fail closed;
- bounded duplicate-normalizing certificate rotation;
- detached CMS signature success with a pinned Code Signing certificate;
- trusted timestamped Authenticode EXE success with a pinned publisher certificate;
- rejection of wrong Manifest signer pin, wrong publisher pin, manifest-byte tamper, signature-byte tamper and unsigned EXE;
- PCK tamper after Manifest signing rejected before directory swap;
- real helper directory swap/relaunch/ACK and rollback regressions remain green;
- hosted CI cannot execute `gh release create/upload` for unsigned reference assets;
- real interrupted HTTP Range resume and update desktop journey remain green;
- existing Iterations 59-63 release gates remain compatible;
- Windows Release export/run regressions remain green.

## Bootstrap boundary

The repository intentionally contains no real certificate SHA-256 pins. A first production baseline with real pins must be distributed through an already trusted/manual channel. That baseline can then authenticate subsequent automatic updates. No target package may bootstrap trust in itself.

## External boundary

The repository never stores or fabricates the Star World publisher private key, Manifest signing private key, CA issuance or TSA operation. Real pins are injected into the release source/configuration before export and become part of the qualified PCK/build identity.

Commercial release remains **HOLD** until the Iterations 60-63 real external qualification/signing evidence exists and the first pinned production baseline is deliberately prepared.
