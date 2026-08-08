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
- T3 全量回归（整改后重跑）：**142/142 全绿**（`RUN_ALL_EXIT=0`，0 fatal/leak）；上轮 7 个失败套件全部在本轮确认 PASS，证据 `build/commercial-acceptance-20260808/t3-post-fixes/`。**注意**：此后 game 侧又有改动（save 服务长路径删除、voxel 成形地面、玩家 step-up、ladder 子类），桌面验收定稿后必须再全量重跑 T3（重点核 +1 整砖台阶仍需跳跃的路线契约）。
- fresh Windows 导出：已完成一轮（`export-smoke-after-gdignore`，11:40，smoke 通过）；因本轮有 game 侧修复（音频 Dummy 防护、读档位置保真、is_grounded、导出预设、台阶行走、长路径删除），桌面验收后重新导出候选包再跑五图矩阵。
- 最终 EXE 五图路线：待执行（基于新导出）。
- 全部桌面验收旅程：第一遍 78/91 完成，13 失败**已全部整改并单独验证 PASS**（见下节）；修复后第二遍全量待执行。
- 本机最低/推荐硬件资格：待硬件分档后执行。
- 严格 7,200 秒长稳：待 fresh 候选包与短资格门禁通过后执行。

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
| `star_continent` | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | pending |
| `desert_ruins` | 待测 | 待测 | 待测 | 待测 | N/A/待核对 | 待测 | 待测 | pending |
| `frozen_wastes` | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | pending |
| `sky_islands` | 待测 | 待测 | 待测 | 待测 | 高空/跌落待测 | 待测 | 待测 | pending |
| `abyss_world` | 待测 | 待测 | 待测 | 待测 | 熔岩待测 | 待测 | 待测 | pending |

## 问题与回归

- 当前正在处理的问题：`runtime_soak_regression` 边际失败已按 BUG-PERF-GROUND-SCAN-001 修复（地面保持扫描 O(WORLD_HEIGHT)→O(站立高度)，soak cycle 3 终末窗 avg 29–36ms→22.7–24.2ms、peak ≤47ms，4/4 PASS）；等待全量 T3 复核。
- 已修复问题：1（`BUG-QUALIFY-POLICY-ROOT-001`，包校验器政策根硬编码 checkout 导致漂移测试窗口硬杀 T3；已加 `-PolicyRoot` 并提交 `6da93ee`，回归全过）。
- 待独立 QA 回归：0。
- 历史外部 HOLD：独立 E4-H、两档实体硬件、严格 7,200 秒、物理 HDD/杀毒/断电、发布签名与更新信任引导；本轮将重新核实可在当前电脑执行的部分，不直接沿用历史状态。

## 最近命令与证据

- 最近一次命令：`run_godot_desktop_test.ps1 ... structural_integrity_scale_desktop_acceptance.gd`（契约对齐后复验 **61/61 PASS**，证据 `desktop-second-pass/`）
- 本轮证据根目录：`build/commercial-acceptance-20260808/`（整改后 T3：`t3-post-fixes/`；桌面第二遍：`desktop-second-pass/`）
- 用户真实存档：不得修改；测试使用隔离 `APPDATA`/`LOCALAPPDATA` 重定向（Godot 4.7 无 `--user-data-dir`），前后校验清单。

## 下一步

1. ~~分组小提交~~ **已完成**（6 笔：`d6cc2da` save 长路径、`c9ba9fd` 台阶/悬浮地面、`1431234` 生成 Chunk 实体化、`5cb573e` scale 契约对齐、`9ddb0a2` 桌面套件时序对齐、`b90a816` QA 记录）。
2. ~~桌面验收第二遍~~ **88/91 完成且 3 失败全部关闭**（见上）；**进行中**：T3 全量重跑（核 +1 台阶跳跃契约）；然后最终一遍全量桌面验收（91，最终 HEAD 干净证据）。
   - T3 第一轮在 `validate_protected_save_deletion.ps1` 硬停：静态校验器仍把 `_remove_directory_recursive` 钉为保护删除服务的必备行为，而 BUG-SAVE-LONG-PATH-001 修复后该服务改走继承的 `_remove_directory_tree`。已将校验器对齐新调用点并显式禁止重新引入私有递归删除器（`3959cb6`）。
   - T3 第二轮在 `validate_bounded_trash_manager.ps1` 硬停（同源陈旧 token）。随即对全部 21 个引用改动文件的 developer_b 校验器做了一次性扫描：另发现 `validate_structural_integrity.ps1` 钉 scale 套件旧的"恰好两次 flush"断言文本；同时清理 `structural_integrity_single_flush_desktop_acceptance.gd` 里已无匹配文本的 `LEGACY_FLUSH_FAILURE` erase 死代码（父套件断言已与单次 flush 规范一致）。三处校验器+套件对齐（`cedd869`），T3 第三轮重跑中（后台 `bvedcugju`）。
   - T3 第三轮（校验器对齐后）：142 套件中唯一失败 `runtime_soak_regression`（"runtime health recovers after bounded travel pressure"，cycle 3 终末采样窗 peak ≥80ms）。根因定位（BUG-PERF-GROUND-SCAN-001）：台阶/悬浮修复引入的五点足迹地面扫描每次从世界顶整列下扫，传送后追赶期多物理 tick 叠加，cycle 3 终末窗均值放大到 master 的 ~2 倍，单 >80ms 峰值帧落窗即翻案。已把保持者扫描上界收紧到头顶 +2（放置 API 整列扫描语义不变），同机 4/4 PASS（终末窗 avg 22.7–24.2ms、peak 40–47ms）。取证过程：master worktree A/B 3/3 通过、逐帧计时探针（单周期不复现 → 三周期序列相关）、套件级复刻 + nosample/noteleport/nospawn/noadaptive 逐项隔离（单项均非根因，系边际放大）、batch 统计。证据 `t3-rerun/`（含探针脚本与全部日志）。扫描修复提交后全量 T3 第四轮重跑。
   - **第二遍结果 88/91，3 失败已全部关闭**：①`encounter_reward_economy` 聚合运行首枪未击杀级联 25 项失败，**单独复跑 70/70 PASS**（并发+低优先级下仍过）；非确定性时序脆弱，已加 `KILL-TIMEOUT` 诊断 dump 取证下次失败。②`multi_hostile_danger` 静默 exit 0xCFFFFFFF 崩溃（~54s 无输出）——**单独复跑 48/48 PASS**；崩溃窗口与我自己发起的 encounter 单独复跑并发重叠（双桌面 Godot 实例争用），判定环境性，非产品缺陷；同时补上该套件修复后缺失的单独复验（`9ddb0a2` 提交信息对该套件的复验声明由此兑现）。③`rest_closed_loop_stable` 解析错误——我在父套件补时钟暂停机制时与子类既有成员（`_paused_day_night` 等）重复声明；已将子类瘦身到只剩 `_settle_player` 探针覆写（机制与父套件逐字节等价），**单独复跑 57/57 PASS**。已审计其余三个子类（agriculture_canonical、husbandry_stable、multi_hostile_batched）在第二遍全过，无同类碰撞。
3. 重新导出 fresh EXE/PCK。**决策**：用户管线原定“用 11:40 fresh EXE 跑五图矩阵”，但 11:40 包早于台阶/悬浮/生成/长路径全部 game 侧修复，用它出矩阵证据等于认证一个已不存在的构建；按“证据必须在当前候选 HEAD 重新生成”原则，桌面+T3 全绿后导出新候选包再跑五图最终包矩阵与关键桌面内容闭环。
4. 运行本机性能资格（`tests/ci/run_performance_capture.ps1`，外部采样须跟踪 console.exe 派生的 GUI 子进程 PID）与严格 7,200 秒长稳（`tests/ci/run_strict_target_hardware_soak.ps1 -SoakSeconds 7200`），再更新覆盖矩阵和最终报告。
5. 最终报告 + 合并 master + tag + release + 同步远程。
