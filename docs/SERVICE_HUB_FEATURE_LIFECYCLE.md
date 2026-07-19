# ServiceHub 功能生命周期参与者合同

## 目标

生产 `service_hub.tscn` 仍保留既有继承入口：

```text
GameplayServiceHub
→ ToolProgressionServiceHub
→ CharacterProgressionServiceHub
→ RepairProgressionServiceHub
→ HusbandryProgressionServiceHub
→ RanchProgressionServiceHub
→ ExplorationProgressionServiceHub
```

但已经迁移的领域不再分别覆盖世界开始、绑定、激活、保存、菜单清理、失败清理和退出。它们通过小型参与者加入一个共享协调器。

当前目标不是一次性删除全部继承，而是：

- 把真实领域状态从继承层移出；
- 显式表达参与者依赖；
- 保留公共字段和节点路径；
- 保持单次原子保存；
- 统一正序启动和逆序清理；
- 为后续渐进迁移建立稳定合同。

## 当前生产结构

协调器由最早完成迁移的 `HusbandryProgressionServiceHub` 创建：

```text
ServiceHubFeatureCoordinator
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
ranch_runtime
→ husbandry_runtime

exploration_journal_rewards
→ exploration_runtime
```

公共字段继续存在：

```text
husbandry_service
husbandry_interaction
animal_attraction_service
animal_product_service
prospecting_service
exploration_danger_service
exploration_journal_service
exploration_reward_service
```

所有服务仍是 Hub 的直接子节点，生产节点路径不变。

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

参与者可选实现：

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

协调器会明确返回：

```text
participant_dependency_missing
participant_dependency_cycle
```

当前注册顺序也是拓扑顺序；不得靠某个 `_ready()` 中的偶然赋值代替依赖声明。

### install

只执行一次，负责：

- 校验依赖端口；
- 创建或绑定领域服务；
- 连接长期信号；
- 接入 UI 或 PlayerExperience；
- 设置兼容公共字段；
- 返回安装是否完整成功。

安装失败的参与者不会进入协调器注册表。

### normalize_world_state

所有已安装参与者按照注册顺序规范化同一个世界状态：

```text
husbandry
→ animal_products
→ exploration
→ exploration_rewards
```

每个参与者只负责自己的领域，不得在 Coordinator 中加入领域规则。

规范化完成后记录一次：

```text
normalize_world_state:<participant ids>
```

阶段历史仍限制为 48 条。

### begin_world

负责：

- 停止上一世界瞬时状态；
- 清除旧引用；
- 反序列化自己的领域；
- 设置地图或奖励上下文；
- 建立不会重复提示的载入基线。

此阶段不启动模拟，也不产生实时玩家通知。

### attach_game

负责绑定生产世界和玩家能力端口，例如：

```text
bind_entity_interaction_service
bind_prospecting_service
```

重绑前必须显式解除旧玩家端口。

### activate

只在世界、玩家、相机和输入全部准备好后调用。参与者只有在此阶段之后才能：

- 开始 `_process`；
- 恢复世界实体；
- 生成实时提示；
- 提交表现层批次。

重复激活必须幂等。

### save_into

参与者只向同一个可变 Payload 写入自己的字段：

```text
husbandry
animal_products
exploration
exploration_rewards
```

禁止参与者单独调用 SaveService。最终仍由核心 Hub 完成一次原子写盘。

### snapshot_into

参与者向共享角色诊断中保留原字段：

```text
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

按注册顺序的逆序执行：

```text
exploration_journal_rewards
→ exploration_runtime
→ ranch_runtime
→ husbandry_runtime
```

依赖下游必须先释放，再清理上游状态。

`clear` 必须主动解除：

- 玩家能力端口；
- 世界和玩家引用；
- 延迟表现批次；
- 运行计时；
- 对外部实体建立的长期信号。

### shutdown

只允许执行一次，负责：

- 先执行 clear；
- 断开参与者建立的长期信号；
- 解除 UI 和 PlayerExperience 桥接；
- 调用领域服务显式 Shutdown；
- 保证重复调用幂等。

## 协调器合同

`ServiceHubFeatureCoordinator` 负责：

- 唯一参与者 ID；
- 合同方法完整性；
- 已安装依赖检查；
- 正向生命周期顺序；
- 逆向清理与关闭顺序；
- 顺序化世界状态规范化；
- 单一保存 Payload；
- 单一诊断 Snapshot；
- 有界阶段历史。

```text
normalize / begin / attach / activate / save / snapshot
→ 注册顺序

clear / shutdown
→ 注册逆序
```

协调器不负责：

- 畜牧规则；
- 产物规则；
- 探矿采样；
- 危险计算；
- 里程碑规则；
- 玩家反馈文案。

## 当前参与者责任

### husbandry_runtime

- 畜牧状态严格迁移；
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
- 昼夜/生态即时危险刷新；
- 危险升级和恢复提示；
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
HusbandryProgressionServiceHub._begin_world
→ FeatureLifecycle.normalize_world_state
→ FeatureLifecycle.begin_world
→ 既有父级 Hub 生命周期
→ Game 创建世界与玩家
→ FeatureLifecycle.attach_game
→ FeatureLifecycle.activate
```

### 保存

```text
FeatureLifecycle.save_into(current_state)
→ 父级未迁移领域写入 current_state
→ GameplayServiceHub 生成一个 Payload
→ SaveService 原子写入
```

### 返回主菜单

```text
完整保存成功
→ 既有核心服务停止
→ FeatureLifecycle.clear(return_to_menu)
→ 逆序解除日志、探索、牧场、畜牧状态
→ 保留服务节点，等待下一个世界
```

### 世界启动失败

```text
FeatureLifecycle.clear(world_start_failed)
→ 父级领域清理
→ 核心 Hub 回到菜单
```

### 场景退出

```text
FeatureLifecycle.shutdown
→ 逆序断开参与者信号和端口
→ 既有继承链退出清理
```

## 兼容性

保持：

- `service_hub.tscn` 使用 `exploration_progression_service_hub.gd`；
- 七层继承入口；
- 八个公共字段；
- 八个生产服务节点路径；
- 玩家实体交互与探矿绑定入口；
- `husbandry.version = 1`；
- `animal_products.version = 1`；
- `exploration.version = 3`；
- `exploration_rewards.version = 1`；
- 所有存档字段名；
- J 键和输入上下文；
- Windows Release 行为。

## 测试

### 静态合同

```text
tests/developer_b/validate_service_hub_lifecycle.ps1
tests/developer_b/validate_husbandry_lifecycle.ps1
tests/developer_b/validate_ranch_lifecycle.ps1
```

验证：

- 生产场景入口未改变；
- Coordinator 位于最早迁移的 Husbandry Root；
- 四个参与者；
- 两条显式依赖；
- 八个公共字段；
- 继承层不直接拥有领域实现；
- 正序规范化和逆序清理；
- 48 条诊断历史；
- 玩家端口和实体信号显式释放；
- 新回归进入全量入口。

### 领域回归

```text
tests/qa/service_hub_feature_lifecycle_regression.gd
tests/qa/husbandry_runtime_lifecycle_regression.gd
tests/qa/ranch_runtime_lifecycle_regression.gd
```

覆盖：

- 唯一 ID、合同、缺失依赖和自依赖；
- 四参与者注册和依赖图；
- 世界状态规范化顺序；
- 正序开始和逆序清理；
- 共享保存和诊断；
- 公共字段与节点路径；
- 玩家端口绑定/解绑；
- 批量畜牧与牧场反馈；
- 菜单、重载、失败和 Shutdown。

### 真实桌面

```text
tests/qa/service_hub_feature_lifecycle_desktop_acceptance.gd
tests/qa/husbandry_runtime_lifecycle_desktop_acceptance.gd
tests/qa/ranch_runtime_lifecycle_desktop_acceptance.gd
tests/qa/exploration_runtime_lifecycle_desktop_acceptance.gd
```

真实验证：

- 右键畜牧和探矿；
- J 键日志与真实领取；
- 多动物出生、成长和产物批次；
- 昼夜和生态危险刷新；
- 单次保存；
- 菜单逆序清理；
- 完整重载；
- 世界启动失败；
- 1024×576 截图和日志证据。

## 后续迁移顺序

下一批建议：

```text
同帧多生态事件合并
→ 多敌对可读性与性能预算
→ Agriculture / Rest
→ Machine Base
→ Repair 扩展
```

每批必须保留旧公共字段和调用入口。只有更多父领域完成参与者迁移后，再评估是否把协调器继续下移到更基础的组合根。
