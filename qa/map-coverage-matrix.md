# 五图地图证据矩阵

状态：**发布关键连续路线已通过；无限世界完整探索与独立 E4-H 仍不成立**  
复审日期：2026-08-05；2026-08-08 商业验收重跑刷新（见末节）

> “有界连续路线、区域采样、最终包截图”不等于“完整探索”。地图由程序生成，不能通过有限测试证明所有 Seed、所有坐标和所有随机组合。

| Profile | 正常进入 | 区域 E3 | 连续正常路线 | 最终包路线 E4-A | 重点环境合同 | 独立 E4-H | 完整探索 | 发布状态 |
|---|---|---|---|---|---|---|---|---|
| `star_continent` | 通过 | ≥6 分离区域 | **E3 通过** | 五图矩阵 | 森林/草地/洞穴/矿物/水体合同 | 待签字 | **否** | HOLD |
| `desert_ruins` | 通过 | ≥6 分离区域 | **E3 通过** | 五图矩阵 | 沙漠/遗迹/仙人掌/资源合同 | 待签字 | **否** | HOLD |
| `frozen_wastes` | 通过 | ≥6 分离区域 | **E3 通过** | 五图矩阵 | 冰雪/冻土/水域/资源合同 | 待签字 | **否** | HOLD |
| `sky_islands` | 通过 | ≥6 分离区域 | **E3 通过** | 五图矩阵 | 浮岛/高空/跌落恢复/资源合同 | 待签字 | **否** | HOLD |
| `abyss_world` | 通过 | ≥6 分离区域 | **E3 通过** | 五图矩阵 | 洞穴/熔岩/深度/敌对遭遇合同 | 待签字 | **否** | HOLD |

## 连续正常路线 | **E3 通过**

PR #100 的路线从每个 Profile 的生产出生点开始，使用正式移动与跳跃输入、真实 `CharacterBody3D` 和已加载体素碰撞，至少完成 20 步、14 米位移和 2 个唯一 Chunk；出生后不修改玩家坐标。

PR #101 将同一生产路线合同放入最终 PCK，通过一个已验证的 Windows EXE/PCK 依次运行五图。报告必须满足：

- `transport_after_spawn=false`；
- `player_transform_writes=0`；
- 路线终点截图通过视觉细节检查，并且诊断世界教程已完成、引导卡片不遮挡地图；
- 每图输出真实 frame-time、加载时间和外部内存；
- GitHub Runner 标记为 `hosted_ci_reference`，不冒充目标硬件。

## 仍需独立体验的地图内容

独立 E4-H 复审必须按最终候选包检查每张图的代表性遗迹、洞穴、水域、高空、边界、视觉重复、引导理解和手感。该人工抽样仍不能声明无限程序化空间“完整探索”，但它是商业发布所需的重点区域体验签字。

## 2026-08-08 商业验收重跑（分支 `codex/commercial-acceptance-20260808`）

最终候选包五图矩阵（`journey-matrix-final/` → 性能修复后 `journey-matrix-final-v2/` → 出生连通性修复后 `journey-matrix-final-v3/` 复取）逐图实测：

| Profile | 路线步数 | 位移 | 唯一 Chunk | 最大跌落 | 平均 FPS | 1% Low | p95 | p99 | 世界启动 | WS p95 | 判定 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `star_continent` | 36/36 | 28.4m | 3 | 1.00m | 149.9 | 83.5 | 8.99ms | 11.39ms | 1834ms | 369 MiB | 通过（最终包 v3） |
| `desert_ruins` | 36/36 | 34.9m | 5 | 0.00m | 164.7 | 102.1 | 7.00ms | 9.39ms | 1084ms | 356 MiB | 通过（最终包 v3） |
| `frozen_wastes` | 36/36 | 35.9m | 3 | 1.00m | 165.6 | 138.9 | 7.03ms | 7.18ms | 707ms | 356 MiB | 通过（最终包 v3） |
| `sky_islands` | 36/36 | 27.3m | 2 | 1.00m | 165.7 | 146.6 | 6.72ms | 6.82ms | 1428ms | 367 MiB | 通过（最终包 v3） |
| `abyss_world` | 36/36 | 36.2m | 4 | 1.00m | 160.9 | 101.9 | 7.14ms | 9.14ms | 642ms | 369 MiB | 通过（最终包 v3） |

五图共同合同：零出生后传送（`player_transform_writes=0`）、视觉细节全过、教程卡片全隐藏、逐图权威退出全干净（`authoritative_quit:true`，生命周期时序单调）。推荐档阈值：avg≥60、1% low≥45、p95≤22.22ms、p99≤33.33ms、加载≤6s、WS≤6144 MiB。

本轮新关闭的地图级缺陷（详见 `qa/issues-found.md`）：

- `star_continent`：台阶/半砖可行走（BUG-STAIR-STEP-001）、台阶坡面地面模型（BUG-STAIR-RAMP-GROUND-SCAN-001，全图所有楼梯受益）、虚空悬浮（BUG-VOID-LEVITATE-001）、生成坠 Chunk（BUG-SPAWN-CHUNK-001）、流式帧刺（BUG-PERF-CHUNK-STEP-001，全图受益）、地面保持扫描放大（BUG-PERF-GROUND-SCAN-001）。
- 全部 Profile：出生微连通孤岛迁移（BUG-SPAWN-WALKABLE-REACH-001，全图出生质量受益，约 10% 种子受影响）。
- `abyss_world`：熔岩玩家物理在修复回归中持续锁定（BUG-LAVA-001 既有回归链）。
- `sky_islands`：高空谨慎下降（BUG-QA-SKY-DESCENT-001 既有）+ 本轮悬浮修复同根因复核。

> 上表为最终候选包 v3（`export-final-v3/`，含台阶坡面地面模型修复 `bb46e35` 与出生连通性门禁 `02e8793`）的五图矩阵 v3 实测（`journey-matrix-final-v3/`）；推荐档硬件资格同包复测 35/35 断言全过（`hardware-qualification-recommended-v3/`）。性能修复前矩阵 v1（`journey-matrix-final/`）、坡面修复后矩阵 v2（`journey-matrix-final-v2/`）与修复中 A/B（`export-perf-fix/`）存档保留。
