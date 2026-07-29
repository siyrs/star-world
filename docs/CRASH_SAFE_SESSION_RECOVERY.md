# 异常会话恢复与安全退出合同

## 目标

《星的世界》已经具备原子世界保存、`.tmp` / `.bak` 恢复、有界自动保存、保存来源时间线和世界进入会话隔离。但这些能力此前仍缺少一个玩家可见的完整闭环：

- 应用、操作系统或设备异常退出后，下一次启动没有明确告诉玩家哪个世界上次未正常结束；
- 主菜单“退出”由 UI 直接调用 `SceneTree.quit()`，窗口关闭也可能绕过最终保存协调；
- 自动保存虽然限制了数据损失窗口，但玩家无法区分“正常退出”与“从最近检查点恢复”。

本合同增加：

1. 一个严格、极小、独立于世界数据的异常会话标记；
2. 主菜单“恢复上次世界”入口；
3. 暂停菜单“保存并退出游戏”；
4. 主菜单退出、暂停菜单退出和 Windows 窗口关闭共享的单一退出协调器；
5. 最终保存失败时取消退出并保持世界可继续操作。

## 不可歧义验收摘要

- 异常退出恢复只引用**权威存档**，不会恢复未提交的内存状态；
- `session_recovery.json` **不进入 world.json**，也不成为第二份世界数据；
- 最终保存失败时取消退出，保留活动世界、Pause、Runtime Health 与恢复标记；
- 真实桌面必须完成中断、重启、恢复和安全退出三阶段旅程；
- 最终合入必须通过 **Windows Release** 实际导出、启动与退出资源检查。

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
- 恢复操作始终重新调用 `SaveService.load_world(world_id)`；
- 标记只告诉 UI“上次哪个世界没有完成正常释放”；
- 标记中的 checkpoint count 只来自真实 `world_saved` 领域事实；
- 所有标记字段都禁止进入 `world.json`。

## 状态所有者

### `WorldSessionRecoveryPolicy`

纯 `RefCounted`，负责：

- schema v1 严格投影；
- world ID 最长 128、名称最长 128、地图 ID 最长 64；
- `loading` / `active` 两个允许状态；
- 时间戳、检查点计数的范围校验；
- create / normalize / mark active / record checkpoint / candidate 转换。

它不创建 Node、Timer、文件、线程或保存事务。

### `WorldSessionRecoveryService`

唯一异常会话标记所有者，负责：

- 开始进入世界时写入 `loading`；
- 世界正式可玩后切换为 `active`；
- 每次权威 `world_saved` 后更新检查点时间与数量；
- 正常返回菜单、世界启动失败、玩家忽略提示或世界删除后清除标记；
- 应用进程直接结束时不主动清除标记，使其成为下次启动证据。

### `CrashSafeStarWorldGame`

唯一应用退出所有者，负责：

- 设置 `SceneTree.auto_accept_quit = false`；
- 接收主菜单退出、暂停菜单安全退出和 `NOTIFICATION_WM_CLOSE_REQUEST`；
- 单飞调用 `CrashSafeServiceHub.prepare_application_quit()`；
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

标记写入失败不会阻止世界启动，因为它是恢复提示而不是权威世界数据；失败会进入有界诊断。

### 权威检查点

```text
manual / autosave / return_to_menu / system
→ 同一个 save_current()
→ SaveService.world_saved
→ marker checkpoint_count + 1
```

标记不会推断保存成功，也不会在保存前增加计数。

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
- Pause UI 显示失败；
- 退出被取消；
- 异常会话标记继续存在。

### 异常退出

进程崩溃、设备断电或被强制终止可能绕过正常清理。下一次启动读取当前主标记，若对应权威世界仍存在，则显示恢复卡片。

恢复按钮只执行：

```text
SaveService.load_world(marker.world_id)
```

因此最多回到最近一次成功的手动或自动检查点，而不会读取未完成内存状态。

## 严格主标记与误报防护

`AtomicJsonStore` 通常允许从 `.tmp` 或 `.bak` 恢复权威数据；世界存档需要这种自愈能力。但异常会话标记是**提示性证据**，旧 backup 可能属于已正常结束的前一个世界或前一个阶段。

因此这里采用 fail-closed 规则：

- 只接受当前 `session_recovery.json` 主文件；
- 主文件缺失或损坏时，不提升 `.tmp` / `.bak` 为恢复提示；
- 检测到非 primary 候选时清理全部 marker 文件；
- 权威 `world.json` 的恢复规则完全不变。

该取舍优先避免错误提示和恢复错世界。即使标记丢失，玩家仍可通过“继续游戏”或存档浏览器加载世界。

## 单一退出协调器

所有退出入口统一为：

```text
Main menu 退出 ─┐
Pause 保存并退出 ├─→ CrashSafeStarWorldGame.request_application_quit(source)
WM_CLOSE ────────┘
                        ↓
                CrashSafeServiceHub.prepare_application_quit()
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

主菜单在存在有效异常会话标记时显示：

- 世界名称；
- 地图 ID；
- 本次会话已成功完成的检查点数量；
- “恢复上次世界”；
- “忽略并清除”。

“忽略并清除”只删除提示，不删除世界。

恢复卡片出现时，它取代重复的普通“开始游戏”主 CTA；“地图选择”“存档 / 继续”等入口仍保留。这样在 1024×576 下保持命令面板有界，同时让键盘与控制器焦点优先落在真正的恢复动作上。

### 暂停菜单

新增“保存并退出游戏”：

- 点击后显示“正在执行最终保存”；
- 成功后回到主菜单并准备退出；
- 失败时显示“已取消退出”，保持暂停和世界所有权；
- 玩家可以释放空间、恢复权限后再次尝试。

### Windows 窗口关闭

关闭按钮与菜单命令共享完全相同的保存、失败和恢复语义。不会再由 Godot 默认自动接受关闭请求。

## 持久化与兼容性

不修改：

- `world.json` schema；
- `catalog.json`；
- settings；
- trash manifest；
- 方块 ID、Seed 或旧世界迁移；
- 自动保存 0/2/5/10/15 分钟设置；
- 15/60/300 秒失败退避；
- 保存检查点 12 条历史。

新增的 `session_recovery.json` 可以安全删除；删除只会失去异常会话提示，不会损坏任何世界。

## 永久测试

### 纯策略与模拟重启

`world_session_recovery_regression.gd` 验证：

- 严格 marker schema；
- loading → active；
- 真实保存后 checkpoint count；
- 销毁第一个服务并创建第二个服务的模拟重启；
- dismiss 不删除世界；
- corrupt primary 不提升旧 backup；
- 删除世界清除 stale marker；
- 所有 marker 字段不进入 `world.json`。

### 应用退出

`graceful_application_quit_regression.gd` 验证：

- Windows window-close 入口；
- 主菜单退出意图；
- 暂停菜单退出意图；
- 成功最终保存后释放世界；
- 最终保存失败时取消退出；
- 失败时保留 world ID、Pause、Runtime Health 和 marker；
- 恢复 SaveService 后可以安全重试；
- `auto_accept_quit` 在 teardown 后恢复。

### 紧凑分辨率与焦点

`session_recovery_ui_regression.gd` 在 1024×576 下验证：

- 恢复卡片和命令面板不越界；
- 恢复状态只收起重复的普通主 CTA；
- 原六命令合同仍保持，其他入口可用；
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
- 模拟重启回归；
- 应用退出回归；
- 1024×576 紧凑 UI 与焦点回归；
- 自动保存、保存时间线、世界会话、恢复、Runtime Health、UI 和 Runtime Soak 相邻回归；
- 三张真实桌面截图和 JSON Artifact。

最终合入仍必须通过仓库权威 Runtime、完整真实桌面矩阵与 **Windows Release** 实际导出、启动和退出资源检查。
