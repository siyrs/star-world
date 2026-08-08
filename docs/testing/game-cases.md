---
siyrs_testing_document: 1
document_type: case-module
title: "Game client commercial acceptance cases"
module: "game"
case_prefixes: ["TC-GAME"]
platforms: ["custom"]
indexed: true
---
# 游戏客户端商业验收用例

## Scope and shared references

覆盖五 Profile、生产 GameScene、内容闭环、存档、输入/UI、碰撞、天气/流体、性能、导出包与长稳。详细历史脚本清单保留在 `docs/TESTING.md`；发布策略阈值以 `data/release_qualification.json` 为唯一数值来源。

## Canonical cases

| Case ID | Tier | Role | Priority | Scenario | Preconditions | Steps | Expected result | Selector/Test ID | Evidence point | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| TC-GAME-001 | T2 | main-path | P0 | 五 Profile 菜单创建、进入、保存、继续、返回 | fresh isolated user data | 对每个 Profile 走生产菜单和生产 GameScene | Profile/Seed/世界元数据一致；可保存重载并安全返回 | `profile_release_journey_regression.gd` | 日志、五图截图、旅程 JSON | active |
| TC-GAME-002 | T2 | boundary | P0 | 存档中断、损坏与权威恢复 | 隔离世界目录 | 执行 checkpoint/manifest/transaction 恢复路径 | 无数据串图；回退与诊断符合合同 | `save_recovery_desktop_acceptance.gd` | 日志、恢复报告、截图 | active |
| TC-GAME-003 |  | regression | P0 | 静态与 headless deterministic 全量 | Godot 4.7 | 运行所有登记 validator/GDScript，严格扫 diagnostics | 0 failure、0 fatal diagnostics、0 leak | `tests/run_all.ps1` | 汇总与原始 stdout/stderr | active |
| TC-GAME-004 |  | uat-automation | P0 | 全部真实桌面 acceptance | 可用桌面渲染与隔离用户目录 | 顺序运行所有 `*_desktop_acceptance.gd` | 每例业务断言、截图和 strict diagnostics 均通过 | `run_all_desktop_acceptance.ps1` | persistent summary、逐例日志/截图 | active |
| TC-GAME-005 |  | release-package | P0 | 同一最终 Windows EXE/PCK 五 Profile 路线 | 固定导出候选 | 首图导出，后四图复用精确包体执行路线 | 五图无 transport/transform 写入作弊；包哈希一致 | `run_windows_export_journey_matrix.ps1` | matrix JSON、包哈希、五图日志/截图 | active |
| TC-GAME-006 |  | performance | P0 | 性能场景与策略阈值 | 固定候选与硬件清单 | 采集 FPS、1% low、p95/p99、加载和工作集 | 所有值满足 `release_qualification.json` 对应层级 | `run_performance_capture.ps1` | metrics JSON、机器清单 | active |
| TC-GAME-007 |  | stability | P0 | 7200 秒严格长稳 | TC-GAME-005 候选与权威 lifecycle | 至少 10 条路线循环、记录内存与 fatal diagnostics | 时长/路线数达标、增长不超策略、0 fatal、生命周期有效 | `run_strict_target_hardware_soak.ps1` | soak JSON、逐周期报告、哈希 | active |
| TC-GAME-008 |  | external-uat | P0 | 边界硬件、HDD/AV、签名后包与独立真人五图签收 | 外部机器、证书、独立操作人 | 复用签名后固定包执行资格包和 E4-H | 所有外部门禁有可验证签收且无未豁免 P0/P1 | external qualification package | 签名/机器/操作人/矩阵证据 | blocked |

## Platform notes

- Windows 桌面为当前唯一发布平台；其他平台不在本轮商业发布声明中。
- 本机 RTX 3090 / NVMe 只产生高配 reference 证据，不能向下外推最低配置或 HDD 结论。
