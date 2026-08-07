from pathlib import Path

replacements = {
    Path('docs/PRODUCT_ROADMAP.md'): [
        (
            '- Windows CI 使用临时自签 Code Signing 证书验证真实 Authenticode 路径，但因为没有真实 TSA 时间戳，商业模式必须 fail-close；',
            '- Windows CI 使用 hosted runner 上真实可信且已时间戳的 Authenticode 二进制验证系统信任、证书 SHA-256 Pin 与时间戳 EKU；该 fixture 不是 Star World 且 Promotion 仍为 reference-only，不能关闭商业门禁；',
        ),
    ],
    Path('docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/09-feature-status-board.md'): [
        (
            '- CI signs a real fixture with an ephemeral locally trusted Code Signing certificate, but the intentionally missing real TSA timestamp keeps the commercial gate closed.',
            '- CI validates a real trusted, timestamped Authenticode binary already present on the hosted Windows image, including signer-certificate SHA-256 and timestamp EKU; that binary is not Star World and the Promotion fixture remains reference-only, so it cannot close the commercial gate.',
        ),
    ],
    Path('docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/11-readiness-gates.md'): [
        (
            'CI uses an ephemeral self-signed Code Signing certificate only to exercise the Windows trust path. It deliberately cannot satisfy the trusted-TSA commercial condition. Commercial release remains **HOLD** pending the real publisher certificate/private-key operation, trusted timestamp, independent E4-H review, minimum/recommended physical hardware, real 7,200-second soak and physical HDD/antivirus/power-loss evidence.',
            'CI verifies a real trusted, timestamped Authenticode binary already present on the hosted Windows image and dynamically checks its signer-certificate SHA-256 and timestamp EKU. It does not create or use a Star World publisher key, and the Promotion fixture remains reference-only. Commercial release remains **HOLD** pending the real publisher certificate/private-key operation, trusted timestamp on the final Star World EXE, independent E4-H review, minimum/recommended physical hardware, real 7,200-second soak and physical HDD/antivirus/power-loss evidence.',
        ),
    ],
}

for path, pairs in replacements.items():
    text = path.read_text(encoding='utf-8')
    for old, new in pairs:
        if old not in text:
            raise SystemExit(f'missing expected text in {path}: {old}')
        text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')
