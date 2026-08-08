---
siyrs_testing_document: 1
document_type: governance
title: "Test governance and commercial release contract"
platforms: ["custom"]
indexed: true
---
# 测试治理与商业发布合同

## Authority

权威入口是 [README.md](./README.md)。每项行为只有一个稳定 Case ID；框架原生脚本负责执行，Markdown 只定义合同和绑定证据。

## Canonical case rules

- 使用稳定 `TC-GAME-NNN`，不得静默删除或重编号。
- T2 每个模块至少包含一个 `main-path` 与一个 `boundary` 用例。
- 五 Profile 的共同能力与差异能力均须给出实际旅程证据；探针、静态合同、截图和编译不能彼此冒充。
- 产品无传统任务结局，不得为了验收伪造“主线通关”；以教程/探索里程碑、内容闭环、保存恢复、死亡重生和安全退出作为可验证终点。

## Isolation and evidence rules

- 每个自动化用例使用独立 `APPDATA` / `LOCALAPPDATA`。执行前后清单与哈希用于证明真实玩家数据未变。
- 成功条件同时包括：业务断言、进程退出码、严格 diagnostics、预期证据文件、候选包 SHA-256 与执行环境。
- 导出后所有旅程、性能与长稳必须复用同一 EXE/PCK；重新导出得到的是新候选，不可拼接证据。
- hosted/reference 高配机器只能产生参考性能，不得声明最低/推荐边界硬件通过。
- 凭据、证书私钥和玩家身份不得写入仓库或证据。

## Release blocking

P0 数据丢失、存档污染、崩溃、严格诊断、关键旅程失败、指标不达标、候选包不一致或外部硬件/签名门禁缺失均保持 HOLD。P1 默认阻断，除非有责任人、影响、回滚方案和独立回归证据的书面豁免。
