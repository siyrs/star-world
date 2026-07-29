# 异常会话恢复与安全退出合同

## 目标

《星的世界》已经具备原子世界保存、`.tmp` / `.bak` 恢复、有界自动保存、保存来源时间线和世界进入会话隔离。本轮把这些能力推进为玩家可见、应用级完整闭环：

- 异常退出后，下一次启动明确展示“恢复上次世界”；
- 主菜单退出、暂停菜单退出和 Windows 窗口关闭共享一次权威最终保存；
- 最终保存失败时取消退出，保留活动世界与故障证据；
- 恢复只读取最近成功提交的权威存档，不恢复未提交内存状态。

## 不可歧义验收摘要

- 异常退出恢复只引用**权威存档**；
- `session_recovery.json` **不进入 world.json**，也不成为第二份世界数据；
- 最终保存失败时取消退出，保留活动世界、Pause、Runtime Health 与恢复标记；
- 真实桌面必须完成中断、模拟重启、恢复和安全退出三阶段旅程；
- 最终合入必须通过 **Windows Release** 实际导出、启动与退出资源检查；
- 新能力必须沉入既有四个**稳定入口**，不得通过替换生产场景脚本或保留平行包装类实现。

## 稳定入口兼容合同

仓库以下文件已经是其他模块、静态门禁和真实场景共同依赖的公共入口：

```text
scenes/game/game.tscn
  → src/core/batched_game.gd

scenes/ui/service_hub.tscn
  → src/ui/exploration_progression_service_hub.gd

scenes/ui/main_menu.tscn
  → src/ui/accessibility_protected_main_menu.gd

scenes/ui/game_ui.tscn
  → src/ui/accessibility_machine_game_ui.gd
```

因此本能力直接增量扩展：

- `BatchedStarWorldGame`：窗口关闭和应用退出所有权；
- `ExplorationProgressionServiceHub`：恢复服务、最终保存协调与应用退出事实；
- `AccessibilityProtectedMainMenu`：恢复卡片、恢复焦点和退出意图；
- `AccessibilityMachineGameUI`：暂停菜单安全退出命令。

禁止保留 `CrashSafe*` 或 `CrashRecovery*` 平行包装类。这样旧 ServiceHub、机器、自动保存、可访问性和 UI 合同不需要认识新的场景入口。

## 权威边界

```text
世界真实状态
  └─ GameplayServiceHub.save_current()
       └─ SaveService.save_world()
            └─ user://worlds/<world_id>/world.json

异常会话证据
  └─ WorldSessionRecoveryService
       └─ user://session_recovery.json
            ├─ world_id / world_name / map_id
            ├─ loading / active
            ├─ started / updated / last checkpoint 时间
            └─ checkpoint count
```

`session_recovery.json` 不是第二个世界存档：

- 不保存玩家坐标、背包、方块、机器、农业或任何玩法状态；
- 恢复操作始终调用 `SaveService.load_world(world_id)`；
- checkpoint count 只来自真实 `SaveService.world_saved`；
- 所有标记字段都禁止进入 `world.json`；
- 删除标记只会失去恢复提示，不会损坏世界。

## 状态所有者

### `WorldSessionRecoveryPolicy`

纯 `RefCounted`，负责：

- schema v1 严格投影；
- world ID 最长 128、名称最长 128、地图 ID 最长 64；
- `loading` / `active` 两个允许状态；
- 时间戳和检查点计数范围校验；
- create / normalize / mark active / record checkpoint / candidate 转换。

它不创建 Node、Timer、文件、线程或保存事务。

### `WorldSessionRecoveryService`

唯一异常会话标记所有者，负责：

- 进入世界前写入 `loading`；
- 世界正式可玩后切换为 `active`；
- 每次权威 `world_saved` 后更新检查点时间与数量；
- 正常返回菜单、世界启动失败、玩家忽略提示或世界删除后清除标记；
- 进程直接结束时不主动清除标记，使其成为下次启动证据。

### `BatchedStarWorldGame`

唯一应用退出所有者，负责：

- 设置 `SceneTree.auto_accept_quit = false`；
- 接收主菜单退出、暂停菜单安全退出和 `NOTIFICATION_WM_CLOSE_REQUEST`；
- 单飞调用 `ExplorationProgressionServiceHub.prepare_application_quit()`；
- 只有最终保存与世界释放成功后才调用 `SceneTree.quit(0)`；
- 测试模式可以关闭真正进程退出，但不能绕过同一协调路径。

UI 永远不直接终止进程。

## 标记生命周期

### 进入世界

```text
用户选择或恢复世界
→ 写 session_recovery.json(state=loading)
→ 正式世界启动
→ state=active
```

标记写入失败不会阻止世界启动，因为它是恢复提示而不是权威世界数据；失败只进入有界诊断。

### 权威检查点

```text
manual / autosave / return_to_menu / system
→ 同一个 save_current()
→ SaveService.world_saved
→ marker checkpoint_count + 1
```

不能在 UI 点击、autosave due、pending 或保存请求发起时提前增加检查点。

### 正常离开世界

```text
最终保存成功
→ FeatureLifecycle 逆序清理
→ current_world_id 清空
→ 清除 marker primary/tmp/bak/recover/corrupt
```

必须在确认世界实际释放后清除。最终保存失败时：

- `current_world_id` 继续保留；
- Runtime Health 继续 attached；
- Pause UI 显示“已取消退出”；
- 进程不退出；
- 异常会话标记继续存在。

### 异常退出

进程崩溃、设备断电或被强制终止可能绕过正常清理。下一次启动读取当前主标记；若对应权威世界仍存在，主菜单展示恢复卡片。

恢复按钮只执行：

```text
SaveService.load_world(marker.world_id)
```

因此最多回到最近一次成功的手动或自动检查点，不会读取未完成内存状态。

## primary-only 误报防护

`AtomicJsonStore` 对世界数据采用 primary → temporary → backup 恢复，这是正确的；但提示性会话标记的旧 backup 可能属于已正常结束阶段。

因此 marker 采用 fail-closed：

- 只接受当前 `session_recovery.json` 主文件；
- 主文件缺失或损坏时，不提升 `.tmp` / `.bak` 为恢复提示；
- 检测到非 primary 候选时清理全部 marker 文件；
- 权威 `world.json` 的恢复规则完全不变。

即使 marker 被丢弃，普通“继续游戏”和存档浏览器仍可访问世界；漏提示优于恢复错世界。

## 单一退出协调器

```text
Main menu 退出 ─┐
Pause 保存并退出 ├─→ BatchedStarWorldGame.request_application_quit(source)
WM_CLOSE ────────┘
                        ↓
       ExplorationProgressionServiceHub.prepare_application_quit()
                        ↓
              RuntimeHealthServiceHub.return_to_menu()
                        ↓
         return_to_menu reason + authoritative save_current()
                        ↓
          成功：释放世界、清 marker、允许进程退出
          失败：保留世界与 marker、取消进程退出
```

不创建第二个退出保存实现，也不直接调用 `SaveService.save_world()`。

## 玩家体验

### 启动恢复卡片

主菜单在存在有效标记时显示：

- 世界名称；
- 地图 ID；
- 本次会话已成功完成的检查点数量；
- “恢复上次世界”；
- “忽略并清除”。

“忽略并清除”只删除提示，不删除世界。

恢复卡片出现时，它取代重复的普通“继续游戏”主 CTA；“创建新世界”“存档 / 继续”“设置”等入口仍保留。这样在 1024×576 下保持命令面板有界，同时让键盘与控制器焦点优先落在恢复动作上。

### 暂停菜单

新增“保存并退出游戏”：

- 点击后显示正在执行最终保存；
- 成功后回到主菜单并准备退出；
- 失败时显示已取消退出，保持暂停和世界所有权；
- 玩家可以释放空间、恢复权限后再次尝试。

### Windows 窗口关闭

标题栏关闭按钮与菜单命令共享完全相同的保存、失败和恢复语义，不再由 Godot 默认自动接受关闭请求。

## 持久化与兼容性

不修改：

- `world.json` schema；
- `catalog.json`；
- settings；
- trash manifest；
- 方块 ID、Seed 或旧世界迁移；
- 自动保存 0/2/5/10/15 分钟设置；
- 15/60/300 秒失败退避；
- 保存检查点 12 条历史；
- 四个生产场景稳定入口。

## 永久测试

### 模拟重启

`world_session_recovery_regression.gd` 验证：

- loading → active；
- 真实保存后 checkpoint count；
- 销毁服务 A、创建服务 B 的模拟重启；
- dismiss 不删除世界；
- corrupt primary 不提升旧 backup；
- 删除世界清 stale marker；
- marker 字段不进入 `world.json`。

### 应用退出

`graceful_application_quit_regression.gd` 验证：

- Windows window-close；
- 主菜单退出意图；
- 暂停菜单退出意图；
- 成功最终保存后释放世界；
- 最终保存失败时取消退出；
- 失败时保留 world ID、Pause、Runtime Health 和 marker；
- 恢复 SaveService 后安全重试；
- teardown 恢复 `auto_accept_quit`。

### 紧凑分辨率与焦点

`session_recovery_ui_regression.gd` 在 1024×576 下验证：

- 恢复卡片和命令面板不越界；
- 恢复状态只收起重复的普通主 CTA；
- 原六命令合同仍保持；
- 键盘与控制器焦点优先恢复；
- Pause 安全退出按钮不越界并使用 Danger 层级。

### 真实桌面

`world_session_recovery_desktop_acceptance.gd` 使用正式 `game.tscn`：

1. 创建并启动真实世界；
2. 修改背包并执行真实保存；
3. 模拟未走 return-to-menu 的进程中断；
4. 创建新的正式 Game 实例模拟应用重启；
5. 截图主菜单恢复卡片；
6. 真实鼠标点击“恢复上次世界”；
7. 验证背包从最近权威检查点恢复；
8. 真实 Escape 打开 Pause；
9. 截图“保存并退出游戏”；
10. 真实鼠标点击安全退出；
11. 验证 marker 清除、世界仍可加载、数据完整；
12. 截图干净主菜单并输出 JSON、stdout、stderr。

## CI 与发行

`.github/workflows/crash-safe-session-recovery-tests.yml` 永久执行：

- 静态架构合同；
- Godot 4.7 严格导入；
- 模拟重启、应用退出、1024×576 UI 与焦点回归；
- 自动保存、保存时间线、世界会话、保存恢复、Runtime Health、UI 与 Runtime Soak 相邻回归；
- 三张真实桌面截图和 JSON Artifact。

最终合入仍必须通过仓库权威 Runtime、完整真实桌面矩阵与 **Windows Release** 实际导出、启动和退出资源检查。
