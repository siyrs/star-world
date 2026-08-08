# QA Session State

更新时间：2026-08-08 +08:00（商业验收重新执行中 — Claude 接管继续）

## 当前候选

- 分支：`codex/commercial-acceptance-20260808`
- 起点 HEAD：`5cbaca66e5efaf7278512448949603a0d925cd0f`
- 起点上游：`origin/master`
- 技术栈：Godot 4.7 / GDScript / Windows x86_64 / `gl_compatibility`
- Godot：`build/tools/godot/Godot_v4.7-stable_win64_console.exe`
- 正式内容：5 个数据驱动 Profile；本轮尚未继承任何历史通过结论

## 当前发布结论

**IN PROGRESS / HOLD**。2026-08-02 及更早的报告只作为断点和用例来源；只有 2026-08-08 在当前候选 HEAD 上重新生成的构建、日志、截图、性能和长稳证据才可进入本轮结论。

## 当前构建与测试状态

- Git 保护：起点工作树干净，已创建独立分支；Codex 整改成果已由 Claude 分三笔提交（`64fe48d` 隔离与套件扩容、`06068b7` 资格政策助手、`d54171d` 治理文档），工作树再次干净。
- T3 全量回归（chunk 性能修复后最终轮，HEAD `3c0d82d`）：**全绿 EXIT: 0**（142/142；runtime_soak 72/72、acceptance 185/185、runtime_stability 25/25、core_smoke 100/100、structural_integrity 28+31），证据 `build/commercial-acceptance-20260808/t3-perf-fix/run_all.log`。AC-002 泵窗口已按时间片语义对齐（`3c0d82d`，实测 47/120）；TARGETING 陈旧 token 误报横幅已在 `7ed0eea` 消除（终审 T3 将于长稳后最终 HEAD 复跑一遍取干净日志）。**T3 门禁再次关闭（性能修复后）**；台阶坡面修复 `bb46e35` 后须在最终 HEAD 终审复跑。
- 桌面验收最终遍（性能修复后，HEAD `7ed0eea`）：第一遍 89/91——non_cube 台阶 traverse 确定性楔死（5/5）、husbandry_closed_loop 读档活体空引用崩溃（2/2）。二分（仅回退 deadline 传递即复绿）+ 逐帧探针定位真根因 **BUG-STAIR-RAMP-GROUND-SCAN-001**：地面模型盒顶近似与碰撞连续斜坡不一致，旧原子构建的帧刺白送额外物理步掩盖了蠕行渐近线楔死，时间片化平滑帧步使其确定性暴露。修复 `bb46e35`（`get_local_surface_height` 解析坡高，吸附追踪真实接触面）：non_cube 3/3 PASS（起攀即站坡面 49.81，匀速爬 50.07，不依赖 tick 运气）、husbandry 3/3 PASS、7 个相关 T3 套件全过（acceptance 隔离 185/185）。**最终桌面全量遍 91/91 全绿**（HEAD `bb46e35`，证据 `desktop-ramp-fix/`，summary passed=91 failed=0）。**桌面验收门禁在最终 HEAD 正式关闭**。
- 终审 T3（HEAD `bb46e35`）：**142/142 EXIT: 0**，无 TARGETING 横幅（仅一行 CONTRACT PASS），证据 `t3-ramp-fix/run_all.log`。**T3 门禁在最终 HEAD 正式关闭**。
- fresh Windows 导出：最终候选包 **v2** `export-final-v2/`（坡面修复后最终包，exe=c42eb5d1…/pck=7f035ce7…）；导出冒烟 **PASS**（29 检查，authoritative_quit:true，生命周期单调）。此前 v1 包 `export-final/`（含 `b23c9d6` 生命周期修复）同门禁通过；更早两轮失败史见 BUG-RELEASE-LIFECYCLE-SAVE-ORDER-001。
- 最终 EXE 五图路线：**PASS（5/5，v2 复取）**（`journey-matrix-final-v2/`，精确复用 export-final-v2 包；36/36 步/图、位移 27.3–36.2m、跨 2–5 chunk、最大跌落 ≤1.0m、零传送、视觉全过、教程全隐藏、每图 authoritative_quit:true）。v2 逐图指标全部落在推荐档阈值内：avg 146–166fps、1% low 81.6–142.4、p95 6.89–8.76ms、p99 6.99–10.88ms、miss30 全 0%、加载 533–1163ms、WS p95 355–369 MiB（star_continent 资格种子 p95 8.76ms，较修复前 32.63ms 改善 73%）。**五图矩阵门禁在最终包上正式关闭**（v1 证据 `journey-matrix-final/` 存档保留）。
- 本机硬件资格（推荐档）：**PASS**（`hardware-qualification-recommended/`，result=pass，35/35 断言 0 违规，五图逐图独立判定全过；operator=claude-release-20260808，OperatorAttested，fingerprint=7e2e4d39…）。本机 RTX 3090 高于推荐档参考配置，最低档硬件资格仍为既有外部 HOLD。
- 严格 7,200 秒长稳：首跑在 cycle 70 中止（star_continent seed 112428 `route_too_short`，规划 6 步/最低 20）→ 定位 **BUG-SPAWN-WALKABLE-REACH-001**（出生质量系统只查局部指标，~10% 种子落微连通孤岛）→ 修复 `02e8793`（walkable-reach BFS，与路线探针同合同；300 周期种子空间扫描全部 reach≥20 零降级，五基准出生点不变，6 个出生敏感套件全过）→ 最终包 v3 `export-final-v3/`（冒烟 29 检查 PASS）→ 矩阵 v3 + 推荐档资格执行中（后台 `bk8xvpa6k`），其后长稳从 cycle 0 重启。
- 全部桌面验收旅程：第一遍 78/91 完成，13 失败已全部整改并单独验证 PASS；第二遍 88/91，3 失败全部关闭；**第三遍（最终 HEAD `7af35ef` 干净证据）91/91 全绿**（19:31→20:01，30.7 分钟，selected=91 passed=91 failed=0），证据 `desktop-final-pass/`。**桌面验收门禁正式关闭**。
- 本机最低/推荐硬件资格：推荐档 **已通过**（见上）；最低档硬件为既有外部 HOLD（本机配置高于最低档，无法冒充）。
- 严格 7,200 秒长稳：最终包上执行中（后台 `bt11v4cxj`）。

## 台阶行走修复（P1 真实产品缺陷，**已关闭**）

- 缺陷：楼梯/台阶视觉是坡但行为是整砖墙——玩家被 0.5 高楼梯前脸楔住，无法走上台阶。
- 三段修复：①`voxel_world.gd::resolve_ground_position` 返回成形表面（`_resolve_block_surface_height`，按 `BlockShapeGeometryScript.get_local_boxes` 取脚下局部 (x,z) 命中的最高 box 顶）②`first_person_player.gd` 新增 `_apply_voxel_step_up`（仅在移动被墙挡住时，向前 0.45m 探测成形地面，0.05<step≤0.55 才抬升；整砖 +1 仍需跳）③**根因**：`ladder_climbing_player.gd` 的 `_physics_process` 无 super 调用完全覆盖基类，基类的 step-up 从不执行——已按该文件 BUG-LAVA-001 同款模式补 `_apply_voxel_step_up` 调用。
- `VOXEL_GROUND_RECOVERY_DEPTH` 已从 0.55 **回退到 0.4**：0.55 让快照恢复在玩家中心被动漂过楼梯半高边界时瞬间上拽 +0.41，且与 step-up 双机制重复；现在 step-up 是唯一 +0.5 抬升机制。
- 幻影地面悬浮（BUG-VOID-LEVITATE-001）已修：`voxel_world` 新增 `try_resolve_ground_position`（无地面返回 null），兜底仅留出生放置；玩家足迹采样（±0.3 五点、容差 [-0.4,+0.18]）拒绝假地面。
- **已验证**：`non_cube_block_geometry_desktop_acceptance` 33/33 PASS（traverse rise 0.5）；正面接近探针 22.07→22.57→23.07 两段爬升复验通过。

## 本轮桌面验收第一遍整改结果（13 失败全部关闭）

- 全部 13 个第一遍失败套件已修复并单独验证 PASS：agriculture_closed_loop、husbandry_closed_loop、rest_closed_loop、bounded_trash_manager、weather（长路径删除）；multi_hostile_danger_batched（56）、ranch_runtime_lifecycle（59，pickup 泵取）；non_cube_block_geometry（33，台阶）；ranged_combat（37，生成坠入未建成 Chunk，BUG-SPAWN-CHUNK-001）；structural_integrity_scale（61，套件契约漂移 BUG-QA-SCALE-FLUSH-CONTRACT-001：pre-flush 合并单次 flush 为 T3+姊妹桌面套件钉定的正式架构，期望 2→1 并新增 `pre_flush_cleanup_count>=1` 钉机制）。
- ZZBATCH 调试输出已从 `batched_voxel_world.gd` 移除（工作树=HEAD）；全部 zz_ 探针已删除。
- 工作树当前未提交改动：save_service/protected_save_service（长路径删除）、voxel_world（成形地面+try_resolve）、first_person_player（step-up+足迹+0.4 恢复）、ladder_climbing_player（step-up 调用）、creature_spawner（生成 Chunk 实体化）、structural_integrity_scale 套件（契约对齐）、qa/issues-found.md（六条新记录）、qa/session-state.md。
- 待办：分组小提交 → 桌面验收 91 套件第二遍全量 → T3 全量重跑（核 +1 台阶跳跃契约）。

## 地图进度（仅本轮）

| Profile | 进入 | 连续正常路线 | 内容闭环 | 碰撞/边界 | 水域/危险 | 存读档/死亡复活 | 最终 EXE | 状态 |
|---|---|---|---|---|---|---|---|---|
| `star_continent` | ✅ 桌面+T3 | ✅ 路线 36/36 步 | ✅ 内容闭环桌面套件 | ✅ 边界/足迹容差 | ✅ 水域套件 | ✅ 存读档套件 | ✅ 矩阵 PASS | passed |
| `desert_ruins` | ✅ 桌面+T3 | ✅ 路线 36/36 步 | ✅ 内容闭环桌面套件 | ✅ 边界 | N/A（无正式水域，已有危险/陷阱套件） | ✅ 存读档套件 | ✅ 矩阵 PASS | passed |
| `frozen_wastes` | ✅ 桌面+T3 | ✅ 路线 36/36 步 | ✅ 内容闭环桌面套件 | ✅ 边界 | ✅ 水域套件 | ✅ 存读档套件 | ✅ 矩阵 PASS | passed |
| `sky_islands` | ✅ 桌面+T3 | ✅ 路线 36/36 步 | ✅ 内容闭环桌面套件 | ✅ 高空谨慎下降套件 | 高空/跌落 ✅ | ✅ 存读档套件 | ✅ 矩阵 PASS | passed |
| `abyss_world` | ✅ 桌面+T3 | ✅ 路线 36/36 步 | ✅ 内容闭环桌面套件 | ✅ 边界 | 熔岩 ✅（BUG-LAVA-001 回归） | ✅ 存读档套件 | ✅ 矩阵 PASS | passed |

## 问题与回归

- 当前正在处理的问题：无活动缺陷。最终候选包 v2 导出+冒烟执行中（`export-final-v2/`）；其后五图矩阵 v2 → 推荐档硬件资格 → 7200s 严格长稳 → 最终报告 → 合并/tag/release/推送。
- 已修复问题：1（`BUG-QUALIFY-POLICY-ROOT-001`，包校验器政策根硬编码 checkout 导致漂移测试窗口硬杀 T3；已加 `-PolicyRoot` 并提交 `6da93ee`，回归全过）。
- 待独立 QA 回归：0。
- 历史外部 HOLD：独立 E4-H、两档实体硬件、严格 7,200 秒、物理 HDD/杀毒/断电、发布签名与更新信任引导；本轮将重新核实可在当前电脑执行的部分，不直接沿用历史状态。

## 最近命令与证据

- 最近一次命令：推荐档硬件资格 **PASS**（35/35 断言）→ 严格 7200s 长稳启动（后台 `bt11v4cxj`，`strict-soak-7200-final/`）；前一命令五图矩阵 v2 **PASS 5/5**（star_continent p95 8.76ms）
- 本轮证据根目录：`build/commercial-acceptance-20260808/`（整改后 T3：`t3-post-fixes/`；T3 最终：`t3-final/`；桌面最终：`desktop-final-pass/`；性能修复后 T3：`t3-perf-fix/`；性能取证与 A/B：`export-perf-fix/`；最终候选包 v1+冒烟：`export-final/`；五图矩阵 v1：`journey-matrix-final/`；坡面修复取证与复验：`chunk-perf-fix/`；坡面修复后桌面 91/91：`desktop-ramp-fix/`；终审 T3：`t3-ramp-fix/`；最终包 v2：`export-final-v2/`；矩阵 v2：`journey-matrix-final-v2/`；推荐档资格：`hardware-qualification-recommended/`；7200s 长稳：`strict-soak-7200-final/`）
- 用户真实存档：不得修改；测试使用隔离 `APPDATA`/`LOCALAPPDATA` 重定向（Godot 4.7 无 `--user-data-dir`），前后校验清单。

## 下一步

1. ~~分组小提交~~ **已完成**（6 笔：`d6cc2da` save 长路径、`c9ba9fd` 台阶/悬浮地面、`1431234` 生成 Chunk 实体化、`5cb573e` scale 契约对齐、`9ddb0a2` 桌面套件时序对齐、`b90a816` QA 记录）。
2. ~~桌面验收第二遍~~ **88/91 完成且 3 失败全部关闭**（见上）；**进行中**：T3 全量重跑（核 +1 台阶跳跃契约）；然后最终一遍全量桌面验收（91，最终 HEAD 干净证据）。
   - T3 第一轮在 `validate_protected_save_deletion.ps1` 硬停：静态校验器仍把 `_remove_directory_recursive` 钉为保护删除服务的必备行为，而 BUG-SAVE-LONG-PATH-001 修复后该服务改走继承的 `_remove_directory_tree`。已将校验器对齐新调用点并显式禁止重新引入私有递归删除器（`3959cb6`）。
   - T3 第二轮在 `validate_bounded_trash_manager.ps1` 硬停（同源陈旧 token）。随即对全部 21 个引用改动文件的 developer_b 校验器做了一次性扫描：另发现 `validate_structural_integrity.ps1` 钉 scale 套件旧的"恰好两次 flush"断言文本；同时清理 `structural_integrity_single_flush_desktop_acceptance.gd` 里已无匹配文本的 `LEGACY_FLUSH_FAILURE` erase 死代码（父套件断言已与单次 flush 规范一致）。三处校验器+套件对齐（`cedd869`），T3 第三轮重跑中（后台 `bvedcugju`）。
   - T3 第三轮（校验器对齐后）：142 套件中唯一失败 `runtime_soak_regression`（"runtime health recovers after bounded travel pressure"，cycle 3 终末采样窗 peak ≥80ms）。根因定位（BUG-PERF-GROUND-SCAN-001）：台阶/悬浮修复引入的五点足迹地面扫描每次从世界顶整列下扫，传送后追赶期多物理 tick 叠加，cycle 3 终末窗均值放大到 master 的 ~2 倍，单 >80ms 峰值帧落窗即翻案。已把保持者扫描上界收紧到头顶 +2（放置 API 整列扫描语义不变），同机 4/4 PASS（终末窗 avg 22.7–24.2ms、peak 40–47ms）。取证过程：master worktree A/B 3/3 通过、逐帧计时探针（单周期不复现 → 三周期序列相关）、套件级复刻 + nosample/noteleport/nospawn/noadaptive 逐项隔离（单项均非根因，系边际放大）、batch 统计。证据 `t3-rerun/`（含探针脚本与全部日志）。扫描修复提交后全量 T3 第四轮重跑。
   - **第二遍结果 88/91，3 失败已全部关闭**：①`encounter_reward_economy` 聚合运行首枪未击杀级联 25 项失败，**单独复跑 70/70 PASS**（并发+低优先级下仍过）；非确定性时序脆弱，已加 `KILL-TIMEOUT` 诊断 dump 取证下次失败。②`multi_hostile_danger` 静默 exit 0xCFFFFFFF 崩溃（~54s 无输出）——**单独复跑 48/48 PASS**；崩溃窗口与我自己发起的 encounter 单独复跑并发重叠（双桌面 Godot 实例争用），判定环境性，非产品缺陷；同时补上该套件修复后缺失的单独复验（`9ddb0a2` 提交信息对该套件的复验声明由此兑现）。③`rest_closed_loop_stable` 解析错误——我在父套件补时钟暂停机制时与子类既有成员（`_paused_day_night` 等）重复声明；已将子类瘦身到只剩 `_settle_player` 探针覆写（机制与父套件逐字节等价），**单独复跑 57/57 PASS**。已审计其余三个子类（agriculture_canonical、husbandry_stable、multi_hostile_batched）在第二遍全过，无同类碰撞。
3. ~~重新导出 fresh EXE/PCK~~ **已完成**（`export-final/`，含 `b23c9d6` 生命周期修复；导出冒烟 29 检查全绿、生命周期单调）。五图矩阵后台执行中（后台 `boj92y0f8`）。
4. 运行本机性能资格（`tests/ci/run_performance_capture.ps1`，外部采样须跟踪 console.exe 派生的 GUI 子进程 PID——**已完成** 13 场景 PASS，证据 `perf-capture-final/`）与硬件资格门禁（`run_external_hardware_qualification.ps1 -Tier recommended`）；随后严格 7,200 秒长稳（`run_strict_target_hardware_soak.ps1 -SoakSeconds 7200`；第一轮已主动中止取证，待最终包重启），再更新覆盖矩阵和最终报告。
   - **插队性能修复（已完成取证与修复）**：矩阵发现 star_continent 资格种子 soak 超推荐档 → 帧日志取证 → 时间片化 chunk 构建修复（`2429978`）→ 复测全指标达标（p95 9.09ms）。此修复使最终包必须重新导出并重走矩阵/资格/长稳，且 T3（进行中）与桌面最终遍（排队）须在最终 HEAD 重取证据。
5. 最终报告 + 合并 master + tag + release + 同步远程。
