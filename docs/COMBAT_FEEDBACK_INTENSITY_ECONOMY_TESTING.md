# 战斗反馈、遭遇强度与弹药经济测试

## 永久质量门禁

`.github/workflows/combat-feedback-intensity-economy-tests.yml` 在相关 Pull Request 和 `master` 推送时运行。它复用严格 Godot 质量门禁，并执行：

1. 数据与静态架构验证；
2. 方向受击、设置、强度和奖励主回归；
3. 3,600 秒混合战斗确定性长稳；
4. 既有 Encounter Reward、Ranged Combat、Encounter Director、Settings 与 Runtime Soak 相邻回归；
5. 正式 ServiceHub、Hardened Settings 与生产 HUD 桌面验收；
6. 截图与 JSON 报告上传。

统一入口 `tests/run_all.ps1` 同时纳入新的静态验证、主回归和长稳回归，防止专项工作流与全仓库测试分叉。

## 主回归

`combat_feedback_intensity_economy_regression.gd` 验证：

- 前、右、后、左方向计算；
- 近战、深渊弹和环境来源文字；
- 来源缺失时显式回退；
- 视觉方向脉冲可独立关闭；
- 相机冲击上下限和损坏设置回退；
- 三个 versioned 遭遇强度 profile；
- 强度只缩放冷却与危险压力，不改变正式敌人编组；
- Reward Registry 和运行时事务都拒绝成品弹药；
- 燧石可通过真实 CraftingService 完成箭矢制造闭环。

## 3,600 秒长稳

`mixed_combat_long_run_regression.gd` 使用确定性一秒步长验证：

- 两名射手、四只僵尸和一名重击者固定为 7 个敌对成员；
- 六个暂停窗口共冻结 30 秒且暂停期间无战斗步进；
- 三次 JSON 保存和重载保持设置与计数；
- 80 场奖励只产生燧石/火药，不产生任何成品弹药；
- 弹丸、活动 Encounter、追踪成员和方向脉冲高水位不超过生产硬上限；
- 显式返回菜单后弹丸、Encounter、方向脉冲和 pending 全部归零。

## 正式桌面验收

`combat_feedback_intensity_desktop_acceptance.gd` 在真实 ServiceHub 中：

- 打开 Hardened Settings；
- 选择高危强度；
- 关闭方向脉冲；
- 将相机冲击设为 0.4；
- 验证设置即时生效并持久化；
- 用同一条 `incoming_damage_resolved` 信号驱动生产 HUD；
- 验证关闭脉冲后，方向、来源、最终伤害和护甲吸收文字仍可访问；
- 输出设置截图、HUD 截图和 JSON 报告；
- 清理测试 Combat 节点和 ServiceHub。

## 相邻经济复审

既有奖励测试同步调整为原材料经济：

- 高效深渊突袭奖励为 2 燧石 + 4 火药；
- 四发手枪消耗保持真实 -4，不因奖励恢复成品弹药；
- 满背包 pending 仍为单个原子事务；
- 自动重试后精确增加燧石/火药；
- 3,600 秒、80 场固定产出 120 燧石和 240 火药；
- 轻型弹净消耗保持 -400，证明低风险 Encounter 不再成为无限完成弹药农场。

## 证据边界

GitHub 托管 CI 能证明导入、确定性逻辑、生产场景组合、截图和资源清理。它不能证明真实玩家体验或真实目标 GPU 的最低帧率与 7,200 秒稳定性。因此即使全部自动化测试通过，商业发布状态仍为 **HOLD**。
