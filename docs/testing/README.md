---
siyrs_testing_document: 1
document_type: index
title: "星的世界 testing documentation index"
platforms: ["custom"]
indexed: true
---
# 《星的世界》测试权威索引

本目录是项目唯一的机器可发现测试合同。历史说明保留在 `docs/TESTING.md`，但全量测试、回归、UAT 与商业验收必须先读本索引，并以 `.siyrs/config.yaml` 的可执行计划和 fresh 证据为准；历史 PASS 不得替代重跑。

## Agent discovery contract

- “全量测试 / 商业验收”默认解析为 T3：确定性回归、全部桌面验收、性能场景、最终 Windows EXE 五 Profile 路线矩阵和 7200 秒严格长稳。
- UAT 只代表已实际执行的旅程，不自动证明最低配置、HDD、防病毒共存、代码签名或独立真人体验。
- 测试必须隔离 `APPDATA` / `LOCALAPPDATA`，不得读取、修改或删除真实玩家世界。
- Godot 退出码为 0 仍须扫描 `SCRIPT ERROR`、解析错误、ObjectDB/资源泄漏及严格门禁列出的引擎错误。
- 证据必须绑定 Git HEAD、工作树指纹、Godot 版本、命令、目标硬件、日志、截图和结果；只有实际运行成功才能标 PASS。

## How to use

1. 阅读 [测试治理](./00-test-governance.md) 与 [T1/T2/T3 选择](./00-test-tiers.md)。
2. 从 [游戏客户端用例](./game-cases.md) 解析稳定 Case ID 与原生 selector。
3. 执行 `.siyrs/config.yaml` 对应层级；本机 Godot 固定为仓库内 `build/tools/godot/Godot_v4.7-stable_win64_console.exe`。
4. lightweight 结论写入 [`evidence/`](./evidence/)；原始大日志、截图、性能 JSON 和包体放在被 Git 忽略的 `build/`。

## Product acceptance boundary

正式地图是五个数据驱动 Profile：`star_continent`、`desert_ruins`、`frozen_wastes`、`sky_islands`、`abyss_world`。产品没有传统主线/支线结局，“通关”项为 N/A；商业旅程终点定义为代表性探索与内容闭环、保存重载、死亡重生、安全返回菜单。

## Latest evidence

| Workflow | Scope | Commit/tree | Status | Evidence |
|---|---|---|---|---|
| 2026-08-08 fresh baseline | 原始 T3 runner，121 项 | `5cbaca66` + clean baseline | FAIL 115/121；6 runner failures + 1 engine error gate escape | `build/commercial-acceptance-20260808/t3/` |
| 2026-08-08 remediation | 隔离、生命周期合同、fatal gate、覆盖扩容 | working tree; awaiting independent full rerun | IN PROGRESS | `build/commercial-acceptance-20260808/` |

## Test debt and release gate

| Item | Severity | Owner | Target | Status/Evidence |
|---|---|---|---|---|
| 最低配置边界机与推荐配置边界机 | P0 release gate | Release QA | external physical machines | BLOCKED on this RTX 3090 reference host |
| 真实 HDD 与启用状态防病毒兼容 | P0 release gate | Release QA | external Windows host | BLOCKED: this host has NVMe and Defender disabled |
| 最终签名候选与签名后固定包复验 | P0 release gate | Release owner | signing environment | BLOCKED: certificate/private key and signtool unavailable |
| 独立真人 E4-H 五图内容签收 | P1 release gate | Independent QA | final fixed package | PENDING |

## Managed test document index

<!-- siyrs-testing-index:start -->
| Document | Type | Module | Case prefixes | Platforms |
|---|---|---|---|---|
| [00-test-governance.md](./00-test-governance.md) | governance |  |  | custom |
| [00-test-tiers.md](./00-test-tiers.md) | tiers |  |  | custom |
| [evidence/README.md](./evidence/README.md) | evidence |  |  | custom |
| [game-cases.md](./game-cases.md) | case-module | game | TC-GAME | custom |
<!-- siyrs-testing-index:end -->
