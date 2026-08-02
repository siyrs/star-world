# 回归测试结果

| 回归 ID | 问题/功能点 | 构建/commit | 测试方法 | 预期 | Developer 自测 | QA 独立结果 | 截图/日志/数据 | 状态 |
|---|---|---|---|---|---|---|---|---|
| RTC-QA-002 | BUG-QA-002 | 42ff644 | production-scene desktop acceptance，调用方精确 `-OutputPath` | 内层 32/10 + 外层 exit 0，primary/named/JSON/log 齐全 | pass；`build/developer-selftest-qa002` | PASS；exit 0，32/10，10 命名截图与 JSON 齐全，无 fatal | `build/qa-independent-qa002-20260731-1057` | qa-passed |
| RTC-UI-002 | BUG-UI-002 | 943a9d2 | headless design system + desktop visual 1280×720；QA-003 补 1024×576 与真实交互状态分析 | WCAG ≥4.5、无重叠/截断、返回按钮可读 | 首轮 pass；64 checks + 32 checks/10 captures | **QA-003 PASS**：design-system 137 checks 全 ≥4.5（含 Button/Primary/Card/Selected/Ghost/MenuPrimary normal/hover/pressed/focus）、visual-refresh 32/10、accessibility 28、layout-1024 24、journey 58 | `build/qa-independent-qa003-20260802-2007` | qa-passed |
| RTC-SPAWN-001 | BUG-SPAWN-001 | 2c7370c | 5 profiles×6 seeds、相邻地形/合成夹具/解析器/旧档/input contract/leak 3轮 | 全绿且运行有界；用户 12 世界/设置不变 | pass；5×6 全矩阵 279 checks；star/24681357 专项 18/18 | 五图深度旅程出生点 PLAYER SPAWN RESOLVE 全部正常 | `tests/qa/collision_seam_probe_regression.gd`；`build/claude-deep-journey` | qa-passed |
| RTC-LEAK-001 | BUG-LEAK-001 | 8df73c3 | 4 测试出口 verbose 泄漏明细 | ObjectDB/Resource 零泄漏 | 修复裸 Node + audio dispose | 逐套件 0 泄漏；全量 113/113 | `tests/qa/tool_harvest_regression.gd` 等 4 文件 | qa-passed |
| RTC-LAVA-001 | BUG-LAVA-001 | 547853f | 真实深渊世界熔岩柱接触 | 熔岩灼烧、间隔门控、离开即停、重生恢复 | 32 checks 全过（water_lava_lifecycle） | 同机制复测通过 | `tests/qa/water_lava_lifecycle_regression.gd` | qa-passed |
| RTC-SAVE-001 | OpenSpec 7.1 | fe0ab4b | 存读档矩阵 | 手动/覆盖/多世界/迁移全过 | 35 checks 全过 | 同机制复测通过 | `tests/qa/save_load_matrix_regression.gd` | qa-passed |
| RTC-STAB-001 | OpenSpec 7.4 | ae45393 | 极端输入/暂停/缩放/快速往返 | 无崩溃、零节点泄漏 | 36 checks 全过 | 同机制复测通过 | `tests/qa/stability_extreme_input_regression.gd` | qa-passed |
| RTC-DEEP-001 | OpenSpec 6.2-6.7 | 8ec6bb7 | 五图深度旅程+内容矩阵 | 全部真实菜单进入、死亡重生、持久化、重复进入 | 141 checks 全过 | 同机制复测通过 | `tests/qa/profile_deep_journey_regression.gd`；`build/claude-deep-journey` | qa-passed |

## 全量发布回归（v1.3.0，2026-08-02）

- [x] 当前源码重新构建（fresh export `build/claude-final-export-v2` 16/16）
- [x] 启动、新建、暂停、退出、重进（深度旅程 5 图 ×2 进入）
- [x] 全部正式地图进入与验收旅程（6.2-6.7，141 checks）
- [x] 主线、关键支线和重要交互（内容矩阵：工具/配方/机器/建造/生物/探索/休息/教程）
- [x] 碰撞、边界、掉图恢复（collision_seam_probe + 接缝连续 + Y<-12 恢复）
- [x] 所有水域与水下流程（water_lava_lifecycle 32 checks：河流/冰下/熔岩）
- [x] 存档、读档、死亡、复活、地图切换（save_load_matrix 35 + 深度旅程死亡重生）
- [x] UI、音频、设置、窗口焦点与分辨率（QA-003 + stability 36 checks）
- [x] 性能前后对比与长稳（13 场景 + 30min soak 291 循环 1.9% 增长）
- [x] 日志无影响游玩的高频错误（全量 113/113 零泄漏零 SCRIPT ERROR）
- [x] 全量自动化回归 113/113 EXIT 0
