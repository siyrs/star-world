# 《星的世界》最终发布质量报告

状态：**DRAFT — 不建议发布**

生成时间：2026-08-02
分支：`codex/commercial-release-gameplay-polish`
基线 HEAD：`7dba322f9f030672acdbd3621f5e0f80d6254ec8`；本轮修复尚未提交。

## 执行摘要

- 正式地图：5；基础正常入口/可玩状态/返回与隔离清理：**5/5 桌面通过**。
- 已实现的传统通关地图：**0**。项目没有可由任务或结局状态证明的传统通关条件，因此没有伪造“已通关”。
- 本轮修复：纹理按钮全状态有效对比度、真实树冠阻挡夹具、保存位置保留、发布外部内存采样、6 个测试树外 Transform3D 诊断。
- 回归：UI 137/137、Spawn 54/54（focused）、五 Profile 基础旅程 58/58、fresh export smoke 16/16、全量回归脚本 exit 0。
- 发布结论：**不发布**。29 ObjectDB + 8 Resource 泄漏尚未关闭；五地图完整内容/水域/死亡/存读档/碰撞、性能与 120 分钟长稳尚未完成。

## 地图覆盖

| 地图 | 进入 | 基础探索 | 水域 | 边界 | 存档元数据 | 死亡复活 | 完整旅程 | 剩余问题 |
|---|---|---|---|---|---|---|---|---|
| 星辰大陆 | PASS | 未完成 | 未测 | 未测 | 创建元数据 PASS | 未测 | 未完成 | 水/边界/战斗/持久化重入 |
| 荒漠遗迹 | PASS | 未完成 | 不适用待确认 | 未测 | 创建元数据 PASS | 未测 | 未完成 | 地下路线/边界/重入 |
| 极寒冰原 | PASS | 未完成 | 未测 | 未测 | 创建元数据 PASS | 未测 | 未完成 | 冰下水域/饥饿/重入 |
| 天空群岛 | PASS | 未完成 | 不适用待确认 | 未测 | 创建元数据 PASS | 未测 | 未完成 | 落下恢复/高空碰撞/重入 |
| 深渊世界 | PASS | 未完成 | 熔岩未测 | 未测 | 创建元数据 PASS | 未测 | 未完成 | 洞穴/岩浆/敌对遭遇/重入 |

基础旅程证据：`build/codex-fix-round7/profile-release-journey-report.json` 和同目录 6 张 PNG。它只证明真实主菜单入口，不能替代本表未完成列。

## 问题修复

| ID | 等级 | 根因 | 修复与验证 | 状态 |
|---|---|---|---|---|
| BUG-UI-002 | P1 | 纹理按钮仅检查 style 注册，无法证明内容区与文字的实际对比 | 对内容矩形逐像素计算 normal/hover/pressed/focus；深色像素面与白色文本，137/137 PASS | 待独立 QA-003 |
| BUG-SPAWN-001 | P1 | “树冠夹具”只是观察一个 procedural seed，未注入阻挡 | 内存 fixture 在 origin body column 注入 leaves，验证候选被拒绝，并验证旧存档有效位置不变；54/54 PASS | 待 3.7 实景碰撞 |
| BUG-OBS-001 | P1 | Working Set p95 索引越界且未采集 Private Bytes/原始样本 | 带超时的 PID sampler，JSON timestamps、WS/Private Bytes min/p50/p95/max；fresh smoke PASS | fixed |
| BUG-TEST-TRANSFORM-001 | P2 | 4 个回归在 Node3D 入树前读写 global_position | 移至入树后，四个 focused suites PASS | fixed |
| BUG-LEAK-001 | P1 | 全量 runner 仅记录而不失败，农业/收获相关退出仍保留对象 | 29 ObjectDB + 8 Resources 仍可复现；未掩盖 | open |

## 性能与稳定性

- fresh smoke：Working Set p95 **322.4 MiB**，Private Bytes p95 **375.2 MiB**，7 个 timestamped 样本，`build/codex-fix-round7/release-smoke-final/release-smoke.memory.json`。
- 此数据仅为约 6.4 秒 smoke，**不是**性能基线，也没有 FPS/1% low/CPU/GPU/VRAM 或 120 分钟趋势，因此发布性能门禁未通过。

## 自动化能力

- `tests/qa/profile_release_journey_regression.gd`：真实鼠标主菜单五 Profile 固定种子创建、运行态、保存元数据、返回、截图、JSON、world manifest、隔离清理。
- `tests/qa/ui_design_system_regression.gd`：纹理/平面按钮全状态有效对比度。
- `tests/qa/spawn_experience_regression.gd`：数据驱动 spawn matrix、真 canopy fixture 与旧档 recovery。
- `tests/release/run_windows_export_smoke.ps1`：fresh export、生命周期 smoke、外部内存原始证据及硬超时。

## 剩余风险与下一步

1. **泄漏**：全量日志 `build/codex-fix-round7/run-all.log` 显示 29 ObjectDB 和 8 Resource 泄漏。已尝试全量与 focused 运行；需 verbose 定位 core smoke/tool harvest/agriculture/irrigation 的所有者并修复。
2. **完整玩法**：五地图仅完成基础入口，尚未执行 OpenSpec 6.2--6.7、7.1--7.4。必须实测水、死亡、读档、边界/掉出、战斗和交互。
3. **性能**：尚无规定场景的对比采样与 120 分钟长稳，不能用短 smoke 推断稳定性。
4. **独立性**：BUG-UI-002 需同一独立 QA 按 QA-003 复测，开发自测不关闭问题。
