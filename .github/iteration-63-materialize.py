from pathlib import Path

roadmap = Path('docs/PRODUCT_ROADMAP.md')
text = roadmap.read_text(encoding='utf-8')
marker = '## Iteration 63 · 发行签名与最终分发门禁（2026-08-07）'
if marker not in text:
    text += '''

## Iteration 63 · 发行签名与最终分发门禁（2026-08-07）

- 商业候选必须先完成 Authenticode 签名与可信时间戳，再生成 candidate_id 和开始硬件/soak 资格；验收后重新签名被明确禁止；
- Windows 验签复用系统 Authenticode 信任引擎，并要求 Code Signing EKU；商业门禁同时要求可信时间戳与 Time Stamping EKU；
- 最终发行者身份不依赖 Subject 文本或 SHA-1 thumbprint，而由 Promotion Bundle 外部保留的发行证书 DER SHA-256 钉死；
- Distribution Gate 同时验证 Iteration 62 Promotion Pin、Promotion Bundle、已资格 EXE 哈希、发行证书 SHA-256 与可信时间戳；
- 已签名 EXE 必须与 candidate-chain 中已资格 EXE 的 SHA-256 完全一致，从而证明签名发生在资格验证之前；
- Distribution Receipt 写在不可变 Promotion Bundle 之外，并记录发行证书、时间戳证书和验证器哈希；
- Windows CI 使用临时自签 Code Signing 证书验证真实 Authenticode 路径，但因为没有真实 TSA 时间戳，商业模式必须 fail-close；
- 商业发布继续 **HOLD**，真实发行私钥、CA 证书、可信 TSA、真实外部资格和最终发行操作仍由外部安全环境产生。

合同见：

- [RELEASE_PUBLISHER_SIGNING_GATE.md](RELEASE_PUBLISHER_SIGNING_GATE.md)
- [PRODUCT_ROADMAP_ITERATION_63.md](PRODUCT_ROADMAP_ITERATION_63.md)
'''
    roadmap.write_text(text, encoding='utf-8')

runner = Path('tests/run_all.ps1')
text = runner.read_text(encoding='utf-8')
anchor = '& "$PSScriptRoot\\developer_b\\validate_release_promotion_iteration_62.ps1"'
addition = '& "$PSScriptRoot\\developer_b\\validate_publisher_signing_iteration_63.ps1"'
if anchor not in text:
    raise SystemExit('run_all Iteration 62 anchor is missing')
if addition not in text:
    text = text.replace(anchor, anchor + '\n' + addition, 1)
    runner.write_text(text, encoding='utf-8')

readiness = Path('docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/11-readiness-gates.md')
text = readiness.read_text(encoding='utf-8')
ready_marker = '## Post-implementation reconciliation · Iteration 63 · 2026-08-07'
if ready_marker not in text:
    text += '''

## Post-implementation reconciliation · Iteration 63 · 2026-08-07

Repository-owned final distribution validation now requires sign-before-qualification, Windows Authenticode verification, an externally retained publisher-certificate SHA-256 and a trusted timestamp for the commercial gate. The Distribution Gate composes the Iteration 62 Promotion Pin with the exact qualified executable hash, and Distribution Receipts remain outside the immutable Promotion Bundle.

CI uses an ephemeral self-signed Code Signing certificate only to exercise the Windows trust path. It deliberately cannot satisfy the trusted-TSA commercial condition. Commercial release remains **HOLD** pending the real publisher certificate/private-key operation, trusted timestamp, independent E4-H review, minimum/recommended physical hardware, real 7,200-second soak and physical HDD/antivirus/power-loss evidence.
'''
    readiness.write_text(text, encoding='utf-8')

board = Path('docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/09-feature-status-board.md')
text = board.read_text(encoding='utf-8')
text = text.replace('after Iteration 62.', 'after Iteration 63.')
text = text.replace(
    'chain-of-custody, offline promotion and anti-forgery workflows are complete',
    'chain-of-custody, offline promotion, publisher-signing validation and anti-forgery workflows are complete'
)
text = text.replace(
    'exact-package hardware collectors, strict soak harness, immutable candidate ID, 19-file chain and offline Promotion Bundle',
    'exact-package hardware collectors, strict soak harness, immutable candidate ID, 19-file chain, offline Promotion Bundle and publisher Distribution Gate'
)
text = text.replace(
    'real minimum/recommended machines and real 7,200-second target soak remain external',
    'real minimum/recommended machines, real 7,200-second target soak and real trusted publisher signing/timestamp remain external'
)
text = text.replace(
    'qualification anti-forgery, transport-integrity and offline promotion gates',
    'qualification anti-forgery, transport-integrity, offline promotion and publisher-signing gates'
)
text = text.replace(
    'E4-H recorder, fault-lab recorder, package assembler, supporting-report chain validator, Promotion Pin/receipt and decision boundary',
    'E4-H recorder, fault-lab recorder, package assembler, supporting-report chain validator, Promotion Pin/receipt, Distribution Gate/receipt and decision boundary'
)
if '## Iteration 63 closure' not in text:
    text = text.replace(
        '\n## Commercial decision\n',
        '''\n## Iteration 63 closure\n\n- Commercial policy requires Authenticode signing and trusted timestamping before candidate identity and qualification are generated.\n- Distribution validation uses Windows Authenticode trust, Code Signing EKU and an externally retained SHA-256 of the publisher certificate.\n- A trusted timestamp and Time Stamping EKU are mandatory for the commercial gate.\n- The signed executable must still equal the candidate-chain executable SHA-256, proving no post-qualification signing mutation.\n- Distribution Receipts remain external to the immutable Promotion Bundle and retain publisher/timestamp certificate and validator hashes.\n- CI signs a real fixture with an ephemeral locally trusted Code Signing certificate, but the intentionally missing real TSA timestamp keeps the commercial gate closed.\n\n## Commercial decision\n''',
        1,
    )
text = text.replace(
    'Repository implementation, the external qualification kit, candidate chain of custody and offline release-promotion workflow are accepted. Commercial release remains **HOLD** until real external evidence is collected, the release owner retains the intended `pin_id` independently, and the final Promotion Bundle passes `-RequireReleaseGate -ExpectedPinId <retained-pin>`.',
    'Repository implementation, external qualification, candidate chain of custody, offline promotion and publisher-signing validation are accepted. Commercial release remains **HOLD** until real external evidence is collected, the release owner independently retains the intended `pin_id` and publisher-certificate SHA-256, the final EXE is signed and trusted-timestamped before qualification, and the final Distribution Gate passes with both external identity pins.'
)
board.write_text(text, encoding='utf-8')
