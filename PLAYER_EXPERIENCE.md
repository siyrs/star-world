# 玩家体验架构

## 目标

玩家体验层负责把已经存在的玩法能力变成可理解、可学习、可验证的产品体验。它不拥有世界、背包或生存数据，也不替业务服务执行操作。

必须满足：

- 第一次进入世界时，玩家知道下一步做什么；
- 准星指向对象时，界面说明可执行操作；
- 成功、失败和状态变化都有即时反馈；
- 引导可以隐藏、关闭和恢复；
- UI 不拦截第一人称鼠标与键盘；
- 世界切换后没有旧 Player、Focus 或 Prompt 引用；
- 新增玩法通过统一合同接入，不在 HUD 中增加特殊判断。

## 运行结构

```text
GameplayServiceHub
└─ PlayerExperienceCoordinator
   ├─ GameplayFeedbackService
   ├─ OnboardingService
   └─ InteractionPromptResolver

Player
├─ PlayerFocusResolver
├─ interaction_focus_changed
└─ gameplay_action_reported

GameUI
└─ GuidanceOverlay
   ├─ Toast
   ├─ Context Prompt
   └─ Tutorial Goal
```

## 模块责任

### PlayerFocusResolver

输入 `RayCast3D + World`，输出统一焦点描述：

```text
block  { block_id, display_name, position, collectible, solid }
entity { entity_id, species_id, display_name, health, max_health }
```

它不绘制 UI，不执行攻击、采集或交互。

### InteractionPromptResolver

纯策略模块，根据：

- 当前焦点；
- 当前快捷栏物品；
- BlockInteractionService 的能力提示；

生成：

```text
title
subtitle
primary
secondary
tone
```

新增门、床、机器等交互时，应扩展交互注册表或提示策略，不把方块 ID 判断塞进 HUD。

### GameplayFeedbackService

负责短时反馈和当前提示状态：

- 有界 Toast 队列；
- 相同 key 去重；
- `info / success / warning / error`；
- Prompt 归一化；
- 世界结束时统一清理。

业务服务只发布事实，不控制动画或布局。

### OnboardingService

当前目标链：

```text
移动 → 环顾 → 采集 → 放置 → 背包 → 合成
```

特点：

- 乱序动作会被记住，但不会跳过当前说明；
- F1 仅临时隐藏，不修改输入上下文；
- 完成状态随世界保存；
- 全局设置可关闭教程；
- `restart()` 可用于未来的“重新开始引导”。

### PlayerExperienceCoordinator

组合根，负责：

- 连接 Player、Inventory、GameUI 和 BlockInteraction；
- 把焦点交给 PromptResolver；
- 把玩法动作交给 Onboarding 与 Feedback；
- 世界启动、失败、返回菜单时挂载和解除 Player；
- 将引导状态加入世界保存事务；
- 应用全局显示设置。

它不直接修改 Player、Inventory 或 World。

### GuidanceOverlay

纯展示组件：

- 顶部居中的 Toast；
- 快捷栏上方的上下文操作提示；
- 右上角的新手目标与进度；
- 右上引导、左上状态卡和底部快捷栏使用互不重叠的安全区；
- 背包、合成、容器、暂停和死亡时隐藏世界提示；
- Toast 可以继续展示保存或错误结果。

整棵树必须满足：

```gdscript
mouse_filter = Control.MOUSE_FILTER_IGNORE
focus_mode = Control.FOCUS_NONE
```

## 视觉系统

`StarDesignTokens` 是颜色、字体、间距、圆角和状态色的唯一基础定义。`ThemeFactory` 将这些 token 转换为 Godot Theme。

业务面板不应散落新的基础色值。特殊语义色可以覆盖，但需要明确含义，例如：

```text
health / hunger / success / warning / danger
```

当前最低桌面布局基线为 `1024×576`。设置页、状态卡、引导、上下文提示、选中物品和快捷栏必须全部位于视口内，并且不能互相覆盖。

## 数据合同

世界存档：

```text
experience {
  version,
  onboarding {
    version,
    completed,
    dismissed,
    current_index,
    completed_actions
  }
}
```

全局设置：

```text
show_tutorial
show_interaction_prompts
```

旧存档和旧设置缺失字段时使用默认值。

## 扩展步骤

新增一个需要玩家理解的玩法时：

1. 业务模块发布成功或失败事实；
2. Player 或领域服务使用稳定 action 名称；
3. OnboardingService 仅在确有学习目标时增加步骤；
4. InteractionPromptResolver 增加通用能力提示；
5. GuidanceOverlay 只展示，不新增业务判断；
6. `player_experience_regression.gd` 覆盖新合同；
7. `ui_layout_regression.gd` 覆盖最低分辨率安全区；
8. 桌面窗口和 Windows Release 截图确认信息不遮挡玩法。

## 发行画面证据

全屏颜色数量不能证明世界真正可见，因为彩色 HUD 可能掩盖只有天空的画面。最终 Windows Release 门禁还必须：

- 将玩家返回一个可验证的安全地面位置；
- 强制加载并验证玩家所在区块的网格和碰撞；
- 将摄像机调整到能看到地形的验收角度；
- 单独采样屏幕中央的世界区域；
- 检查中央区域具有足够的颜色层次，且不能被单一天空颜色主导；
- 报告 `focus_chunk_renderable`、`camera_current`、世界区域颜色数量和主导色比例。

这项门禁由 `visual_acceptance_regression.gd` 和导出后的 `ReleaseSmokeRunner` 共同约束。

## 验收标准

每次体验改动至少验证：

- 主菜单和覆盖层按钮仍可真实鼠标点击；
- 鼠标捕获后视角、左键和右键仍可用；
- GuidanceOverlay 全树透传鼠标；
- F1 不改变暂停、InputContext 或鼠标模式；
- Prompt 在覆盖层打开时隐藏，关闭后恢复；
- Toast 去重且队列有界；
- 引导跨保存恢复；
- 设置页和游戏 HUD 在 `1024×576` 内无裁切、无重叠；
- 返回菜单后 Player 和 Prompt 引用被释放；
- 最终导出包中央区域能看到真实世界几何，而不是仅凭 HUD 颜色通过；
- 发行报告、截图、日志和进程退出码全部有效。
