# Development Plan

## Requirement Summary
- 对当前 Godot 4.7 Windows 游戏执行全内容发现、fresh export、真实 UI 操作、全地图/任务/状态/性能覆盖，按实测问题完成可维护修复和自动化回归，再由独立 QA 重测。

## Architect Review
| Item | Decision / Guidance | Notes |
|---|---|---|
| System boundaries | 现有正式逻辑保持在 `src/`、`scenes/`、`data/`；测试机器人、巡检、采样和证据代码优先位于 `tests/`、`tools/`、`qa/` | 不用跳过玩法或改存档伪造覆盖 |
| Data/API/config/deploy impact | 只在实测缺陷要求时改变配置/数据/API；导出仍限 Windows Desktop | 不执行正式部署/推送/发布 |
| Compatibility or migration impact | 任一存档格式变化必须具版本号、缺省值、容错/迁移和旧存档回归；正式行为变化需保持已有输入/API 兼容 | 地图 ID/坐标/状态不可散落硬编码 |
| Technical constraints for Developer | 先复现保存证据，再修改；每个修复小提交；测试辅助与 release 逻辑隔离；当前源码构建产物必须使用独立输出目录 | 禁止复用 `build/` 根目录旧包作当前证据 |
| Architecture risks | 动态体素世界、程序化地图与单一主场景可能使“地图”不是独立 `.tscn`；覆盖清单必须交叉世界预设/Seed/服务/传送/存档，而非只数场景文件 | 若发现跨系统改造再激活独立 Architect |

## Architect Questions Back to PM
| Question | Reason | PM Answer | Need User Confirmation | Status |
|---|---|---|---|---|
| 是否需要先行独立 Architect？ | 当前尚无确定的跨 API/数据迁移方案 | PM：不需要；沿用现有模块边界，发现具体架构风险再激活 | no | resolved |

## Feasibility Assessment
| Item | Result | Notes |
|---|---|---|
| Can implement? | yes | Developer D-001 确认四个 smoke 问题均可修；PM 已为 UI/出生/runner/packaging 定义最小工作包 |
| Difficulty | high | 需要全内容、真实 GUI、性能、长稳、修复和独立回归 |
| Rough effort | 首批门禁修复约 1 个工作日，完整五地图/长稳按证据持续 | 性能生产调度若需结构拆分再增加工作量，不降低验收 |
| Main risks | 动态内容发现不全、UI 自动化可观测性、运行时长、存档污染、性能采样一致性 | 通过清单交叉验证、隔离存档/输出、固定采样条件和 session-state 缓解 |
| Unknowns | 当前全部世界预设、任务/传送/水域以及自动化覆盖缺口 | Analyst A-001 负责关闭 |

## Developer Questions Back to PM
| Question | Reason | PM Answer | Need User Confirmation | Status |
|---|---|---|---|---|
| 第一轮实施是否允许先只建立 fresh baseline 而不修改正式逻辑？ | 需要先区分当前缺陷与旧包误判 | PM：允许且必须；发现缺陷后再进入修复 | no | resolved |

## Developer Concrete Proposal
- D-001 已确认：
  - PowerShell 5.1 缺少 `ArgumentList` 且 `Kill(true)` 不兼容；提供安全 Windows argv 转义、兼容进程终止和 UTF-8。
  - 导出字体必须通过静态 `preload` / ResourceLoader 使用导入后的 `FontFile`，不能 `FileAccess` 原始 TTF 或吞 warning。
  - chunk warning 先建立固定 Seed/视距、静止收敛与移动压力时间序列；不放宽阈值/降低视距上限。只有证实持续 4 ms 预算超支才拆小可中断 slice。
  - release 的 `Performance.MEMORY_STATIC=0` 属不可用指标；内部标 N/A/来源，外部驱动绑定精确 PID 采 Working Set/Private Bytes 时间序列。
- PM 按发布优先级将首个实施包定为：BUG-QA-002 runner 契约、BUG-UI-002 可读性、BUG-SPAWN-001 出生体验；随后 BUG-REL-001、BUG-PACK-001、BUG-UI-001，再进入性能/遥测和五地图旅程。

## Technical Approach
- 使用 `tests/release/run_windows_export_smoke.ps1` 建立 fresh 导出、运行、JSON、截图和致命日志首门禁。
- 运行 `tests/run_all.ps1` 和项目已有 headless/desktop acceptance，按退出码与原始日志记录当前回归面。
- 从正常玩家入口以 Windows GUI 输入操作；在必要时使用项目内测试场景/脚本快速覆盖兴趣点，但另行验证正常路径。
- 新增测试工具时使用显式 QA 参数或独立 test script，默认 release 路径不得暴露测试入口。
- 运行时采样固定分辨率、渲染器、VSync/场景/周期，并用游戏内帧数据与系统进程/GPU 数据交叉核验。
- 修复循环：证据 → 根因 → 最小修改 → focused self-test → fresh build → 独立 QA retest → 相邻回归。

## Implementation Order
1. Analyst 完成地图/内容/入口/覆盖缺口发现，PM 更新矩阵。
2. Developer 复核可行性和具体首轮命令；PM readiness validator 通过。
3. fresh export/smoke、全量自动化基线、首次真实 UI 新建游戏和基准采样。
4. 逐地图正常路径、专项和极端测试；问题按 P0→P1→P2→P3 修复。
5. Developer 自测后独立 QA 验证；QA 缺陷返回 Developer 修复再重测。
6. 长稳、性能前后对比、发布门禁、PM 验收与小提交交付。

## Feature Implementation Plan
| Function Point | Implementation Steps | Owner | Status | Notes |
|---|---|---|---|---|
| FP-001 | 核验工具/命令/路径，执行 editor scan、run_all 和 fresh release smoke | Developer | not-started | Analyst 先输出 |
| FP-002 | 将唯一地图/内容清单写入覆盖矩阵，并提供可达入口 | PM + Developer | not-started |  |
| FP-003 | fresh export，验证产物哈希/时间戳/启动/退出 | Developer | not-started |  |
| FP-004 | 正常入口实际完成全部地图和任务 | Developer | not-started |  |
| FP-005 | 增补碰撞/边界/掉图探针并修复实际缺陷 | Developer | not-started |  |
| FP-006 | 增补水域/水下状态用例并修复实际缺陷 | Developer | not-started |  |
| FP-007 | 存读档、任务、死亡复活、地图切换和兼容性回归 | Developer | not-started |  |
| FP-008 | UI/音频/输入/设置/相机的真实桌面用例与打磨 | Developer | not-started |  |
| FP-009 | 建立基线/长稳采样，定位并优化实际瓶颈 | Developer | not-started |  |
| FP-010 | focused regression、自测、QA handoff/bugfix | Developer | not-started | QA 独立重测 |
| FP-011 | 更新证据/报告，按问题类型提交 | PM + Developer | not-started | 不推送/发布 |

## Files and Modules to Change
| Area | File/Module | Change Summary |
|---|---|---|
| QA/task records | `qa/**`, current task workspace | 持续记录覆盖、证据、问题、性能、回归和门禁 |
| Existing QA harness | `tests/**`, `tests/release/run_windows_export_smoke.ps1` | 复用并按发现缺口最小扩展 |
| Game/runtime | `src/**`, `scenes/**`, `data/**` | 仅对已复现缺陷做最小可维护修改 |
| Export | `project.godot`, `export_presets.cfg` | 仅在构建/版本/发布缺陷确证时修改 |
| Cross-PowerShell driver | `tests/release/run_windows_export_smoke.ps1`, docs | PS5.1 + pwsh 安全参数、终止、UTF-8、精确 PID 外部采样 |
| UI/theme | `src/ui/design_tokens.gd`, `src/ui/theme_factory.gd`, responsive map/settings UI | 导出字体、对比度、行高/间距、按钮可识别 |
| Spawn | `src/world/world_generator.gd` 及相关 QA | 数据驱动候选评分：净空、离树距离和前向视野；不硬编码坐标 |
| Diagnostics/perf | `src/diagnostics/**`, `src/world/**`, `src/chunk/**`（仅在数据触发时） | 指标可用性、收敛时间序列、必要时内部调度优化 |

## API / Config / Deploy Impact
- API impact: 当前无预先变更；每个问题另行评估。
- Config impact: 当前无预先变更；固定当前 Windows Desktop/GL Compatibility 基线。
- Deploy impact: 无；不推送、不发布。
- Data migration impact: 当前无；若存档结构修复则必须兼容旧版本并记录迁移。

## Self-test Plan
- [ ] 当前 commit editor import/scan 无解析错误
- [ ] `tests/run_all.ps1` 通过并保存日志
- [ ] fresh release smoke 通过且产物时间戳/哈希可核验
- [ ] focused issue regression 通过
- [ ] 相邻地图/状态/输入回归通过
- [ ] 日志无新增影响游玩的高频错误

## Rollback Plan
- 每个修改保持小提交；若回归失败，以对应提交为边界做正向修复。禁止 reset/checkout 丢弃用户内容；必要时用新修复提交回退行为。

## Risks
- 详见 `15-risk-register.md`；Developer 在发现报告后补充具体实现风险。

## Developer Confirmation
- Architect guidance reviewed: yes
- Feasibility reviewed: yes
- Concrete implementation plan ready: yes
- Ready to implement after user confirmation: yes
- Confirmed at: 2026-07-31 10:24 +08:00
- Notes: 用户已在初始请求明确授权实施；无需再次确认。等待 QA-001 完成 Gate 4 即可开始。
