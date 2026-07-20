# ServiceHub 功能生命周期参与者合同

## 目标

生产 `service_hub.tscn` 继续保留既有公开继承入口：

```text
GameplayServiceHub
→ ToolProgressionServiceHub
→ CharacterProgressionServiceHub
→ RepairProgressionServiceHub
→ HusbandryProgressionServiceHub
→ RanchProgressionServiceHub
→ ExplorationProgressionServiceHub
```

已迁移领域不再分别覆盖世界开始、绑定、激活、保存、菜单清理、失败清理和退出。它们通过小型参与者加入一个共享协调器。

当前原则：

- 领域状态从继承层移出；
- 显式表达参与者依赖；
- 保留公共字段、节点路径和旧存档；
- 所有领域写入同一个保存 Payload；
- 正序启动、逆序清理；
- 新领域优先成为参与者，不继续扩大继承链。

## 当前生产结构

协调器由最底层、最通用的 `GameplayServiceHub` 创建：

```text
GameplayServiceHub
└─ ServiceHubFeatureCoordinator
   ├─ machine_runtime
   │  ├─ MachineRuntimeScheduler
   │  └─ FurnaceService
   ├─ husbandry_runtime
   │  ├─ AnimalHusbandryService
   │  └─ HusbandryInteractionAdapter
   ├─ ranch_runtime
   │  ├─ AnimalAttractionService
   │  └─ AnimalProductService
   ├─ exploration_runtime
   │  ├─ ExplorationDangerService
   │  └─ ProspectingService
   └─ exploration_journal_rewards
      ├─ ExplorationJournalService
      └─ ExplorationMilestoneRewardService
```

显式依赖：

```text
ranch_runtime → husbandry_runtime
exploration_journal_rewards → exploration_runtime
```

`machine_runtime`、`husbandry_runtime` 和 `exploration_runtime` 是相互独立的根参与者。

公共字段继续存在：

```text
machine_runtime
machine_runtime_participant
husbandry_service
husbandry_interaction
animal_attraction_service
animal_product_service
prospecting_service
exploration_danger_service
exploration_journal_service
exploration_reward_service
```

生产节点路径继续稳定：

```text
/Services/MachineRuntime
/Services/FurnaceService
/Services/AnimalHusbandryService
/Services/HusbandryInteraction
/Services/AnimalAttractionService
/Services/AnimalProductService
/Services/ProspectingService
/Services/ExplorationDangerService
/Services/ExplorationJournalService
/Services/ExplorationMilestoneRewardService
```

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

可选实现：

```gdscript
get_dependencies() -> Array[StringName]
normalize_world_state(state) -> Dictionary
get_lifecycle_snapshot() -> Dictionary
```

### get_dependencies

依赖 ID 必须：

- 非空；
- 不重复；
- 不是参与者自己；
- 注册时已经安装。

协调器明确返回：

```text
participant_dependency_missing
participant_dependency_cycle
```

当前注册顺序也是拓扑顺序；不得依赖某个父类 `_ready()` 的偶然赋值。

### install

只执行一次，负责：

- 校验依赖端口；
- 创建或绑定领域服务；
- 连接长期信号；
- 接入 UI、PlayerExperience 或共享 Scheduler；
- 设置兼容公共字段；
- 返回完整安装结果。

安装失败的参与者不会进入注册表。

### normalize_world_state

参与者按注册顺序规范化同一世界状态：

```text
machines
→ husbandry
→ animal_products
→ exploration
→ exploration_rewards
```

每个参与者只负责自己的领域；Coordinator 不包含领域规则。

规范化阶段记录一次有界诊断：

```text
normalize_world_state:machine_runtime,husbandry_runtime,...
```

阶段历史最多 48 条。

### begin_world

负责：

- 停止上一世界瞬时状态；
- 清除旧引用和延迟批次；
- 反序列化本领域；
- 建立地图、奖励或机器上下文；
- 建立不会重复提示的载入基线。

此阶段不启动实时模拟，也不产生新世界实时通知。

### attach_game

负责绑定生产世界、玩家和能力端口，例如：

```text
bind_entity_interaction_service
bind_prospecting_service
```

Machine Runtime 当前不需要玩家端口，但仍实现统一方法以保持合同一致。

重绑前必须显式解除旧玩家端口。

### activate

只有世界、玩家、相机、输入和 HUD 全部准备后调用。参与者在此阶段后才能：

- 启动共享或领域 Process；
- 恢复世界实体；
- 生成实时提示；
- 提交表现层批次。

重复激活必须幂等。

### save_into

参与者只向同一个可变 Payload 写入自己的字段：

```text
machines
husbandry
animal_products
exploration
exploration_rewards
```

禁止参与者单独调用 `SaveService.save_world()` 或打开世界文件。最终由 Gameplay Hub 完成一次原子写盘。

### snapshot_into

参与者向共享诊断中贡献兼容字段：

```text
machines
machine_runtime
husbandry
animal_attraction
animal_products
exploration
danger
exploration_journal
exploration_rewards
```

生命周期内部计数通过：

```text
feature_lifecycle.participants
```

提供，只读且不进入存档。

### clear

用于：

- 返回主菜单；
- 世界启动失败；
- 进入新世界前清理。

按依赖逆序执行：

```text
exploration_journal_rewards
→ exploration_runtime
→ ranch_runtime
→ husbandry_runtime
→ machine_runtime
```

无直接依赖关系的根参与者仍按照注册逆序清理，以保证后注册的上层功能先释放。

`clear` 必须主动解除：

- 玩家能力端口；
- 世界和玩家引用；
- 延迟表现批次；
- 运行计时；
- 对外部实体建立的长期信号；
- Machine Scheduler 的实时推进。

服务节点保留，供下一世界复用。

### shutdown

只执行一次，负责：

- 先执行 clear；
- 断开参与者建立的长期信号；
- 解除 UI 和 PlayerExperience 桥接；
- 调用领域服务显式 Shutdown；
- 关闭共享 Scheduler；
- 保证重复调用幂等。

## 协调器责任

`ServiceHubFeatureCoordinator` 负责：

- 唯一参与者 ID；
- 合同方法完整性；
- 已安装依赖检查；
- 正向生命周期顺序；
- 逆向清理与关闭顺序；
- 顺序化世界状态规范化；
- 单一保存 Payload；
- 单一诊断 Snapshot；
- 48 条有界阶段历史。

```text
normalize / begin / attach / activate / save / snapshot
→ 注册顺序

clear / shutdown
→ 注册逆序
```

协调器不负责：

- 机器槽位、配方和燃料；
- 畜牧和繁殖规则；
- 牧场产物规则；
- 探矿采样；
- 危险计算；
- 里程碑规则；
- 玩家反馈文案。

## 当前参与者责任

### machine_runtime

- Machine 状态严格迁移；
- 启动和停止共享 `MachineRuntimeScheduler`；
- 注册 Furnace 机器领域；
- 多机器完成反馈合并；
- `machines` 保存；
- `machines / machine_runtime` 诊断。

完整合同见 [MACHINE_BASE.md](MACHINE_BASE.md)。

### husbandry_runtime

- Husbandry 状态严格迁移；
- 受管动物恢复；
- 玩家实体交互端口；
- 喂养与繁殖事务；
- 动物死亡信号；
- 出生/成长批量反馈；
- `husbandry` 保存与诊断。

### ranch_runtime

依赖 `husbandry_runtime`：

- 饲料吸引；
- 持久产物；
- 产物提示只读模型；
- 多动物同周期产物批次；
- `animal_products` 保存；
- `animal_attraction / animal_products` 诊断。

### exploration_runtime

- 探矿和危险服务；
- 地图上下文；
- 玩家探矿端口；
- 昼夜、生态和攻击状态的帧级危险批次；
- 危险升级与恢复提示；
- `exploration` 保存；
- `exploration / danger` 诊断。

### exploration_journal_rewards

依赖 `exploration_runtime`：

- 日志派生视图；
- 奖励状态；
- J 键 UI 接入；
- 新奖励单次提示；
- 原子奖励领取；
- `exploration_rewards` 保存；
- 日志与奖励诊断。

## 生命周期顺序

### 新世界或继续世界

```text
GameplayServiceHub._begin_world
→ FeatureLifecycle.normalize_world_state
→ FeatureLifecycle.begin_world
→ 未迁移父级领域反序列化
→ Game 创建世界与玩家
→ FeatureLifecycle.attach_game
→ FeatureLifecycle.activate
```

Machine Runtime 在 `begin_world` 恢复 Furnace 数据，在 `activate` 后才开始共享推进。

### 保存

```text
未迁移领域写入 current_state
→ FeatureLifecycle.save_into(payload)
→ GameplayServiceHub 补充 world / player
→ SaveService 原子写入
```

所有参与者共享同一个 Payload。

### 返回主菜单

```text
完整保存成功
→ FeatureLifecycle.clear(return_to_menu)
→ 逆序解除日志、探索、牧场、畜牧和机器状态
→ 既有核心服务停止
→ 保留服务节点等待下一个世界
```

### 世界启动失败

```text
FeatureLifecycle.clear(world_start_failed)
→ 父级未迁移领域清理
→ 核心 Hub 回到菜单
```

### 场景退出

```text
最上层 Hub _exit_tree
→ 各继承层调用 super._exit_tree
→ GameplayServiceHub._exit_tree
→ FeatureLifecycle.shutdown
→ 逆序断开参与者信号和端口
```

Tool 和 Character 层必须继续传播 `super._exit_tree()`，否则根协调器无法执行最终 Shutdown。

## 兼容性

保持：

- `service_hub.tscn` 使用 `exploration_progression_service_hub.gd`；
- 七层继承入口；
- 既有 Husbandry、Ranch、Exploration 公共字段；
- 新增 Machine 公共字段但不删除旧字段；
- 原生产服务节点路径；
- 玩家实体交互与探矿绑定入口；
- `machines.version = 1 / machines.furnaces`；
- `husbandry.version = 1`；
- `animal_products.version = 1`；
- `exploration.version = 3`；
- `exploration_rewards.version = 1`；
- J 键、Machine Overlay 和输入上下文；
- Windows Release 行为。

## 测试

### 静态合同

```text
tests/developer_b/validate_machine_base.ps1
tests/developer_b/validate_service_hub_lifecycle.ps1
tests/developer_b/validate_husbandry_lifecycle.ps1
tests/developer_b/validate_ranch_lifecycle.ps1
```

验证：

- Coordinator 位于 Gameplay 根；
- 五个生产参与者；
- 两条显式依赖；
- 公共字段和节点路径；
- 继承层不直接拥有已迁移领域；
- Machine Scheduler、保存和批量反馈；
- 正序规范化和逆序清理；
- 退出链传播。

### 领域回归

```text
tests/qa/machine_base_regression.gd
tests/qa/service_hub_feature_lifecycle_regression.gd
tests/qa/husbandry_runtime_lifecycle_regression.gd
tests/qa/ranch_runtime_lifecycle_regression.gd
```

覆盖：

- 依赖缺失、重复 ID 和合同拒绝；
- Machine、Husbandry、Ranch、Exploration 正序启动；
- 五参与者共享保存；
- 完整逆序清理；
- 玩家端口解除；
- Scheduler 停止和重启；
- 角色诊断兼容字段。

### 真实桌面

永久门禁包括：

- 双 Furnace Machine Base Journey；
- Husbandry 多出生与成长；
- Ranch 多产物；
- Exploration 危险与探矿；
- Journal/Reward 领取；
- Multi-hostile 五敌对危险；
- 返回菜单、完整重载和失败启动。

### Windows Release

合并前必须经过生产导出、启动、画面、保存和退出资源检查。Headless 成功不能替代发行包验收。

## 后续迁移顺序

建议：

```text
Agriculture runtime participant
→ Equipment / Attribute participant
→ Repair participant
```

每次迁移必须保持字段、节点路径、存档 Schema、UI 输入、领域回归、真实桌面和 Windows Release，不得一次性重写整个继承链。
