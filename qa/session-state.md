# QA Session State

更新时间：2026-08-02 +08:00（本轮 Claude 接续 deepseek)

## 当前 Git

- 分支：`master`
- 本轮 HEAD：见 `git log`（QA-003 → save matrix → water/lava → deep journeys → stability → perf capture)
- 未推送任何本轮内容。

## 本轮（Claude）已完成

- **QA-003 独立复测**(2.6):`build/qa-independent-qa003-20260802-2007`,5 用例全过——design-system 137 checks（全部对比度 ≥4.5)、visual-refresh 32 checks/10 captures、accessibility 28 checks、layout-1024 24 checks、profile-journey 58 checks。BUG-UI-002 → qa-passed。
- **存读档矩阵**(7.1):`tests/qa/save_load_matrix_regression.gd`,35 checks。补四个缺口：手动存档经生产 hub `save_current()` 往返、覆盖写代际（primary 最新/.bak 上一代）、多世界独立负载、v1→v2 磁盘迁移。
- **水域+熔岩生命周期**(7.2/7.3):`tests/qa/water_lava_lifecycle_regression.gd`,27 checks 跑真实生成世界。星陆河流/冻原冰下水的干/入/游/上浮/出/快速重入；无氧气系统（按不存在记录）。**发现 BUG-LAVA-001**：熔岩=通用水态、可游泳、5 秒接触零伤害，已登记待 PM 决策，不阻塞发布。
- **五图深度旅程+内容矩阵**(6.2-6.7):`tests/qa/profile_deep_journey_regression.gd`,141 checks 全过。每图真实菜单进入（固定 seed 112358、隔离 QA 世界）→ profile 专属探针 → 死亡+真实「重生」按钮 → 持久化 → 重复进入 → 清理，pre/post world manifest 契约成立。
- **稳定性+极端输入**(7.4):`tests/qa/stability_extreme_input_regression.gd`,36 checks。120 键+90 鼠标突发（节点零泄漏）、UI scale 1.0/1.25/1.5、全屏标志往返、3× 暂停/恢复、快速进入/存档/返回。
- **性能采集**(5.3/5.4):`tests/qa/performance_scenario_capture.gd` + `tests/ci/run_performance_capture.ps1`,13 场景。**关键发现**:console.exe 是 launcher，必须采子进程 PID，否则 ws 只有 6.5 MiB（真实 384.8 MiB)。数据已写入 `qa/performance-baseline.md`。
- **长稳 soak**(5.5):`tests/qa/long_soak_journey.gd` + `tests/ci/run_long_soak.ps1`,30min 跨 5 图巡游（手册 120min 的脚本化压缩等效）。
- **最终 export**(8.2):`build/claude-final-export`,fresh export + release smoke 16/16。

## 证据目录

| 内容 | 路径 |
|---|---|
| QA-003 | `build/qa-independent-qa003-20260802-2007/` |
| 深度旅程 | `build/claude-deep-journey/` |
| 稳定性 | `build/claude-stability/` |
| 性能 | `build/claude-perf/` |
| soak | `build/claude-soak-30min/` |
| 最终 export | `build/claude-final-export/` |

## 当前问题

| ID | 等级 | 状态 | 证据 / 下一步 |
|---|---|---|---|
| BUG-UI-002 | P1 | qa-passed | QA-003 全过（见上）。 |
| BUG-LAVA-001 | P2 | open，待 PM 设计决策 | 熔岩=通用水态/零伤害；运行时证据在 water_lava_lifecycle_regression。不阻塞发布（无崩溃/恢复路径验证）。 |
| BUG-PERF-001 | P1 | 数据已采集 | 5.3/5.4 场景数据齐全；120min 以 30min 脚本化压缩替代，见 8.6 风险登记。 |

## 下一步

1. 等待 30min soak 与全量回归结果。
2. 完成 8.6 最终 review（20 条验收条件逐条对证据）。
