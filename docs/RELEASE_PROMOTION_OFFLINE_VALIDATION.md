# Release Promotion Offline Validation

Iteration 62 adds a promotion layer above the accepted Iteration 61 candidate chain. The inner chain remains unchanged. The promotion layer solves two operational problems: the receiving machine should not need to trust its current repository checkout, and the final release gate must be pinned to the candidate deliberately selected by the release owner.

## 1. Keep the Iteration 61 chain unchanged

First create and validate the existing candidate chain exactly as documented in `RELEASE_CANDIDATE_CHAIN_OF_CUSTODY.md`.

The resulting directory remains the canonical Iteration 61 chain and is never mutated by the promotion tools.

## 2. Create and retain the promotion pin

After the release owner selects the intended candidate, create one pin:

```powershell
pwsh -NoProfile -File tests/ci/new_release_promotion_pin.ps1 `
  -ProjectRoot . `
  -ChainBundleDirectory delivery\star-world-v1.3.0 `
  -ReleaseOwnerId release-owner-a `
  -ReleaseChannel commercial `
  -OutputPath approvals\v1.3.0-promotion-pin.json
```

The pin binds:

- `candidate_id`;
- Iteration 61 `bundle_id`;
- Iteration 60 `package_id`;
- commit and version;
- EXE and PCK SHA-256;
- release channel;
- release-owner label.

The resulting `pin_id` is deterministic for those facts. Keep the pin ID outside the promotion bundle: ticket, approval system, protected release note or another controlled record. The repository does not claim that the label is a cryptographic human identity.

## 3. Assemble the Promotion Bundle

```powershell
pwsh -NoProfile -File tests/ci/new_release_promotion_bundle.ps1 `
  -ProjectRoot . `
  -ChainBundleDirectory delivery\star-world-v1.3.0 `
  -PromotionPinPath approvals\v1.3.0-promotion-pin.json `
  -OutputDirectory promotion\star-world-v1.3.0
```

For a real target-hardware package, add `-RequireReleaseGate`.

The output wraps the complete Iteration 61 chain and adds:

```text
promotion-manifest.json
promotion-pin.json
contracts/data/release_qualification.json
contracts/project.godot
contracts/export_presets.cfg
candidate-chain/...
```

The contract files are frozen snapshots from the checkout used to assemble the promotion payload. They are not substitutes for the commit hash; they make the receiving validation independent from whatever repository checkout happens to exist later.

## 4. Validate offline with the retained pin

The receiving machine needs the audited validation scripts, but the evidence data no longer depends on live repository contract files:

```powershell
pwsh -NoProfile -File tests/ci/validate_release_promotion_bundle.ps1 `
  -PromotionBundleDirectory D:\received\star-world-v1.3.0 `
  -ExpectedPinId <pin-id-retained-outside-the-bundle>
```

For commercial approval:

```powershell
pwsh -NoProfile -File tests/ci/validate_release_promotion_bundle.ps1 `
  -PromotionBundleDirectory D:\received\star-world-v1.3.0 `
  -ExpectedPinId <pin-id-retained-outside-the-bundle> `
  -RequireReleaseGate
```

`-RequireReleaseGate` refuses to run without `-ExpectedPinId`. The nested Iteration 61 validator is executed against a temporary synthetic contract root built only from the frozen snapshots carried in the Promotion Bundle.

The validator checks:

- the outer manifest and exact physical file inventory;
- visible and hidden extra files;
- reparse points and unsafe paths;
- SHA-256 and length for every payload file;
- deterministic `promotion_id`;
- the promotion pin and externally retained expected pin ID;
- the complete nested Iteration 61 chain;
- candidate/package/pin equality;
- frozen release qualification, project and export-preset contracts;
- the Iteration 60 release gate when requested.

## 5. Record a handoff receipt without changing the bundle

After a receiver validates the payload, create a receipt outside the canonical directory:

```powershell
pwsh -NoProfile -File tests/ci/new_release_promotion_receipt.ps1 `
  -PromotionBundleDirectory D:\received\star-world-v1.3.0 `
  -ExpectedPinId <retained-pin-id> `
  -ReceiverId qa-machine-minimum `
  -OutputPath D:\receipts\qa-machine-minimum.json
```

For a real final release check, add `-RequireReleaseGate`.

The receipt records:

- `promotion_id`, `pin_id`, `candidate_id`, chain `bundle_id` and `package_id`;
- receiver label and validation time;
- promotion-manifest SHA-256;
- hashes of the promotion, pin and chain validators used for that check;
- whether the embedded package passed the commercial release gate.

Receipt output inside the Promotion Bundle is rejected. Validation evidence must not mutate the payload it is describing.

## Security boundary

Iteration 62 protects against accidental candidate substitution, stale checkout dependence, transfer corruption and untracked post-validation mutation. It does not provide a public-key signature, trusted timestamp or proof that a human/physical event really occurred.

If the publisher requires cryptographic identity authenticity, use an external signing or artifact-attestation system and retain that signature alongside the Promotion Bundle. Do not replace the existing content hashes or evidence contracts with a weaker shared secret.
