# Architecture Audit · 2026-07-29 · Iteration 51

## 审计范围

本轮从长期自动保存继续向应用级可靠性推进，审计：

- 主菜单退出与窗口关闭路径；
- `GameplayServiceHub.return_to_menu()` 的最终保存边界；
- 自动保存、保存恢复和检查点时间线能否形成异常退出后的玩家闭环；
- 主菜单继续游戏、存档浏览器与权威世界目录；
- 真实桌面、模拟重启与 Windows Release 门禁。

## 发现 1：UI 直接终止进程

原 `MainMenu._quit()` 同时：

```text
quit_requested.emit()
get_tree().quit()
```

UI 组件既发出退出意图，又直接终止进程。这使组合根无法：

- 判断当前是否仍有活动世界；
- 先执行最终保存；
- 在保存失败时取消退出；
- 把主菜单退出、暂停菜单退出和窗口关闭统一为一个事务边界；
- 对退出行为做单元与集成测试。

这是职责倒置：UI 应描述用户意图，应用生命周期必须由根组合对象拥有。

## 发现 2：窗口关闭绕过最终保存

项目此前没有关闭 `SceneTree.auto_accept_quit`，也没有处理 `NOTIFICATION_WM_CLOSE_REQUEST`。因此 Windows 标题栏关闭按钮可能直接结束进程，不经过：

```text
RuntimeHealthServiceHub.return_to_menu()
→ return_to_menu save reason
→ GameplayServiceHub.save_current()
→ FeatureLifecycle reverse cleanup
```

自动保存可以缩短数据损失窗口，但不能替代一次可失败、可观察的最终保存。

## 发现 3：可靠存档没有玩家可见恢复闭环

已有能力已经很强：

- `AtomicJsonStore` 原子写入；
- `.tmp` / `.bak` 自愈；
- 有界自动保存；
- 12 条保存检查点时间线；
- 当前世界本次进入隔离；
- Runtime Health 保存失败证据。

但异常退出后，下一次启动仍只是普通主菜单。玩家不知道：

- 上次哪个世界未正常结束；
- 最近一次权威检查点是否存在；
- 应该点击普通“继续游戏”还是去存档浏览器查找。

这是基础设施完整、产品闭环缺失。

## 发现 4：不能把运行会话状态塞进 world.json

最直接但错误的做法是给每个世界增加：

```text
last_session_active = true
```

这会导致：

- 正常世界保存与运行退出状态耦合；
- world schema 和迁移无意义增长；
- 崩溃发生时最后一次世界保存未必能更新该字段；
- 一个进程中的瞬时状态成为持久玩法状态；
- 恢复入口可能反向修改世界数据。

异常退出证据必须独立、极小、可删除，并且只能引用权威 world ID。

## 发现 5：旧 backup 误报恢复

`AtomicJsonStore` 对世界数据采用 primary → temporary → backup 的恢复顺序，这是正确的，因为世界数据应该尽最大努力自愈。

但异常会话标记的语义不同。每次 marker 更新都会留下上一版本 `.bak`；若玩家正常退出后主 marker 被外部损坏，而旧 backup 仍来自活动阶段，下一次启动若自动提升 backup，就会错误显示“上次未正常结束”。

因此恢复标记不能照搬世界数据的候选提升规则。

## 发现 6：退出失败必须保留所有权

原 `GameplayServiceHub.return_to_menu()` 已正确做到：最终保存失败时不清理世界。`RuntimeHealthServiceHub` 也只在 `current_world_id` 为空时 detach。

新应用退出能力必须复用这个边界，不能：

- 保存失败后仍调用 `SceneTree.quit()`；
- 提前清除 recovery marker；
- 提前解除 Runtime Health；
- 在 Pause UI 中假装退出成功。

## 决策

### 1. 单一退出协调器

新增 `CrashSafeStarWorldGame` 作为唯一应用生命周期所有者：

```text
MainMenu quit intent ─┐
Pause quit intent ────┼─→ request_application_quit(source)
WM_CLOSE ─────────────┘
```

它关闭 Godot 自动接受退出，并只在 `prepare_application_quit()` 成功后调用真正的 `SceneTree.quit(0)`。

### 2. 复用现有最终保存事务

`CrashSafeServiceHub.prepare_application_quit()` 不创建保存实现，而是调用：

```text
RuntimeHealthServiceHub.return_to_menu()
```

因此继续获得：

- `return_to_menu` 来源；
- 原 `save_current()`；
- 原 FeatureLifecycle 逆序清理；
- 原失败保留 world ID 和 Runtime Health 语义。

### 3. 独立严格会话标记

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

### 4. 标记只监听权威领域事实

检查点数量只在 `SaveService.world_saved` 后增加。不能在：

- save 请求发起时；
- UI 点击时；
- autosave due 时；
- pending 时；
- 保存失败时增加。

### 5. primary-only fail-closed

会话标记只接受当前 primary：

- primary 有效：展示恢复；
- primary 缺失或损坏：不展示；
- 仅 `.tmp` / `.bak` 有效：拒绝并清除所有 marker 文件；
- 世界数据自己的恢复策略不变。

这避免旧 backup 误报恢复。即使 marker 被丢弃，普通“继续游戏”和存档浏览器仍可访问世界。

### 6. 清除顺序

正常返回或安全退出必须满足：

```text
最终保存成功
→ world ownership released
→ current_world_id empty
→ 清 marker
```

失败时保持 marker。

### 7. 玩家入口

主菜单增加恢复卡片，但不增加普通 `_menu_buttons` 数量，避免破坏既有键盘/控制器导航合同。恢复卡片拥有独立主按钮，焦点导航优先进入恢复动作。

Pause 增加“保存并退出游戏”，失败时取消退出并明确展示原因。

## 不采用的方案

### UI 自己调用 save + quit

拒绝。会复制最终保存、绕过 Runtime Health 来源和 FeatureLifecycle。

### 只依赖自动保存

拒绝。自动保存限制损失窗口，但不能证明用户主动关闭应用时执行了最终事务。

### 把 active flag 写入 world.json

拒绝。崩溃时不能可靠更新，并污染世界 schema。

### 自动加载恢复世界

拒绝。恢复是玩家可见选择；自动进入可能加载错误世界或让用户无法先管理存档。

### 使用旧 backup 生成恢复提示

拒绝。提示性 marker 的旧 backup 可能来自已正常结束会话，误报风险高于漏提示风险。

### 创建第二份 crash snapshot 世界文件

拒绝。已有权威原子保存和自动保存，不应复制世界状态、迁移与恢复域。

## 测试设计

### 纯策略与模拟重启

- schema 白名单和范围；
- loading → active；
- 真实 `world_saved` 更新；
- 销毁服务 A、创建服务 B 的模拟重启；
- dismiss 只清提示；
- corrupt primary + valid backup fail-closed；
- 删除世界清 marker；
- world.json 无 marker 字段。

### 应用退出

- 主菜单退出意图；
- 暂停菜单退出意图；
- 模拟 Windows close notification；
- 成功时最终保存与世界释放；
- 失败时取消退出；
- 失败时 Pause、world ID、Runtime Health、marker 保留；
- 修复保存服务后重试成功；
- SceneTree auto quit teardown 恢复。

### 真实桌面与模拟重启

同一个测试进程中创建两个正式 `game.tscn` 实例：

1. 第一实例创建、游玩、修改背包并真实保存；
2. 不调用 return-to-menu，直接销毁第一实例，模拟异常进程生命周期；
3. 第二实例启动并读取磁盘 marker；
4. 截图恢复卡片；
5. 真实鼠标恢复世界；
6. 真实 Escape 与 Pause 安全退出；
7. 截图安全退出命令；
8. 真实鼠标执行最终保存；
9. 截图干净主菜单；
10. 验证世界可重载、背包完整和 marker 全清。

## 合入标准

只有以下全部成功才允许合入：

- 新静态架构合同；
- Godot 4.7 严格导入；
- 模拟重启领域回归；
- graceful application quit 回归；
- 真实桌面三阶段旅程；
- 原自动保存、保存时间线、世界会话、保存恢复、目录、Runtime Health 和 UI 回归；
- 权威 Runtime；
- 完整桌面矩阵；
- Windows Release 实际导出、启动和退出资源检查。
