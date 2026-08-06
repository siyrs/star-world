from pathlib import Path

roadmap = Path('docs/PRODUCT_ROADMAP.md')
text = roadmap.read_text(encoding='utf-8')
marker = '## Iteration 62 · 离线发布晋级与身份钉死（2026-08-07）'
if marker not in text:
    text += '''

## Iteration 62 · 离线发布晋级与身份钉死（2026-08-07）

- Promotion Pin 用稳定 `pin_id` 将发布所有者选择绑定到 candidate、chain bundle、package、commit、版本和最终 EXE/PCK；
- 商业 `-RequireReleaseGate` 必须同时提供在 Promotion Bundle 之外保留的 `ExpectedPinId`，不再只依赖包内自洽；
- 已验收的 Iteration 61 19 文件证据链保持不变，由独立 Promotion Bundle 外层封装；
- Promotion Bundle 固化 `release_qualification.json`、`project.godot` 与 `export_presets.cfg`，接收端通过临时合成 contract root 离线复核，不依赖当前 checkout；
- 外层清单继续拒绝缺失/额外/隐藏文件、哈希和长度漂移、reparse point、目录穿越与 promotion identity 漂移；
- 接收端验证回执写在不可变 Promotion Bundle 之外，并记录 promotion/pin/candidate/bundle/package 身份、manifest 哈希和验证器哈希；
- 永久门禁覆盖合同快照篡改、内层链篡改、错误 Pin、可见/隐藏注入、路径穿越、promotion ID 篡改和包内回执写入；
- 商业发布继续 **HOLD**，离线晋级完整性不能替代真实 E4-H、物理硬件、7,200 秒 soak、故障实验或发行方签名体系。

合同见：

- [RELEASE_PROMOTION_OFFLINE_VALIDATION.md](RELEASE_PROMOTION_OFFLINE_VALIDATION.md)
- [PRODUCT_ROADMAP_ITERATION_62.md](PRODUCT_ROADMAP_ITERATION_62.md)
'''
    roadmap.write_text(text, encoding='utf-8')

runner = Path('tests/run_all.ps1')
text = runner.read_text(encoding='utf-8')
anchor = '& "$PSScriptRoot\\developer_b\\validate_release_candidate_chain_iteration_61.ps1"'
addition = '& "$PSScriptRoot\\developer_b\\validate_release_promotion_iteration_62.ps1"'
if anchor not in text:
    raise SystemExit('run_all Iteration 61 anchor is missing')
if addition not in text:
    text = text.replace(anchor, anchor + '\n' + addition, 1)
    runner.write_text(text, encoding='utf-8')

readiness = Path('docs/tasks/20260731-v1.3.0-commercial-release-gameplay-polish/11-readiness-gates.md')
text = readiness.read_text(encoding='utf-8')
ready_marker = '## Post-implementation reconciliation · Iteration 62 · 2026-08-07'
if ready_marker not in text:
    text += '''

## Post-implementation reconciliation · Iteration 62 · 2026-08-07

Repository-owned release promotion now adds an externally retained Promotion Pin, frozen release/project/export contract snapshots, offline nested-chain validation and immutable handoff receipts. `-RequireReleaseGate` must be paired with the expected pin ID so a different internally consistent candidate cannot be promoted accidentally.

Commercial release remains **HOLD**. Independent E4-H review, minimum/recommended physical hardware, the real 7,200-second target-hardware soak, HDD/antivirus/power-loss experiments, release-owner selection and any publisher signing/timestamp authority remain external execution controls.
'''
    readiness.write_text(text, encoding='utf-8')
