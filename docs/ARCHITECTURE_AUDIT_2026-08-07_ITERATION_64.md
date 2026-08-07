# Architecture Audit · Iteration 64 · Publisher-Pinned Auto Update

Date: 2026-08-07

## Audit question

Can the existing GitHub Release updater guarantee that the package installed on a player's machine was authorized by the same publisher trust domain introduced by Iteration 63, including the PCK and every non-EXE payload, without placing publisher private keys in the repository or GitHub Actions?

## Findings

### 1. ZIP SHA-256 is integrity, not independent publisher authentication

The updater downloaded both the ZIP and its `.sha256` from the same GitHub Release. If the release publishing surface were replaced, the attacker could replace both values.

Decision: retain ZIP SHA-256 for corruption/resume identity, but do not treat it as publisher identity.

### 2. The old manifest had the same trust origin as the ZIP

`update-manifest.json` provided excellent exact-payload verification and prevented unlisted files, but it was itself unsigned. An attacker controlling the Release could regenerate the manifest for malicious payload bytes.

Decision: schema 2 adds a detached CMS signature over the exact manifest bytes.

### 3. Authenticode on EXE alone would leave PCK substitution open

Godot behavior lives substantially in `StarWorld.pck`. A valid old/same publisher-signed EXE can coexist with a replaced PCK.

Decision: the detached signed Manifest remains the authority for EXE, PCK and every other payload file. Authenticode independently authenticates the native executable.

### 4. Trust must come from the current installation

A target package cannot be allowed to ship a new certificate and say “trust me with this certificate.”

Decision: `UpdateService` loads and normalizes `data/update_trust_policy.json` from the currently running PCK before any download/install. It passes that immutable transaction policy to a validator extracted from the current PCK. Target content is not consulted for current transaction pins.

### 5. Certificate rotation needs overlap but must remain bounded

Permanent single-certificate pinning would make legitimate renewal operationally dangerous; unlimited pins would weaken auditability.

Decision: at most four unique SHA-256 certificate pins per trust domain, with an overlap rollout documented as the only supported rotation sequence.

### 6. Authentication must precede the filesystem transaction

Existing helper rollback is strong after swap, but a malicious package should never be allowed to mutate the install directory merely because rollback is available.

Decision: helper order is exact manifest/hash validation → CMS + Authenticode trust validation → first `Move-Item`. Static and real Windows tests enforce this ordering.

### 7. Hosted CI cannot be a commercial publisher without the real signing authority

The tag workflow previously exported and uploaded an unsigned package directly to GitHub Release. That becomes unsafe once the client requires publisher-pinned packages.

Decision: hosted CI produces reference-only artifacts. A separate external publisher validates already Authenticode-signed bytes, signs the manifest using the controlled certificate store, self-validates the same production trust chain and only then invokes `gh release`.

## Architecture

```text
CURRENT INSTALLED VERSION
  data/update_trust_policy.json
        │
        ├── manifest signer cert SHA-256 pins (max 4)
        └── EXE publisher cert SHA-256 pins (max 4)
        │
        ▼
GitHub Release ZIP + .sha256
        │
        ├── SHA-256 / resumable transfer identity
        ▼
Staging directory
        │
        ├── update-manifest.json ── detached CMS ── update-manifest.p7s
        │        │
        │        └── hashes EXE + PCK + every payload byte
        │
        └── StarWorld.exe ── Windows Authenticode + trusted TSA
                 │
                 ▼
current-install trust validator
        │
        ├── manifest signer pin + Code Signing EKU
        ├── publisher pin + Code Signing EKU
        └── timestamp + Time Stamping EKU
                 │
                 ▼
          ALLOW DIRECTORY SWAP
                 │
                 ▼
      existing ACK / rollback transaction
```

## State ownership

- GitHub Release owns transport location only, not trust identity.
- `ResumableHttpDownloader` owns partial transfer state only.
- `UpdatePackagePolicy` owns structural manifest semantics only; it does not perform Windows cryptography.
- `UpdateTrustPolicy` owns bounded current-install trust configuration.
- `windows_update_trust_validator.ps1` owns Windows CMS/Authenticode verification.
- `windows_update_helper.ps1` owns the install transaction and invokes trust verification before swap.
- target update content never owns the pins that authorize itself.

## Compatibility

- schema/protocol 1 remains structurally readable only for retained reference tests;
- production `UpdateService` requires schema/protocol 2 unless the explicit test-only reference override is enabled;
- original Range resume, exact manifest inventory, directory swap, relaunch ACK and rollback remain unchanged in purpose and retain dedicated regressions;
- the new trust policy is additive to the PCK and does not enter player saves.

## Risks and mitigations

- GitHub Release compromise: attacker cannot produce CMS/Authenticode signatures matching current-install pins.
- signed EXE + malicious PCK: signed Manifest binds PCK bytes.
- target self-bootstrap: current-install policy is serialized before target staging is promoted.
- expired/rotated certificate: bounded overlap allows planned rotation.
- publisher key theft: outside repository scope; real private keys remain external and revocation/rotation must replace pins.
- CI fixture mistaken for production: repository pins remain empty and CI test certificates are ephemeral/reference-only.
- post-download local same-user tamper: helper re-hashes package/files and authenticates staged bytes immediately before swap; a fully compromised same-user process remains outside the updater's trust boundary.

## Conclusion

Iteration 64 is the appropriate next repository-owned release/security iteration. It closes a real product delivery path that was not protected by Iteration 63, while preserving external key custody and the updater's existing reliability transaction.
