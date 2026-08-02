# Decision Log

Record key PM, architecture, QA, scope, and user decisions that affect delivery.

## Decisions

| Decision ID | Time | Owner | Context | Decision | Alternatives Considered | Rationale | Impact | Related FP / AC | Status |
|---|---|---|---|---|---|---|---|---|---|
| DEC-001 | 2026-07-31 10:08 +08:00 | PM | 用户要求在独立分支工作 | 使用 `codex/commercial-release-gameplay-polish`，起点 `c1054d8` | 直接修改 master；独立 worktree | 起始工作树干净，独立分支足以保护用户状态且避免 OneDrive 多 worktree 复杂性 | 全部修改和提交仅在独立分支 | FP-011 / AC-010 | accepted |
| DEC-002 | 2026-07-31 10:09 +08:00 | PM | build 根目录有 2026-07-26 旧 EXE/PCK | 以 `build/release-readiness-fresh` 独立 fresh export/smoke 为首门禁 | 直接启动旧包；覆盖根目录包 | 防止旧二进制误判，并保存本轮独立日志/JSON/截图 | 基线与后续回归可追溯 | FP-003 / AC-001 | accepted |
| DEC-003 | 2026-07-31 10:09 +08:00 | PM | 旧任务 2026-07-11 曾宣称 5 地图/193 checks 通过 | 仅作内容候选和历史断点，不当作当前 HEAD 通过 | 继承旧验收 | 当前 HEAD 已有大量后续功能提交且旧包过期 | 本轮全部地图与性能必须重测 | FP-002,FP-010 / AC-002,AC-009 | accepted |
| DEC-004 | 2026-07-31 10:08 +08:00 | PM | 并发槽和职责隔离 | 使用 Analyst→Developer→独立 QA 串行最小团队；PM 管理所有 handoff | 同时创建全角色团队 | 满足单一职责和 QA 独立性，减少跨代理冲突 | 开发前 readiness，QA bug 必须重测 | FP-010 / AC-008 | accepted |
| DEC-005 | 2026-07-31 10:08 +08:00 | PM | 用户授权实施但禁止未授权发布 | 本地修改、小提交；不 push/tag/release | 自动发布 | 保持授权边界 | 发布动作不在本任务自动范围 | FP-011 / AC-010 | accepted |

## Superseded Decisions

| Decision ID | Superseded By | Reason | Time |
|---|---|---|---|
|  |  |  |  |
