# 探索运行时生命周期合同

## 目标

把仍然由 `ExplorationProgressionServiceHub` 手工管理的探矿和危险运行时迁移到小型生命周期参与者，同时保持现有公共字段、节点路径、存档结构和玩家操作不变。

迁移后的组合结构：

```text
ExplorationProgressionServiceHub
└─ ServiceHubFeatureCoordinator
   ├─ exploration_runtime
   │  └─ ExplorationRuntimeParticipant
   │     ├─ ExplorationDangerService
   │     └─ ProspectingService
   └─ exploration_journal_rewards
      └─ ExplorationJournalRewardParticipant
         ├─ ExplorationJournalService
         └─ ExplorationMilestoneRewardService
```

日志和奖励显式依赖 `exploration_runtime`。协调器拒绝缺失依赖和自依赖，并在诊断 Snapshot 中暴露依赖图。

## 原问题

迁移前，顶层探索 Hub 同时负责：

- 创建危险和探矿服务；
- 连接扫描、拒绝和危险变化信号；
- 把危险服务交给 HUD；
- 恢复探索记录；
- 绑定玩家探矿入口；
- 激活危险轮询；
- 保存探索状态；
- 拼装探索和危险诊断；
- 返回菜单、启动失败和退出时清理；
- 发布扫描和危险反馈。

日志/奖励参与者又依赖 `prospecting_service`。这一依赖只由 `_ready()` 中的代码排列维持，没有可验证合同。

旧清理还只清空服务内部引用，没有显式调用：

```gdscript
player.bind_prospecting_service(null)
```

在返回菜单或启动失败的过渡窗口内，旧玩家对象可能继续持有已清理服务端口。

## 参与者责任

`ExplorationRuntimeParticipant` 是探矿和危险运行时的生命周期所有者。

### install

- 创建 `ExplorationDangerService`；
- 创建 `ProspectingService`；
- 校验两个 Registry；
- 保留生产节点名：
  - `ExplorationDangerService`
  - `ProspectingService`
- 保留 Hub 公共字段：
  - `exploration_danger_service`
  - `prospecting_service`
- 连接扫描、危险、昼夜和生态信号；
- 将危险服务连接到生产 HUD。

### begin_world

- 使用 `ProspectingStateMigration` 规范化探索状态；
- 清除旧世界和旧玩家引用；
- 恢复 `exploration.version = 3` 记录；
- 设置当前地图生态档案；
- 重置瞬时危险通知状态。

### attach_game

- 把真实 `VoxelWorld` 和玩家绑定到危险服务；
- 把真实 `VoxelWorld` 和玩家绑定到探矿服务；
- 调用玩家兼容入口：

```gdscript
bind_prospecting_service(prospecting_service)
```

### activate

- 启用有界危险刷新；
- 完成第一次生产危险评估。

### save_into

只向协调器提供的共享 Payload 写入：

```json
{
  "exploration": {
    "version": 3,
    "records": [],
    "last_result": {}
  }
}
```

参与者不能自行调用 `SaveService`。

### snapshot_into

继续提供兼容字段：

```text
exploration
danger
```

并通过生命周期 Snapshot 额外提供：

- 当前是否安装和激活；
- 服务是否有效；
- 绑定玩家实例 ID；
- 扫描成功/拒绝次数；
- 危险升级/缓解提示次数；
- 即时危险刷新次数；
- 最近刷新触发源。

### clear / shutdown

- 先由日志/奖励参与者逆序清理；
- 再显式解绑旧玩家探矿端口；
- 停止危险处理；
- 清除世界和玩家引用；
- 清除探索记录和危险 Snapshot；
- Shutdown 时断开自己建立的全部信号；
- HUD 解除危险服务引用。

## 显式依赖合同

参与者可以实现：

```gdscript
func get_dependencies() -> Array[StringName]
```

当前依赖图：

```text
exploration_runtime
└─ exploration_journal_rewards
```

注册 `exploration_journal_rewards` 前，协调器必须已经安装 `exploration_runtime`。

失败原因：

```text
participant_dependency_missing
participant_dependency_cycle
```

正常阶段按注册/依赖顺序执行：

```text
install
begin_world
attach_game
activate
save_into
snapshot_into
```

清理阶段逆序执行：

```text
exploration_journal_rewards.clear
→ exploration_runtime.clear
```

这样日志刷新和奖励状态总是在探矿记录被销毁之前结束。

## 即时危险刷新

危险服务仍保留 `0.75` 秒有界轮询，作为移动、深度、岩浆和洞穴变化的稳定基础。

同时，参与者监听两个高信号事件：

```text
DayNightService.phase_changed
CreatureSpawner.ecology_changed
```

事件发生后立即调用一次 `refresh_now()`，避免：

- 白天切到夜晚后 HUD 最多滞后一个轮询周期；
- 敌对生物生成或清场后危险提示短暂错误；
- 精英出现后危险权重延迟显示。

即时刷新不增加环境采样预算。每次评估仍受：

```text
horizontal_radius = 4
vertical_radius = 4
max_samples = 125
```

保护。

## 危险反馈闭环

原系统只提示危险上升，没有明确告诉玩家区域已经恢复。

新规则：

```text
safe / guarded
→ dangerous / severe
→ 发布危险提示

 dangerous / severe
→ safe / guarded
→ 发布“区域危险已缓解”
```

相同 Tier 重复刷新不会重复提示；只有真实 Tier 转换才会发布反馈。

玩家可见示例：

```text
危险等级：危险 · 夜晚、附近敌对生物 ×2

区域危险已缓解：警戒
```

## 兼容性

保持不变：

- `service_hub.tscn` 继续使用 `exploration_progression_service_hub.gd`；
- 七层 Hub 继承入口暂时保留；
- `prospecting_service` 公共字段；
- `exploration_danger_service` 公共字段；
- `exploration_journal_service` 公共字段；
- `exploration_reward_service` 公共字段；
- 四个生产节点路径；
- 玩家 `bind_prospecting_service` 入口；
- 右键探矿和 J 键日志；
- 校准仪地图限制和错误地图零冷却；
- 探索、奖励和世界存档 Schema；
- 探矿样本预算和不暴露坐标合同。

## 测试门禁

### 静态合同

`validate_service_hub_lifecycle.ps1` 验证：

- Hub 不再直接预加载危险、探矿和迁移实现；
- 两个参与者均注册；
- 四个公共字段保留；
- 节点路径和保存字段保留；
- 显式依赖存在；
- 缺失依赖和自依赖被拒绝；
- 旧玩家显式解绑；
- 昼夜和生态即时刷新；
- 危险缓解文案和有界诊断。

### 领域回归

`service_hub_feature_lifecycle_regression.gd` 覆盖：

- 依赖缺失和自依赖失败；
- 正序启动和逆序清理；
- 48 条历史上限；
- 两个生产参与者；
- 真实服务节点路径；
- 玩家绑定和解绑；
- 昼夜/生态即时刷新；
- 危险升级与缓解；
- 探矿、奖励、统一保存和重载；
- 世界启动失败清理。

### 真实桌面

`exploration_runtime_lifecycle_desktop_acceptance.gd` 使用生产：

```text
GameScene
VoxelWorld
ExplorationPlayer
DayNightService
CreatureSpawner
ExplorationDangerService
ProspectingService
SaveService
```

真实验证：

1. 创建星辰大陆世界；
2. 生产玩家绑定探矿服务；
3. 切换到夜晚；
4. 创建两只真实僵尸；
5. 危险立即升至危险或极高；
6. 清场并回到白天；
7. 危险立即降低并提示缓解；
8. 真实右键完成勘探；
9. 正式保存；
10. 返回菜单并验证旧玩家解绑；
11. 完整重载并恢复记录与绑定；
12. 失败启动路径再次清理；
13. 输出 1024×576 截图和日志证据。
