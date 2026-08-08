---
siyrs_testing_document: 1
document_type: tiers
title: "T1/T2/T3 selection and execution"
platforms: ["custom"]
indexed: true
---
# T1 / T2 / T3 选择与执行

- **T1**：变更驱动回归。当前安全后备命令是完整 deterministic runner；可按变更缩窄，但必须扩展到共享生命周期、存档、输入和 Service Hub 影响面。
- **T2**：固定 selector `commercial-smoke-v1`。包含五 Profile 正常菜单/创建/继续主路径，以及存档恢复边界路径。
- **T3**：严格商业发布门禁。依序运行 deterministic 全量、全部桌面 acceptance、性能场景、同一最终 EXE/PCK 五 Profile 路线矩阵及 7200 秒 reference soak。

T3 的本机自动化通过仍不能替代外部最低/推荐边界硬件、HDD、防病毒共存、签名后候选和独立真人 E4-H；这些门禁未完成时最终结论必须为 HOLD。

机器计划：

```powershell
py -3.12 C:\Users\sirius\.codex\skills\siyrs-skill\scripts\siyk.py config validate --root .
py -3.12 C:\Users\sirius\.codex\skills\siyrs-skill\scripts\siyk.py docs validate --root . --strict
py -3.12 C:\Users\sirius\.codex\skills\siyrs-skill\scripts\siyk.py plan --root . --tier t3
```
