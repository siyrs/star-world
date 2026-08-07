from pathlib import Path

root = Path('.')

# Full runner: keep release/security iteration order explicit.
run_all = root / 'tests/run_all.ps1'
text = run_all.read_text(encoding='utf-8')
needle = '& "$PSScriptRoot\\developer_b\\validate_publisher_signing_iteration_63.ps1"\n'
insert = needle + '& "$PSScriptRoot\\developer_b\\validate_publisher_pinned_auto_update_iteration_64.ps1"\n'
if 'validate_publisher_pinned_auto_update_iteration_64.ps1' not in text:
    if needle not in text:
        raise SystemExit('run_all Iteration 63 anchor missing')
    text = text.replace(needle, insert, 1)
run_all.write_text(text, encoding='utf-8')

# Fix PowerShell test pins: scalar 64-char strings, not collection replication.
crypto = root / 'tests/qa/windows_update_publisher_trust_acceptance.ps1'
text = crypto.read_text(encoding='utf-8')
text = text.replace("@('f' * 64)", "@((('f' * 64) -join ''))")
text = text.replace("@('e' * 64)", "@((('e' * 64) -join ''))")
crypto.write_text(text, encoding='utf-8')

# Main roadmap appendix.
roadmap = root / 'docs/PRODUCT_ROADMAP.md'
text = roadmap.read_text(encoding='utf-8')
if '## Iteration 64 · 发行者钉死自动更新' not in text:
    text = text.rstrip() + '''\n\n\n## Iteration 64 · 发行者钉死自动更新（2026-08-07）\n\n- 自动更新不再把同源 GitHub Release ZIP、`.sha256` 与未签名 Manifest 视为独立发行身份；\n- `update-manifest.json` 升级到 schema/protocol 2，并由 detached CMS `update-manifest.p7s` 绑定 EXE、PCK 与全部载荷哈希；\n- staged EXE 同时验证 Windows Authenticode、Code Signing EKU、当前安装 Publisher Certificate SHA-256 Pin、可信 TSA 与 Time Stamping EKU；\n- Manifest signer 与 EXE publisher 使用当前安装版本携带的独立证书 SHA-256 Pin，目标包不能决定本次认证使用的信任根；\n- 每个信任域最多四个 Pin，证书轮换必须先部署 old+new overlap，再移除旧 Pin；\n- helper 在任何安装目录 `Move-Item` 之前完成逐文件哈希、CMS 与 Authenticode 认证，原有 ACK/rollback 事务保持不变；\n- Hosted CI 只生成 `REFERENCE-ONLY` 更新资产，不再直接创建未签名商业 GitHub Release；真实上传由外部签名工作站工具在验证 EXE/TSA、CMS 与双 Pin 后执行；\n- 仓库默认真实 Pin 为空并 fail-close，首次生产启用必须通过已信任/手动渠道部署带真实 Pin 的基线版本；\n- 商业发布继续 **HOLD**，真实发行/Manifest 私钥、证书 Pin 与 Iterations 60-63 的真实外部资格仍由外部安全环境产生。\n\n合同见：\n\n- [GITHUB_RELEASE_AUTO_UPDATE.md](GITHUB_RELEASE_AUTO_UPDATE.md)\n- [PUBLISHER_PINNED_AUTO_UPDATE.md](PUBLISHER_PINNED_AUTO_UPDATE.md)\n- [PRODUCT_ROADMAP_ITERATION_64.md](PRODUCT_ROADMAP_ITERATION_64.md)\n'''
roadmap.write_text(text, encoding='utf-8')

status = root / 'docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/09-feature-status-board.md'
text = status.read_text(encoding='utf-8')
text = text.replace('after Iteration 63.', 'after Iteration 64.')
text = text.replace(
    'offline promotion, publisher-signing validation and anti-forgery workflows are complete',
    'offline promotion, publisher-signing validation, publisher-pinned auto-update and anti-forgery workflows are complete'
)
text = text.replace(
    'exact-package hardware collectors, strict soak harness, immutable candidate ID, 19-file chain, offline Promotion Bundle and publisher Distribution Gate',
    'exact-package hardware collectors, strict soak harness, immutable candidate ID, 19-file chain, offline Promotion Bundle, publisher Distribution Gate and publisher-pinned updater'
)
text = text.replace(
    'includes cross-domain campaigns, qualification anti-forgery, transport-integrity, offline promotion and publisher-signing gates',
    'includes cross-domain campaigns, qualification anti-forgery, transport-integrity, offline promotion, publisher-signing and publisher-pinned updater gates'
)
if '## Iteration 64 closure' not in text:
    marker = '\n## Commercial decision\n'
    addition = '''\n## Iteration 64 closure\n\n- Auto-update schema/protocol 2 carries a detached CMS signature over the exact payload-hash Manifest.\n- Current-install Manifest signer and Authenticode publisher certificate SHA-256 pins authenticate the target; target content cannot select its own trust roots.\n- The signed Manifest binds `StarWorld.pck`, closing the valid-EXE/malicious-PCK substitution path.\n- Windows helper verifies payload hashes, CMS, Authenticode, Code Signing EKU and trusted TSA before the first install-directory move.\n- Four-pin bounded overlap supports certificate rotation without unbounded trust growth.\n- Hosted CI is reference-only and cannot publish unsigned commercial update assets; the external signing workstation owns signed Manifest creation and `gh release` publication.\n- Repository default real pins remain empty/fail-closed; the first production pinned baseline is an external bootstrap event.\n'''
    if marker not in text:
        raise SystemExit('status board commercial marker missing')
    text = text.replace(marker, addition + marker, 1)
text = text.replace(
    'Repository implementation, external qualification, candidate chain of custody, offline promotion and publisher-signing validation are accepted.',
    'Repository implementation, external qualification, candidate chain of custody, offline promotion, publisher-signing validation and publisher-pinned auto-update are accepted.'
)
status.write_text(text, encoding='utf-8')

readiness = root / 'docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/11-readiness-gates.md'
text = readiness.read_text(encoding='utf-8')
if 'Post-implementation reconciliation · Iteration 64' not in text:
    text = text.rstrip() + '''\n\n\n## Post-implementation reconciliation · Iteration 64 · 2026-08-07\n\nRepository-owned automatic update delivery now consumes the publisher trust introduced by Iteration 63. Schema/protocol 2 signs the exact payload Manifest with detached CMS, the staged EXE independently requires pinned Authenticode plus trusted timestamp, and all pins come from the currently installed version before the target package is promoted. The existing directory-swap/ACK/rollback transaction remains after this new pre-swap authentication gate.\n\nHosted CI no longer publishes unsigned public update assets; it produces reference-only evidence. Real Manifest signing, real certificate pins, first-baseline bootstrap and signed GitHub Release publication remain external release controls. Commercial release remains **HOLD** with the existing independent/physical qualification requirements.\n'''
readiness.write_text(text, encoding='utf-8')
