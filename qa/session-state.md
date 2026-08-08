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
- T3 全量回归（整改后重跑）：正在执行 `tests/run_all.ps1`，证据写入 `build/commercial-acceptance-20260808/t3-post-remediation/`。
- fresh Windows 导出：已完成一轮（`export-smoke-after-gdignore`，11:40，smoke 通过）；若 T3 后有代码修复则重新导出。
- 最终 EXE 五图路线：待执行。
- 全部桌面验收旅程：待执行。
- 本机最低/推荐硬件资格：待硬件分档后执行。
- 严格 7,200 秒长稳：待 fresh 候选包与短资格门禁通过后执行。

## 地图进度（仅本轮）

| Profile | 进入 | 连续正常路线 | 内容闭环 | 碰撞/边界 | 水域/危险 | 存读档/死亡复活 | 最终 EXE | 状态 |
|---|---|---|---|---|---|---|---|---|
| `star_continent` | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | pending |
| `desert_ruins` | 待测 | 待测 | 待测 | 待测 | N/A/待核对 | 待测 | 待测 | pending |
| `frozen_wastes` | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | 待测 | pending |
| `sky_islands` | 待测 | 待测 | 待测 | 待测 | 高空/跌落待测 | 待测 | 待测 | pending |
| `abyss_world` | 待测 | 待测 | 待测 | 待测 | 熔岩待测 | 待测 | 待测 | pending |

## 问题与回归

- 当前正在处理的问题：尚无；等待 fresh 基线发现。
- 已修复问题：0。
- 待独立 QA 回归：0。
- 历史外部 HOLD：独立 E4-H、两档实体硬件、严格 7,200 秒、物理 HDD/杀毒/断电、发布签名与更新信任引导；本轮将重新核实可在当前电脑执行的部分，不直接沿用历史状态。

## 最近命令与证据

- 最近一次命令：`tests/run_all.ps1 -Godot build/tools/godot/Godot_v4.7-stable_win64_console.exe`（整改后重跑，运行中）
- 本轮证据根目录：`build/commercial-acceptance-20260808/`（整改后 T3：`t3-post-remediation/`）
- 用户真实存档：不得修改；测试使用隔离 `APPDATA`/`LOCALAPPDATA` 重定向（Godot 4.7 无 `--user-data-dir`），前后校验清单。

## 下一步

1. 收集并审计 fresh T3 的退出码、用例计数和 fatal/leak 日志。
2. 对失败项执行复现—定位—修复—Developer 自测。
3. fresh 导出同一 EXE/PCK，运行五图最终包矩阵与关键桌面内容闭环。
4. 由独立 QA 以原用例和相邻流程重测所有修复。
5. 运行本机性能资格与严格长稳，再更新覆盖矩阵和最终报告。
