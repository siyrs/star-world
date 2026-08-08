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
- T3 全量回归（整改后重跑）：**142/142 全绿**（`RUN_ALL_EXIT=0`，0 fatal/leak）；上轮 7 个失败套件全部在本轮确认 PASS，证据 `build/commercial-acceptance-20260808/t3-post-fixes/`。
- fresh Windows 导出：已完成一轮（`export-smoke-after-gdignore`，11:40，smoke 通过）；因本轮有 game 侧修复（音频 Dummy 防护、读档位置保真、is_grounded、导出预设），桌面验收后重新导出候选包再跑五图矩阵。
- 最终 EXE 五图路线：待执行（基于新导出）。
- 全部桌面验收旅程：**进行中**（91 套件：`desktop_acceptance_regression` + 90 个 `*_desktop_acceptance.gd`，逐套件隔离用户数据 + 截图取证），证据写入 `build/commercial-acceptance-20260808/desktop-acceptance/`。
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

- 当前正在处理的问题：无阻塞；等待整改后 T3 结果。
- 已修复问题：1（`BUG-QUALIFY-POLICY-ROOT-001`，包校验器政策根硬编码 checkout 导致漂移测试窗口硬杀 T3；已加 `-PolicyRoot` 并提交 `6da93ee`，回归全过）。
- 待独立 QA 回归：0。
- 历史外部 HOLD：独立 E4-H、两档实体硬件、严格 7,200 秒、物理 HDD/杀毒/断电、发布签名与更新信任引导；本轮将重新核实可在当前电脑执行的部分，不直接沿用历史状态。

## 最近命令与证据

- 最近一次命令：`tests/run_all.ps1 -Godot build/tools/godot/Godot_v4.7-stable_win64_console.exe`（整改后重跑，运行中）
- 本轮证据根目录：`build/commercial-acceptance-20260808/`（整改后 T3：`t3-post-remediation/`）
- 用户真实存档：不得修改；测试使用隔离 `APPDATA`/`LOCALAPPDATA` 重定向（Godot 4.7 无 `--user-data-dir`），前后校验清单。

## 下一步

1. 桌面验收 91 套件全量执行并审计 summary（进行中）。
2. 对失败项执行复现—定位—修复—回归。
3. 重新导出 fresh EXE/PCK（含本轮 game 侧修复），运行五图最终包矩阵与关键桌面内容闭环。
4. 运行本机性能资格与严格 7,200 秒长稳，再更新覆盖矩阵和最终报告。
5. 最终报告 + 合并 master + tag + release + 同步远程。
