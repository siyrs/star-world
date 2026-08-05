# PR #102 Closure Report

## 结论

PR #102 初始提交仅包含临时仓库快照 workflow，与描述中的功能不一致。本次闭环补齐 Iteration 56 剩余可自动化任务，并删除临时 workflow。目标分支为仓库实际默认分支 `master`。

## 清单映射

| Iteration 56 项目 | 状态 | 证据 |
|---|---|---|
| 1. 结构破坏与掩体反制 | 已完成 | PR #94 及既有永久回归 |
| 2. 方向受击反馈 | 已完成 | 权威上下文、四方向固定池、来源/伤害/护甲文字、相机与可访问性设置 |
| 3. 遭遇强度设置 | 已完成 | schema v1 三档 profile，只缩放冷却和危险压力 |
| 4. 弹药制造与掉落再平衡 | 已完成 | 燧石/火药奖励、成品弹药双层拒绝、燧石箭矢配方 |
| 5. 长时混合战斗 Release Soak | 工程部分完成 | 3,600 秒确定性混合战斗；真实 Windows 目标硬件 7,200 秒仍为外部 HOLD |

## 关键实现

- `DamageDirectionPolicy`：纯函数计算前/右/后/左，并提供近战、深渊弹和环境标签；
- `CombatService`：在权威 incoming result 中保留 source position、最终伤害和护甲吸收；
- `CombatFeedbackOverlay`：固定四槽方向提示与可访问文字；
- `GameSettingsPolicy`：方向脉冲、相机冲击与遭遇强度 canonical settings；
- `EncounterIntensityRegistry/Policy/Director`：三档强度，只改变节奏和危险预算；
- `EncounterRewardRegistry/Service`：只允许燧石/火药，运行时拒绝成品弹药；
- `ranged_combat.json`：正式注册燧石并让箭矢配方消耗燧石；
- 永久 CI、统一测试入口和专项文档。

## 测试矩阵

- 静态：数据 schema、纯策略、硬预算、设置传播、奖励白名单、永久 workflow、文档边界；
- 主回归：方向、来源、设置损坏回退、强度倍率、编组不变、奖励过滤、真实合成；
- 长稳：两名射手、四只僵尸、一名重击者，恰好 3,600 秒、80 奖励、三次保存/重载和菜单清理；
- 相邻：Reward Economy、Ranged Registry、Encounter Director、Settings、Runtime Soak；
- 桌面：生产设置面板、生产 HUD、截图、JSON 报告和退出清理。

## 复审修正

开发复核额外纠正：

- 3,600 秒奖励火药数学期望从错误的 280 改为 240；
- 保存边界限定为三次，避免结束时多保存一次；
- 桌面奖励断言改为 0 完成轻型弹，而不是误读弹匣内子弹为背包弹药；
- 临时快照 workflow 不进入永久分支；
- 历史“奖励直接补完成弹药”的文档明确由 Iteration 57 取代。

## 证据边界

本 PR 只有在固定 head SHA 的永久 CI 全绿后才可合并。即使合并，商业发布仍为 **HOLD**：独立 E4-H、最低/推荐目标硬件和真实 7,200 秒最终包长稳尚未完成。
