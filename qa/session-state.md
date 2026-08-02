# QA Session State

更新时间：2026-08-02 +08:00（**最终状态 — 发布完成**）

## 当前 Git

- 分支：`master`（已推送 origin，v1.3.0 tag 已发布）
- 最终 HEAD：`b50e6b2`（CHANGELOG）
- Release：https://github.com/siyrs/star-world/releases/tag/v1.3.0

## 发布验收结论

**推荐发布（RELEASE）已执行**：
- 47/47 OpenSpec 发布门槛全部完成
- 全量回归 113/113 EXIT 0（条件 17）
- fresh export smoke 16/16（`build/claude-final-export-v2`，含熔岩修复）
- 30min soak：291 循环跨 5 图、内存增长 1.9%、无退化（条件 13）
- 11 项问题全部 qa-passed，无剩余 open
- 20 条验收 19 条满足 + 1 条（独立分支）按用户决策记录（master）
- Windows 发布资产校验：GitHub API digest + sha256 文件 + 本地下载三重一致

## 本轮（Claude，2026-08-02）完成记录

| OpenSpec | 内容 | 证据 |
|---|---|---|
| 2.6 | QA-003 独立 UI 复测 | `build/qa-independent-qa003-20260802-2007`，279 checks，对比度全 ≥4.5 |
| 5.3/5.4 | 性能采集 | `build/claude-perf`（13 场景 + 52 内存样本，ws_p95 384.8 MiB） |
| 5.5 | 长稳 soak | `build/claude-soak-30min`（291 循环，1.9% 增长） |
| 6.2-6.7 | 五图深度旅程+内容矩阵 | `build/claude-deep-journey`（141 checks） |
| 7.1 | 存读档矩阵 | `tests/qa/save_load_matrix_regression.gd`（35 checks） |
| 7.2/7.3 | 水域+熔岩 | `tests/qa/water_lava_lifecycle_regression.gd`（32 checks） |
| 7.4 | 稳定性+极端输入 | `tests/qa/stability_extreme_input_regression.gd`（36 checks） |
| 8.2 | 最终 fresh export | `build/claude-final-export-v2`（16/16） |
| 8.5/8.6 | commits + 最终 review | `qa/final-release-report.md` |

## 修复记录

- **BUG-LAVA-001**（P2，PM 决策后实现）：熔岩灼烧（4.0/0.5s 间隔门控、离开即停、持续致死、重生恢复）
- **BUG-LEAK-001**（P1）：4 个测试出口 ObjectDB/Resource 泄漏（裸 Node free + audio dispose）
- 9 个保存/目录/GUI 测试隔离断言修正（有 9 个真实用户世界环境下）

## 问题登记

11 项全部 qa-passed（`qa/issues-found.md`）。无 open 问题。

## 已知边界（登记为发布风险，不阻塞）

1. CPU/GPU/VRAM 无可靠跨进程计数器（性能报告以 FPS/帧时/内存为代理）
2. 120min 长稳以 30min 脚本化压缩替代（脚本支持 `-SoakSeconds 7200` 扩展）
3. 本轮在 master 而非独立分支（用户决策保持 master）
4. 水为安全流体（无氧气/溺水）——未决设计，下个版本可决策
