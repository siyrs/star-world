# 全仓架构审计 · 第十二轮 · 2026-07-19

## 基线与范围

本轮从：

```text
master@5377d8891f0bc1970353be21e9ff322df7e2600b
```

开始，审查范围包括：

- ServiceHub 七层继承入口；
- `ServiceHubFeatureCoordinator`；
- 畜牧、牧场、探索三个已经或正在迁移的领域；
- 玩家能力端口；
- 世界状态迁移；
- 动物死亡信号；
- 同步多事件反馈；
- 畜牧和牧场领域测试；
- 真实桌面与 Windows Release 质量门禁。

审计原则仍然是先保护输入、保存、世界可见性、旧世界兼容和最终发行，再推进架构和功能。

## 总体结论

上一轮已经把 Ranch Runtime 迁为生命周期参与者，但畜牧核心仍由父级 Hub 手工管理，形成了一个新的组合断层：

```text
Husbandry Hub 手工拥有核心状态
        ↓ 隐式 _ready 顺序
Ranch Participant 使用 husbandry_service
```

这不是真正的显式依赖。继续迁移后，继承层会再次承担世界迁移、保存和清理；同时，规模化繁殖会产生与旧牧场产物相同的反馈风暴。

本轮完成以下闭环：

```text
HusbandryRuntimeParticipant
→ RanchRuntimeParticipant 显式依赖
→ 状态白名单迁移
→ 玩家与动物信号显式释放
→ 出生/成长批量反馈
→ 领域 + 真实桌面 + Windows Release 验收
```

## P0 守护项

### 1. 不改变畜牧规则与数值

本轮没有修改：

- 饲料 ID；
- 爱心时间；
- 繁殖冷却；
- 配对半径；
- 幼崽成长时间；
- 饲料成长缩减比例；
- 最大受管动物数；
- managed animal ID；
- 鸡蛋产物和离线预算。

原因：本轮目标是生命周期和反馈可扩展性，而不是重新平衡既有闭环。

### 2. 保留公共入口

保留：

```text
service_hub.tscn
husbandry_progression_service_hub.gd
ranch_progression_service_hub.gd
exploration_progression_service_hub.gd
```

保留字段：

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

保留对应生产节点路径。

### 3. 保存必须仍是单次原子事务

所有参与者只向 `current_state` 写入：

```text
husbandry
animal_products
exploration
exploration_rewards
```

最终仍只调用一次 SaveService。不存在每个参与者独立写盘。

## P1 已完成优化

### 4. 畜牧核心生命周期仍在继承层

旧 Hub 直接实现：

- 服务创建；
- 交互适配器创建；
- PlayerExperience 重配置；
- 反序列化；
- 世界与玩家绑定；
- 激活；
- 保存；
- 所有畜牧反馈；
- 失败、菜单和退出清理。

影响：

- Ranch 无法声明真实依赖；
- Coordinator 不能保证清理顺序；
- 直接实例化 Husbandry Root 没有参与者诊断；
- 每迁移一个新父领域都可能再次搬 Coordinator。

处置：协调器下移到 Husbandry Root，并注册 `husbandry_runtime`。

### 5. Ranch 依赖只靠父类 `_ready()` 顺序

旧 Ranch Participant 在安装时读取：

```text
hub.husbandry_service
hub.husbandry_interaction
```

但 `get_dependencies()` 返回空数组。

影响：若父类初始化顺序改变，可能安装失败；诊断仍会把 Ranch 视为独立功能；逆序清理无法表达为什么 Ranch 必须先结束。

处置：

```gdscript
func get_dependencies() -> Array[StringName]:
    return [&"husbandry_runtime"]
```

### 6. 旧玩家实体交互端口没有显式解绑

旧菜单清理只调用：

```text
AnimalHusbandryService.clear()
```

但玩家仍可能在场景过渡帧持有 `entity_interaction_service`。

处置：所有 begin/clear/shutdown 都显式执行：

```gdscript
bind_entity_interaction_service(null)
```

### 7. 动物死亡回调生命周期不完整

每个受管动物都会连接：

```text
creature.died → AnimalHusbandryService._on_creature_died.bind(husbandry_id)
```

旧 `detach_world()` 只清空 `_live`，未主动断开仍存活动物的回调。

影响：

- 场景过渡期间旧动物死亡可能回调已清理服务；
- 测试替身和未来对象池会放大问题；
- Shutdown 依赖节点销毁副作用。

处置：保存 `_live` 仍有效时逐个构造相同绑定 Callable 并断开，然后再清空引用。

### 8. 畜牧存档缺少独立严格迁移器

此前 SaveService 会补齐顶层字段，具体服务只在 deserialize 时做基本规范化。未知字段、非法坐标和敌对物种没有统一的参与者前置合同。

处置：新增 `HusbandryStateMigration`：

- 物种白名单；
- 有限坐标；
- 字段白名单；
- 计时器上限；
- 生命范围；
- 稳定顺序；
- 旧世界空域。

### 9. 同帧出生和成长反馈线性放大

例如两对牛同帧繁殖：

```text
baby_born A → Toast + craft sound
baby_born B → Toast + craft sound
```

领域事件本身是正确的，但表现层会挤占其它反馈。

处置：

```text
每个领域事件保持原样
→ Participant 缓存最多 64 个表现事件
→ call_deferred 帧尾汇总
→ 一条 Toast
→ 出生批次一次 craft sound
```

成长批次不播放 craft sound。

### 10. 旧测试固定参与者数量

上一轮新增 `ranch_runtime` 后，旧探索桌面用例从 2 改为 3。本轮如果继续修改所有硬编码数量但不验证依赖和公共端口，测试仍然脆弱。

处置：

- 数量更新为当前生产 4；
- 同时验证每个参与者 ID；
- 验证 Ranch → Husbandry 依赖；
- 验证 Journal → Exploration 依赖；
- 验证所有公共字段和节点路径；
- 验证完整逆序清理历史。

## P1 功能推进

### 11. 多动物生命事件摘要

玩家现在能收到：

```text
牧场生命更新：新生：幼年牛 ×2
```

或：

```text
牧场生命更新：成年：牛 ×2
```

这是表现层增强，不改变真实幼崽数量、位置或记录。

### 12. 有界反馈预算

新增明确预算：

```text
MAX_PENDING_LIFECYCLE_EVENTS = 64
MAX_VISIBLE_TYPES = 3
```

超过待处理事件上限时，领域状态仍然完整，仅丢弃额外表现事件，并在诊断中增加 `dropped_lifecycle_events`。

## 测试实际应发现的问题

本轮验收专门设计为发现：

1. `setup()` 返回 void 却被参与者当 bool；
2. 动态 `Variant` 直接赋给类型化 Dictionary/Array；
3. 玩家节点仍存在但服务端口已正确解绑；
4. 两对动物的位置导致错误跨组配对；
5. 同帧事件因 deferred 时机被拆成多个批次；
6. 出生音效按动物播放而不是按批次；
7. 重载时出生或成长事件被重新宣布；
8. 保存前未同步真实动物位置和生命；
9. Ranch 在 Husbandry 清理后才访问依赖；
10. 长期动物死亡回调未解除。

这些都已进入静态或运行测试，而不是只写在文档中。

## 本轮交付

- `HusbandryRuntimeParticipant`；
- `HusbandryStateMigration`；
- `HusbandryNotificationPolicy`；
- Husbandry Service 显式 Shutdown；
- Interaction Adapter 显式 Shutdown；
- Coordinator 下移到 Husbandry Root；
- Ranch 显式依赖 Husbandry；
- 四参与者诊断；
- 静态合同；
- 领域回归；
- 两组真实桌面验收；
- 全量 Runtime 和 Windows Release 验收；
- 生命周期合同与本审计报告。

## 下一阶段建议

### P1 · 多敌对事件合并与预算

当前 Exploration Runtime 对每个：

```text
phase_changed
ecology_changed
```

都立即评估危险。多只敌对同帧生成、死亡或卸载时，`CreatureSpawner` 可能发出多次生态变更。

下一步应建立：

```text
同帧生态事件收集
→ 原因集合去重
→ 每帧最多一次即时危险评估
→ 诊断原始事件数与实际刷新数
```

随后才能可靠验证三到五只敌对同时前摇的视觉与 CPU 预算。

### P2 · Machine Base

从 Furnace 提取：

- 输入输出能力；
- 进度；
- 阻塞；
- 燃料/能源端口；
- 离线推进；
- 位置型序列化；
- UI Snapshot。

### P2 · 建筑连接形状

继续推进：

- 门；
- 栅栏；
- 梯子；
- 玻璃板自动连接；
- 统一视觉、碰撞、预览和保存合同。

### P3 · CI 与规模平台

- reusable workflow；
- 大型牧场 24 动物压测；
- 同步繁殖/成长压力用例；
- 多敌对和多掉落 soak；
- 保存体积和载入时间报告。

## 合并门槛

只有以下全部成功才允许进入 `master`：

1. Godot 严格导入；
2. Husbandry/Ranch/ServiceHub 静态合同；
3. 新旧畜牧与牧场领域回归；
4. 两组真实畜牧桌面流程；
5. ServiceHub 和探索桌面流程；
6. 全量 Runtime 与领域矩阵；
7. 完整真实桌面输入/UI 矩阵；
8. Windows Release 实际导出和启动；
9. 日志无脚本错误、解析错误和资源泄漏；
10. 分支基于最新 `master` 且 behind=0。
