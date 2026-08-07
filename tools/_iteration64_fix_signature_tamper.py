from pathlib import Path

path = Path('tests/qa/windows_update_publisher_trust_acceptance.ps1')
text = path.read_text(encoding='utf-8')
old = "$signatureBytes[[Math]::Min(32, $signatureBytes.Length - 1)] = $signatureBytes[[Math]::Min(32, $signatureBytes.Length - 1)] -bxor 0x01"
new = "$signatureBytes[0] = $signatureBytes[0] -bxor 0x01"
if old not in text:
    raise SystemExit('signature tamper anchor missing')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
