# ServiceHub 功能生命周期参与者合同

## 目标

随着系统增多，生产 `service_hub.tscn` 的脚本入口逐步形成了多层继承：

```text
GameplayServiceHub
→ ToolProgressionServiceHub
→ CharacterProgressionServiceHub
→ RepairProgressionServiceHub
→ HusbandryProgressionServiceHub
→ RanchProgressionServiceHub
→ ExplorationProgressionServiceHub
```

每一层都可能重复实现：

```text
_ready
_begin_world
attach_game
activate_gameplay
save_current
return_to_menu
handle_world_start_failed
get_character_snapshot
_exit_tree
```

本轮不进行一次性大重写，而是先建立小型参与者合同，并迁移依赖关系较清晰的“探索日志 + 里程碑奖励”。

## 生产结构

```text
ExplorationProgressionServiceHub
├─ ExplorationDangerService             仍由当前继承层管理
├─ ProspectingService                    仍由当前继承层管理
└─ FeatureLifecycle
   └─ ExplorationJournalRewards participant
      ├─ ExplorationJournalService
      └─ ExplorationMilestoneRewardService
```

`ExplorationJournalService` 和 `ExplorationMilestoneRewardService` 仍是 Hub 的直接子节点，以保留现有节点路径；参与者只拥有生命周期编排和反馈连接。

以下公共字段保持不变：

```gdscript
exploration_journal_service
exploration_reward_service
```

现有场景、测试、诊断和 UI 不需要改用新的服务定位方式。

## 参与者合同

每个参与者必须实现：

```gdscript
install(hub) -> bool
begin_world(state)
attach_game(world, player, sun, environment, ground_resolver)
activate()
save_into(payload)
snapshot_into(snapshot)
clear(reason)
shutdown()
```

### install

只执行一次，负责：

- 校验依赖；
- 创建或绑定领域服务；
- 连接信号；
- 接入 UI；
- 返回安装是否成功。

安装失败不会进入注册表。参与者 ID 必须唯一。

### begin_world

接收当前世界状态的只读副本，负责：

- 设置地图上下文；
- 反序列化参与者拥有的状态；
- 建立通知基线；
- 不启动世界模拟。

当前日志/奖励参与者在此刷新日志、设置地图奖励档案并恢复 `exploration_rewards`。

### attach_game

用于绑定生产世界、玩家、光照或地面解析端口。第一批迁移的日志/奖励领域不直接依赖世界对象，因此当前实现为空操作，但合同和顺序已通过测试固定。

### activate

世界、相机和输入全部准备好后调用。参与者只有在该阶段之后才允许产生实时玩家提示。

### save_into

把领域状态写入同一个可变保存 payload。禁止参与者单独调用 `SaveService`，以免出现多个部分成功的保存事务。

### snapshot_into

向角色和运行诊断的共享 snapshot 添加只读字段。日志和奖励继续使用原字段名：

```text
exploration_journal
exploration_rewards
```

### clear

在返回主菜单或世界启动失败时调用。按注册顺序的逆序执行，先清理依赖下游，再清理上游。

### shutdown

只允许执行一次；负责断开参与者自己建立的信号和 UI 绑定。重复调用必须幂等。

## 协调器合同

`ServiceHubFeatureCoordinator` 负责：

- 唯一参与者 ID；
- 合同方法完整性；
- 安装和正向生命周期顺序；
- 逆向清理与关闭顺序；
- 单一保存 payload；
- 单一诊断 snapshot；
- 有界阶段历史。

阶段历史最多保留 48 条，不允许诊断数据随运行时间无限增长。

```text
install / begin / attach / activate / save / snapshot
→ 注册顺序

clear / shutdown
→ 注册逆序
```

## 探索奖励可领取提示

原系统只有打开 `J` 日志后才能看到奖励变为可领取。参与者现在监听权威 `rewards_changed` snapshot：

```text
运行中首次从非 claimable 变为 claimable
→ 提示“探索里程碑可领取：…（按 J 查看）”
→ 播放一次 UI 提示音
```

为避免刷屏：

- 世界载入和反序列化期间不提示；
- `activate()` 时建立当前待领奖励基线；
- 相同 snapshot 重复刷新不提示；
- 已领取状态从基线移除；
- 世界重载不会再次宣布已有待领奖励；
- 多个里程碑同时完成时合并为一条数量提示。

## 生命周期顺序

### 新世界或继续世界

```text
ExplorationProgressionServiceHub._begin_world
→ 探矿状态迁移和恢复
→ FeatureLifecycle.begin_world
→ 日志刷新
→ 奖励地图上下文和 claimed 恢复
→ 既有父级 Hub 生命周期
→ Game 创建世界与玩家
→ attach_game
→ activate_gameplay
→ FeatureLifecycle.activate
```

### 保存

```text
探矿 serialize
→ participant.save_into(current_state)
→ 父级各领域写入 current_state
→ GameplayServiceHub 生成单一 payload
→ SaveService 原子写入
```

### 返回主菜单

```text
完整保存成功
→ 既有核心服务停止
→ FeatureLifecycle.clear(return_to_menu)
→ 日志和奖励 snapshot 清空
→ 保留服务节点，等待下一个世界
```

### 世界启动失败

```text
FeatureLifecycle.clear(world_start_failed)
→ 探矿和危险清理
→ 父级领域清理
→ 核心 Hub 回到菜单
```

### 场景退出

```text
FeatureLifecycle.shutdown
→ 断开奖励和 UI 信号
→ 既有继承链退出清理
```

## 兼容性

本轮保持：

- `service_hub.tscn` 仍使用 `exploration_progression_service_hub.gd`；
- 原有 Hub 继承入口；
- 日志和奖励公共字段；
- 日志和奖励节点路径；
- `exploration.version = 3`；
- `exploration_rewards.version = 1`；
- 地图印记、校准探矿仪和奖励数据；
- 保存字段名；
- J 键和输入上下文；
- Windows Release 行为。

## 测试

### 静态合同

```text
tests/developer_b/validate_service_hub_lifecycle.ps1
```

验证：

- 生产场景入口未改变；
- 公共字段保留；
- 继承层不再直接拥有日志/奖励实现脚本；
- 参与者完整实现九个生命周期和诊断方法；
- 协调器使用逆序 clear/shutdown；
- 48 条诊断历史上限；
- 单次奖励提示和载入基线存在；
- 全量测试入口包含生命周期回归。

### 领域回归

```text
tests/qa/service_hub_feature_lifecycle_regression.gd
```

覆盖：

- 唯一 ID 和不完整合同拒绝；
- 正向 begin、逆向 clear/shutdown；
- shutdown 幂等；
- 共享保存和诊断 payload；
- 生产 Hub 安装参与者；
- 公共字段和节点路径兼容；
- 单次奖励提示；
- 重复刷新不刷屏；
- 保存、返回菜单和完整恢复；
- 载入不重复通知；
- 启动失败清理。

### 真实桌面

```text
tests/qa/service_hub_feature_lifecycle_desktop_acceptance.gd
```

使用生产 `GameScene`、真实右键、真实 J 键和真实鼠标按钮，验证：

- 发现记录；
- 新奖励单次提示；
- 日志输入隔离；
- 真实领取；
- 正式保存；
- 返回主菜单清理；
- 完整世界重载；
- claimed 和物品不重复；
- 生产失败信号清理；
- 1024×576 截图证据。

## 后续迁移顺序

第一批迁移完成后，建议继续：

```text
探矿 + 危险
→ 牧场产物
→ 动物养殖
→ 农业与休息
→ 修理扩展
```

每批仍需保留旧公共字段和调用入口。只有当多个参与者稳定后，再考虑把协调器下移到基础 `GameplayServiceHub`，避免本轮直接修改所有父级生命周期顺序。
