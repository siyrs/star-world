# Risk Register

Track delivery, product, architecture, implementation, QA, release, and coordination risks.

## Risks

| Risk ID | Time | Category | Description | Probability | Impact | Mitigation | Owner | Status | Closed At | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| RISK-001 | 2026-07-31 10:08 +08:00 | qa | 动态/程序化世界使地图与兴趣点清单遗漏 | high | high | 从 scenes/data/src/menu/save/teleport/tests 多源交叉发现；未知默认按正式内容 | Analyst + PM | mitigating |  | Packet A-001 |
| RISK-002 | 2026-07-31 10:08 +08:00 | release | 旧 `build/StarWorld.exe` 导致把历史行为误判为当前源码 | high | high | 使用独立目录 fresh export；记录 HEAD、哈希、时间戳 | Developer | mitigating |  | DEC-002 |
| RISK-003 | 2026-07-31 10:08 +08:00 | qa | Windows GUI 自动化只观察到画面但无法证明内部状态 | medium | high | 截图/窗口状态与游戏内 JSON、日志、存档或测试断言交叉证据 | Developer + QA | open |  |  |
| RISK-004 | 2026-07-31 10:08 +08:00 | development | QA/性能工具污染正式发布逻辑或泄露调试入口 | medium | high | 独立 tests/tools/qa、显式参数和 release 默认关闭；增加合同测试 | Developer | open |  |  |
| RISK-005 | 2026-07-31 10:08 +08:00 | qa | 实际操作污染用户已有存档 | medium | high | 先发现存档位置，备份并使用唯一 QA 世界/隔离目录；任何破坏前做只读解析 | Developer + QA | open |  |  |
| RISK-006 | 2026-07-31 10:08 +08:00 | qa | 性能数据受 VSync/窗口/场景/采样工具漂移影响 | high | medium | 固定硬件、分辨率、渲染器、场景、Seed、时长和采样方式；保留原始数据 | QA | open |  |  |
| RISK-007 | 2026-07-31 10:08 +08:00 | development | 广泛修复引入存档/API/玩法回归 | medium | high | 小提交、focused + 相邻回归、旧存档兼容、QA bugfix 重测 | Developer + QA | open |  |  |
| RISK-008 | 2026-07-31 10:08 +08:00 | coordination | 长任务中断导致重复教程测试或遗漏断点 | medium | high | 每个重要步骤更新 `qa/session-state.md`，以矩阵和问题状态恢复 | PM | mitigating |  |  |

## Risk Review Rules

- P0/P1 risks must have an owner and mitigation before implementation starts.
- Closed risks must include evidence or rationale in Notes.
- Accepted risks must be explicitly accepted by PM and visible in the stage user report.
