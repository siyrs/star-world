# Architecture Audit · 2026-07-29 · Iteration 51

## 审计范围

本轮从长期自动保存继续向应用级可靠性推进，审计：

- 主菜单退出与 Windows 窗口关闭；
- `GameplayServiceHub.return_to_menu()` 的最终保存边界；
- 异常退出后的玩家恢复闭环；
- marker、权威世界存档和旧 backup 的语义差异；
- 生产场景稳定入口、既有继承链和全仓静态合同；
- 模拟重启、真实桌面和 Windows Release 门禁。

## 发现 1：UI 直接终止进程

原 `MainMenu._quit()` 同时执行：

```text
quit_requested.emit()
get_tree().quit()
```

UI 直接终止进程，使组合根无法先执行最终保存，也无法在保存失败时取消退出。这是应用生命周期所有权倒置。

## 发现 2：窗口关闭绕过最终保存

项目此前没有关闭 `SceneTree.auto_accept_quit`，也没有处理 `NOTIFICATION_WM_CLOSE_REQUEST`。Windows 标题栏关闭可能不经过：

```text
RuntimeHealthServiceHub.return_to_menu()
→ return_to_menu save reason
→ GameplayServiceHub.save_current()
→ FeatureLifecycle reverse cleanup
```

自动保存只能限制损失窗口，不能替代一次可失败、可观察的最终保存。

## 发现 3：可靠存档没有玩家可见恢复闭环

已有系统已经提供：

- 原子 JSON；
- `.tmp` / `.bak` 自愈；
- 有界自动保存；
- 12 条检查点时间线；
- 当前世界本次进入隔离；
- Runtime Health 保存失败证据。

但异常退出后主菜单没有告诉玩家上次哪个世界未正常结束，也没有直接恢复最近权威检查点的入口。

## 发现 4：不能把运行会话塞进 `world.json`

给世界增加 `last_session_active=true` 会污染持久玩法 schema，而且崩溃时不保证最后一次世界保存有机会更新该字段。异常会话证据必须独立、极小、可删除，并且只引用权威 world ID。

## 发现 5：旧 backup 误报恢复

世界数据需要 primary → temporary → backup 的自愈顺序；提示性 marker 则不同。旧 `.bak` 可能来自已正常结束的上一阶段。如果主 marker 损坏后提升旧 backup，会错误显示“上次未正常结束”。

因此会话标记必须 primary-only fail-closed。

## 发现 6：退出失败必须保留所有权

现有 `return_to_menu()` 已正确做到最终保存失败时不清理世界；Runtime Health 也只在 `current_world_id` 清空后 detach。

新退出能力不能在失败时：

- 调用 `SceneTree.quit()`；
- 提前清 marker；
- 提前解除 Runtime Health；
- 在 Pause UI 中假装成功。

## 发现 7：生产场景文件是稳定入口

首轮实现尝试通过四个窄包装类挂载能力：

```text
CrashSafeStarWorldGame
CrashSafeServiceHub
CrashRecoveryMainMenu
CrashRecoveryGameUI
```

Godot 严格导入能够通过，但全仓既有门禁立即揭示：

- `service_hub.tscn` 必须继续挂载 `exploration_progression_service_hub.gd`；
- `game.tscn`、`main_menu.tscn`、`game_ui.tscn` 同样被视为公共稳定入口；
- 机器、自动保存、生命周期和可访问性合同依赖这些入口和直接继承关系；
- 替换场景入口会让本不相关的领域同时失败。

这不是旧测试“太严格”，而是仓库已经形成事实上的公共架构 API。正确修复不是批量放宽旧门禁，而是恢复稳定入口并把能力沉入现有顶层类。

## 决策

### 1. 单一退出协调器沉入 `BatchedStarWorldGame`

```text
MainMenu quit intent ─┐
Pause quit intent ────┼─→ BatchedStarWorldGame.request_application_quit(source)
WM_CLOSE ─────────────┘
```

它关闭 Godot 自动接受退出，只在 `prepare_application_quit()` 成功后调用 `SceneTree.quit(0)`。

### 2. 最终保存协调沉入 `ExplorationProgressionServiceHub`

不创建第二个保存实现，而是继续调用：

```text
RuntimeHealthServiceHub.return_to_menu()
```

因此保留：

- `return_to_menu` 来源；
- 原 `save_current()`；
- FeatureLifecycle 逆序清理；
- 失败保留 world ID 和 Runtime Health 的语义。

### 3. 恢复 UI 沉入稳定可访问性入口

- `AccessibilityProtectedMainMenu`：恢复卡片、恢复焦点、退出意图；
- `AccessibilityMachineGameUI`：暂停菜单“保存并退出游戏”。

不改变生产 `.tscn` 脚本路径，不保留平行 wrapper。

### 4. 独立严格会话标记

新增：

```text
user://session_recovery.json
```

只保存：

- world ID、名称、地图；
- loading / active；
- started / updated / checkpoint 时间；
- 成功 checkpoint count。

没有玩家状态、世界状态或调度状态。

### 5. 标记只监听权威事实

checkpoint count 只在 `SaveService.world_saved` 后增加，不能在 UI 点击、autosave due、pending、请求发起或保存失败时提前增加。

### 6. primary-only fail-closed

- primary 有效：展示恢复；
- primary 缺失或损坏：不展示；
- 仅 `.tmp` / `.bak` 有效：拒绝并清全部 marker；
- 世界数据自己的恢复策略不变。

### 7. 清除顺序

```text
最终保存成功
→ world ownership released
→ current_world_id empty
→ 清 marker
```

失败时保持 marker。

### 8. 1024×576 产品预算

恢复卡片与六个原命令同时显示会压缩紧凑高度。恢复状态下只隐藏重复的普通“继续游戏”主 CTA：

- 恢复成为当前主动作；
- 创建新世界、存档浏览、设置等入口保留；
- `_menu_buttons` 六命令合同不改变；
- 键盘和控制器焦点优先恢复；
- 1024×576 有独立布局回归。

## 不采用的方案

### UI 自己调用 save + quit

拒绝。会复制最终保存并绕过 Runtime Health 与 FeatureLifecycle。

### 只依赖自动保存

拒绝。不能证明用户主动关闭应用时执行了最终事务。

### 把 active flag 写入 world.json

拒绝。污染 schema 且崩溃时不可靠。

### 自动加载恢复世界

拒绝。恢复必须是玩家可见选择。

### 使用旧 backup 生成恢复提示

拒绝。旧 backup 误报恢复的风险高于漏提示。

### 创建第二份 crash snapshot 世界文件

拒绝。已有权威原子保存，不应复制世界状态与迁移域。

### 保留四个包装类并修改旧门禁

拒绝。包装类制造平行公共入口，批量修改旧门禁会掩盖真实兼容性退化。

## 测试设计

### 模拟重启

- schema 白名单和范围；
- loading → active；
- 真实 `world_saved` 更新；
- 销毁服务 A、创建服务 B 的模拟重启；
- dismiss 只清提示；
- corrupt primary + valid backup fail-closed；
- 删除世界清 marker；
- `world.json` 无 marker 字段。

### 应用退出

- 主菜单退出意图；
- 暂停菜单退出意图；
- 模拟 Windows close notification；
- 成功时最终保存与世界释放；
- 失败时取消退出；
- 失败时 Pause、world ID、Runtime Health、marker 保留；
- 修复保存服务后重试成功；
- SceneTree auto quit teardown 恢复。

### 稳定入口兼容

静态合同固定验证：

```text
game.tscn        → batched_game.gd
service_hub.tscn → exploration_progression_service_hub.gd
main_menu.tscn   → accessibility_protected_main_menu.gd
game_ui.tscn     → accessibility_machine_game_ui.gd
```

并验证四个临时 wrapper 不存在。

### 1024×576 UI

- 恢复卡片与命令面板不越界；
- 原六命令总数不变；
- 恢复状态只隐藏重复主 CTA；
- 恢复焦点优先；
- Pause 安全退出按钮不越界。

### 真实桌面与模拟重启

同一个测试进程创建两个正式 `game.tscn`：

1. 第一实例创建、游玩、修改背包并真实保存；
2. 不调用 return-to-menu，直接销毁第一实例；
3. 第二实例启动并读取磁盘 marker；
4. 截图恢复卡片；
5. 真实鼠标恢复世界；
6. 真实 Escape 打开 Pause；
7. 截图安全退出命令；
8. 真实鼠标执行最终保存；
9. 截图干净主菜单；
10. 验证世界可重载、背包完整和 marker 全清。

## 合入标准

只有以下全部成功才允许合入：

- 静态架构与稳定入口合同；
- Godot 4.7 严格导入；
- 模拟重启领域回归；
- graceful application quit 回归；
- 1024×576 UI 与焦点回归；
- 真实桌面三阶段旅程；
- 原自动保存、时间线、世界会话、保存恢复、目录、Runtime Health、UI 与生命周期回归；
- 权威 Runtime；
- 完整桌面矩阵；
- Windows Release 实际导出、启动和退出资源检查。
