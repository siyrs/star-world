---
siyrs_testing_document: 1
document_type: evidence
title: "Commercial acceptance evidence ledger"
platforms: ["custom"]
indexed: true
---
# 商业验收证据账本

本目录只保存可审阅的轻量结论与证据绑定。原始日志、截图、导出包、性能采样和长稳逐周期报告保存在 Git 忽略的 `build/`，不得把这些大文件提交进仓库。

每次记录至少包含：日期、Git HEAD、工作树指纹、执行环境、原始命令、Case ID、结果、证据相对路径、候选包 SHA-256 和未关闭门禁。历史记录不可覆盖 fresh 结果。
