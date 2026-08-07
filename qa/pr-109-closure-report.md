# PR #109 Closure Report · Iteration 64

## Scope reviewed

Iteration 64 secures the in-game GitHub Release updater with publisher identity rather than same-origin hashes alone.

Repository-owned delivery includes:

- schema/protocol 2 updater Manifest;
- detached CMS signature covering the exact Manifest bytes;
- Manifest signer certificate DER SHA-256 pins loaded from the current install;
- staged EXE Authenticode publisher certificate DER SHA-256 pins loaded from the current install;
- Code Signing EKU, trusted timestamp and Time Stamping EKU verification;
- a maximum four-pin overlap rotation policy per trust domain;
- trust validation before any install-directory swap;
- unchanged post-authentication directory swap, relaunch ACK and rollback semantics;
- deterministic signed Manifest generation/signing/packaging tools for the external publisher workstation;
- hosted CI restricted to reference-only assets instead of unsigned public GitHub Release publication;
- permanent Windows/Godot quality gates and retained reference compatibility.

## Review-found corrections

1. SHA-256 + an unsigned Manifest were recognized as same-origin integrity evidence, not independent publisher authentication.
2. EXE Authenticode alone was rejected as insufficient because a legitimate signed EXE could be paired with a substituted PCK.
3. Trust roots were moved to the currently installed PCK and serialized before installation; target content cannot select the pins that authorize itself.
4. Publisher authentication is ordered before the first install-directory `Move-Item`, so malicious content does not rely on rollback after mutation.
5. Hosted tag CI lost unsigned public Release publication capability; real publication moved to the external signing workstation.
6. Legacy helper swap/ACK/rollback fixtures are explicitly reference-only and cannot claim publisher authentication.
7. The first CMS tamper regression flipped a DER byte that could lie outside the signed-value path; it was corrected to corrupt the ASN.1 envelope deterministically without weakening production validation.

## Evidence boundary

Repository defaults intentionally contain no real publisher or Manifest signer certificate pins. The first production pinned baseline, real private keys, CA/TSA operations, and Iterations 60-63 real external qualification remain external controls.

Merge is permitted only after the final PR head completes all triggered permanent GitHub Actions checks successfully and the branch remains based on the current `master` without unresolved review threads.
