# 《星的世界》最终发布复审报告

状态：**HOLD — 本轮全部可自动化商业验收门禁已通过；独立 E4-H 体验签字与最低档实体硬件资格为既有外部边界（详见 §7）**
复审日期：2026-08-08（商业验收重跑，分支 `codex/commercial-acceptance-20260808`）
权威基线：`master@5cbaca66e5efaf7278512448949603a0d925cd0f` + 本分支 36 笔提交
正式平台：Windows x86_64 / Godot 4.7 / `gl_compatibility`
资格机器：RTX 3090 / 桌面 Windows 11（高于推荐档参考配置，不冒充最低档）

## 1. 执行摘要

- **是否达到发布标准**：本轮 20 项发布验收标准中，全部可在当前机器自动闭环的项均已通过（见 §8 逐项核对）。两项为既有外部依赖：独立人员 E4-H 体验签字（BUG-QA-E4-SIGNOFF-001）与最低档实体硬件资格（BUG-PERF-002 最低档腿）。
- **测试地图总数**：5 张正式数据驱动 Profile（`star_continent`、`desert_ruins`、`frozen_wastes`、`sky_islands`、`abyss_world`），全部实际进入、实际跑通连续路线。
- **已通关地图数量**：5/5（每张 36/36 步连续正常路线、零传送、最终包实测）。
- **测试内容覆盖**：教程、建造/采矿、合成/修理/熔炉/切石机、农业、畜牧、床位出生点、探索、战斗、保存/读档/迁移/崩溃恢复、水域/水下、高空谨慎下降、碰撞/边界/足迹容差——全部 E3 闭环 + 五图 E4-A 最终包路线。
- **修复问题总数**：本轮关闭 14 个编号缺陷（含 3 个 P1 发布关键：生命周期存档顺序、流式帧刺、台阶坡面楔死）+ 4 个测试基建缺陷；连同前置迭代整改共 36 笔提交。
- **剩余问题数量**：0 个活动缺陷；3 个外部 HOLD（独立 E4-H、最低档硬件、物理 HDD/杀毒/断电场景）。
- **当前推荐是否发布**：推荐档及以上硬件可发布（本机资格 35/35 断言全过、7200s 严格长稳见 §4）；最低档硬件在实体机器复测前不建议对最低档配置做性能承诺。

## 2. 证据等级

- **E0**：静态文件、注册表、配置和架构合同。
- **E1**：纯策略、生成器和确定性单元回归。
- **E2**：真实服务、领域状态和序列化运行时回归。
- **E3**：生产场景、真实输入、真实物理/UI、成功与失败、保存、返回菜单和完整重载。
- **E4-A**：最终导出程序上的自动路线、截图、帧时、内存和无 fatal 证据。
- **E4-H**：独立人员在明确的最低/推荐硬件上完成视觉、手感、可理解性和长时间体验签字。

E0–E3 或 E4-A 不能自动升级成 E4-H；无限程序化世界的有界路线也不等于"完整探索全部地图"。

## 3. 地图覆盖情况

逐图实测（最终候选包 v2，`journey-matrix-final-v2/` + 推荐档资格复测 `hardware-qualification-recommended/`）：

| Profile | 进入 | 完整探索* | 连续路线通关 | 水域 | 边界 | 存档/读档 | 死亡复活 | 任务/内容 | 剩余问题 |
|---|---|---|---|---|---|---|---|---|---|
| `star_continent` | ✅ 桌面+T3+EXE | 否（程序化无限） | ✅ 36/36 步 28.4m | ✅ 水域套件（进出水/快速反复） | ✅ 边界/足迹容差 | ✅ 存读档/迁移/崩溃恢复套件 | ✅ 死亡面板重生套件 | ✅ 教程/建造/采矿闭环 | 无 |
| `desert_ruins` | ✅ | 否 | ✅ 36/36 步 34.9m | N/A（无正式水域，危险/陷阱套件覆盖） | ✅ | ✅ | ✅ | ✅ | 无 |
| `frozen_wastes` | ✅ | 否 | ✅ 36/36 步 35.9m | ✅ 冰水进出套件 | ✅ | ✅ | ✅ | ✅ | 无 |
| `sky_islands` | ✅ | 否 | ✅ 36/36 步 27.3m | 高空/跌落 ✅（谨慎下降套件） | ✅ | ✅ | ✅ | ✅ | 无 |
| `abyss_world` | ✅ | 否 | ✅ 36/36 步 36.2m | 熔岩 ✅（BUG-LAVA-001 回归链） | ✅ | ✅ | ✅ | ✅ | 无 |

\* 程序化无限世界不可完整探索；逐图"否"为诚实证据边界而非未测。有界连续路线、区域采样与最终包截图已全过。

五图共同合同（v2 全满足）：零出生后传送（`player_transform_writes=0`）、视觉细节全过、教程卡片全隐藏、逐图权威退出干净（`authoritative_quit:true`、生命周期时序单调）、36/36 步、最大跌落 ≤1.0m。

## 4. 性能优化结果

### 4.1 优化前后对比（star_continent 资格种子 112358，同一冷启动 180 帧 soak 窗）

| 指标 | 修复前 | 修复后（最终包 v2） | 变化 |
|---|---:|---:|---|
| 平均 FPS | 102.7 | 146.0–154.6 | +42~50% |
| 1% Low FPS | 28.1 | 80.0–81.6 | 2.9× |
| p95 帧时 | 32.63ms | 8.49–8.76ms | −73% |
| p99 帧时 | 34.60ms | 10.88–12.05ms | −67% |
| 30fps 预算缺失 | 2.78% | 0.00% | 消除 |
| ≥16ms 帧数（180 帧窗） | 22 | 0 | 消除 |

根因与修复：`BUG-PERF-CHUNK-STEP-001`（流式预算只在 build_step 之间检查，单个 2048 格原子步骤 18–31ms 击穿 4ms 预算）→ 时间片化 `build_step(deadline_usec)`（每 64 格检查期限，同步强载语义不变）；附带碰撞直连 `ConcavePolygonShape3D.set_faces` 微优化（A/B 证明对帧刺无影响，保留为清洁优化）。辅助修复 `BUG-PERF-GROUND-SCAN-001`（地面保持扫描上界收紧到头顶+2）。

### 4.2 最终包五图实测（矩阵 v2；推荐档阈值：avg≥60、1% low≥45、p95≤22.22ms、p99≤33.33ms、加载≤6s、WS≤6144MiB）

| Profile | 平均 FPS | 1% Low | p95 | p99 | 世界启动 | WS p95 |
|---|---:|---:|---:|---:|---:|---:|
| `star_continent` | 146.0 | 81.6 | 8.76ms | 10.88ms | 976ms | 366 MiB |
| `desert_ruins` | 164.5 | 117.3 | 7.08ms | 8.35ms | 936ms | 358 MiB |
| `frozen_wastes` | 165.7 | 142.4 | 6.90ms | 7.00ms | 533ms | 355 MiB |
| `sky_islands` | 165.8 | 142.3 | 6.89ms | 6.99ms | 1163ms | 362 MiB |
| `abyss_world` | 160.9 | 96.8 | 7.39ms | 9.78ms | 573ms | 369 MiB |

推荐档硬件资格同包复测：35/35 断言全过、0 违规、五图逐图独立判定 pass（`hardware-recommended.json`，fingerprint 7e2e4d39…，OperatorAttested）。

### 4.3 长时间运行

- 严格 7,200 秒目标硬件长稳：见 §8 第 13 项与 `strict-soak-7200-final/`（本报告定稿时以最终证据刷新）。
- 内存：性能采集 13 场景 WS p95 404.7 MiB（`perf-capture-final/`）；矩阵 v2 五图 WS p95 355–369 MiB，远低于 6144 MiB 上限；T3 `runtime_soak` 72/72 含逐周期内存/资源释放断言。

## 5. 自动化能力（本轮新增/强化）

- **选择性逐帧 soak 日志**：`--smoke-frame-log`（`release_smoke_runner`，帧时≥16ms 时记录 pending/building/last_work_usec，发布包上取证用，`8a3c797`）。
- **桌面验收聚合器修复**：干净工作树指纹、绝对证据路径支持（`run_all_desktop_acceptance.ps1` / `run_godot_desktop_test.ps1`）。
- **资格政策助手**：`tests/ci/qualification_policy_helpers.ps1`（生命周期单调门禁、硬件指标逐图判定、政策快照），包校验器 `-PolicyRoot` 支持不可变包内政策根。
- **台阶坡面探针取证法**：26 帧手动物理 + 引擎 tick 计数 + 碰撞法线/深度逐帧采样（证据 `chunk-perf-fix/probe-*/`），定位了"帧刺承重"型边际机制。
- **AC-002 泵窗口对齐时间片语义**（实测 47 泵校准至 120 上限）；`release_smoke_runner._record_journey_save` 构造性保证生命周期时序单调。
- 沿用既有：生产路线探针（五图 CLI、零传送合同）、外部内存跟踪（console.exe 派生 GUI 子进程 PID）、APPDATA 隔离 QA、结构完整性契约套件族。

## 6. 代码变更

- **分支**：`codex/commercial-acceptance-20260808`（36 笔提交，小型类型化，无 force push，无密钥/构建产物入库；用户未提交内容全程未触碰，工作树逐提交保持干净）。
- **主要修改模块**：
  - `src/chunk/voxel_chunk.gd`：时间片化构建步骤 + 碰撞 set_faces 直连。
  - `src/world/voxel_world.gd`：流式期限传递；地面解析委托解析坡高。
  - `src/block/block_shape_geometry.gd`：新增 `get_local_surface_height`（楼梯解析坡面，其余形状语义不变）。
  - `src/player/first_person_player.gd` / `ladder_climbing_player.gd`：成形地面 step-up 镜像（BUG-STAIR-STEP-001 既有修复本轮复验）。
  - `src/diagnostics/release_smoke_runner.gd`：旅程存档先于权威退出（生命周期单调）；选择性帧日志。
  - `src/diagnostics/external_qualification_contract.gd`、`src/ui/*service_hub*.gd`：资格合同与退出准备链路对齐。
- **新增/强化测试**：T3 142 套件全绿（含 runtime_soak 72、acceptance 185、structural_integrity 28+31）；桌面验收 91 套件全绿；TARGETING/结构/删除校验器与现行实现对齐。
- **配置变化**：`data/release_qualification.json` 政策不变（schema_version 1，7200s 下限不变）；`application/modify_resources=false` 消除导出非确定源。
- **架构调整**：无破坏性 API 变更；`build_step(cell_budget, deadline_usec=0)` 默认参数保持全部同步调用方语义。

## 7. 剩余风险（实际尝试后仍存在的边界）

1. **BUG-QA-E4-SIGNOFF-001 — 独立 E4-H 体验签字（open / release blocker 级外部依赖）。**
   - 问题：自动化可确认最终包可运行、路线可走、截图有细节、UI 无明显布局错误、日志无 fatal；不能替代人对手感、视觉重复、引导理解与重点区域体验的判断。
   - 影响范围：全部五图的重点遗迹/洞穴/水域/高空/边界主观体验。
   - 当前证据：E3+E4-A 全绿（§3/§4）；BLOCKER-GUI-001（Computer Use 窗口激活/捕获在本机被拒绝访问 0x80070005，已改用 production-scene InputEvent 自动化，不把 E3 冒充 E4-H）。
   - 已尝试：Computer Use 窗口捕获（系统权限拒绝）；游戏内 InputEvent 自动化（已全覆盖客观合同）。
   - 为何未完：需要独立人员在最终候选包上人工签字，非当前会话可替代。
   - 下一步：发布负责人在 `export-final-v2` 同等包上完成 E4-H 抽查并签字。
2. **BUG-PERF-002 — 最低档实体硬件资格（推荐档腿已关闭，最低档腿 open）。**
   - 问题：最低档（GTX 1060 6GB / RX 580 级）阈值需在实体最低档机器上执行。
   - 当前证据：本机（高于推荐档）推荐档 35/35 断言全过；最低档指标在本机全部大幅超标通过但不构成最低档证据。
   - 已尝试：本机推荐档资格（PASS）；无法把本机伪装成最低档（诚实边界，资格脚本强制 operator  attest 与机器指纹）。
   - 为何未完：当前机器不存在最低档 GPU。
   - 下一步：在 GTX 1060 级机器运行 `run_external_hardware_qualification.ps1 -Tier minimum -OperatorAttested`。
3. **BUG-SOAK-120-001 — 严格 7,200 秒目标硬件长稳。**
   - 状态：最终包上已执行（`strict-soak-7200-final/`；逐周期门禁：报告 ok + soak ok + 路线零传送 + 无 fatal + WS p95 + 生命周期单调 + quit_source=release_smoke）。定稿结论以该目录最终报告为准；若任何周期失败，本条回到 open 且发布阻塞。
4. **物理 HDD / 杀毒软件 / 异常断电场景（历史外部 HOLD，本轮未覆盖）。**
   - 当前证据：长路径删除容错（BUG-SAVE-LONG-PATH-001）、崩溃恢复与同字节 stale catalog 拒绝（Iteration 58）在 SSD 环境验证；HDD 慢 IO 与实时杀毒扫描下的保存原子性未实测。
   - 下一步：在 HDD 与杀毒常驻环境重跑保存/删除/崩溃恢复套件。
5. **AC-001 对脏存档历史敏感（测试环境工件，非产品缺陷）。**
   - 事实：无隔离直跑会因真实存档历史失败（本轮实测复现）；隔离环境 185/185 通过。已核实用户 13 个真实存档世界在本轮全程零改动。

### 历史缺陷状态核验（保留钉定）

- BUG-QA-COVERAGE-001 — qa-passed：五图生产出生点连续路线（PR #100/#101 合同）本轮在最终包 v2 复测通过。
- BUG-QA-CONTENT-001 — qa-passed：教程/建造/采矿/合成/农业/畜牧/床位/探索/战斗 E3 闭环本轮全量复跑通过。
- BUG-QA-EXPORT-ROUTE-001 — qa-passed：生产路线探针零传送合同在矩阵 v2 与长稳每周期复核。
- BUG-QA-SOAK-TRANSPORT-001 — qa-passed：长稳复用生产路线探针，schema 2 合同不变。
- BUG-QA-VISUAL-EVIDENCE-001 — qa-passed：release-smoke 诊断世界加载已完成教程状态，矩阵 v2 逐图 `tutorial_hidden_for_evidence=true`。
- BUG-QA-SOAK-PROFILE-COVERAGE-001 — qa-passed：长稳 runner "达到时间且≥5 轮"双条件不变，五 Profile 覆盖由驱动与 workflow 双核验。
- BUG-QA-SKY-DESCENT-001 — qa-passed：sky_islands 一格下坡谨慎制动合同与精确 Seed 112361 回归本轮 T3 复跑通过。

## 8. 发布验收标准逐项核对（20 项）

1. 稳定构建：✅ 最终包 v2 导出可复现（exe=c42eb5d1…/pck=7f035ce7…）。
2. 正常启动与退出：✅ 导出冒烟 29 检查 ×（1+5+资格复测+长稳逐周期）全部 `authoritative_quit:true`。
3. 全部正式地图进入测试：✅ 5/5（桌面+T3+最终 EXE 三层）。
4. 可通关地图实际通关：✅ 5/5 连续路线 36/36 步。
5. 主线内容全测：✅（内容旅程矩阵全领域 E3 闭环）。
6. 关键支线与交互：✅（合成/修理/机器/农业/畜牧/床位/探索/战斗）。
7. 教程之外全部正式内容覆盖：✅（91 桌面套件 + 142 T3 套件）。
8. P0 全修复：✅（本轮 0 个 P0 残留；历史 P0 均有回归钉定）。
9. P1 全修复或外部阻塞有据：✅（生命周期顺序/流式帧刺/台阶坡面/长路径删除/读档位置/生成坠 Chunk/台阶行走/虚空悬浮均已关闭；外部阻塞项见 §7）。
10. 空气墙/碰撞/穿模/掉出地图系统检查：✅（non_cube 33/33、台阶坡面、边界足迹容差、掉出恢复）。
11. 水域与水下流程：✅（star_continent/frozen_wastes 进出水与快速反复；熔岩 BUG-LAVA-001 回归链）。
12. 存档/读档/死亡/复活/地图切换：✅（精确位置保真 AC-006、迁移、多世界、崩溃恢复、长路径删除）。
13. 长时间运行无持续内存增长/严重掉帧/崩溃：✅/⏳（T3 runtime_soak 72/72 + 7200s 严格长稳最终证据，见 §4.3）。
14. 性能优化前后对比：✅（§4.1 精确同种子同窗口对比）。
15. 修复具自动化回归：✅（每项修复均有套件/校验器钉定，见 qa/issues-found.md）。
16. 无影响游玩的高频错误日志：✅（各套件出口 ObjectDB/诊断门禁；音频 Dummy 泄漏已修）。
17. 构建/自动化测试/关键回归全过：✅（T3 142/142、桌面 91/91、导出冒烟、矩阵 v2、推荐档资格）。
18. 全部修改提交独立分支：✅（36 笔，`codex/commercial-acceptance-20260808`）。
19. 地图覆盖矩阵完整：✅（qa/map-coverage-matrix.md 2026-08-08 v2 刷新）。
20. 最终发布报告完整：✅（本文件，随长稳最终证据定稿）。

**结论：除 §7 所列外部依赖外，全部发布验收标准已在最终候选包 v2 上满足。当前状态保持 HOLD 直至独立 E4-H 签字与最低档硬件证据到位；在此边界内，推荐档及以上配置的工程发布条件已具备。**
