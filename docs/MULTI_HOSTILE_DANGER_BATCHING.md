# 多敌对危险事件合并与来袭攻击可读性合同

## 目标

随着地图生态从单只普通僵尸扩展到五只敌对上限、条件精英和可躲避攻击前摇，危险系统必须同时满足两类要求：

1. 玩家能够理解多个敌人正在做什么；
2. 同一帧的大量生态和战斗事件不会线性放大环境扫描、HUD 刷新和诊断数据。

生产数据流现在为：

```text
DayNightService.phase_changed
CreatureSpawner.ecology_changed
CreatureSpawner.threat_changed
        ↓
ExplorationRuntimeParticipant.queue_danger_refresh
        ↓
DangerRefreshBatchPolicy
        ↓  每帧最多一次
ExplorationDangerService.refresh_for_events
        ↓
缓存环境样本 + 实时敌对/前摇上下文
        ↓
Danger Snapshot
        ↓
HUD 区域危险 + 全局来袭攻击提示
```

## 原问题

旧路径会在每个离散事件中直接调用：

```gdscript
ExplorationDangerService.refresh_now()
```

一次完整危险评估会读取最多 125 个世界方块。五只敌对同步生成时，Spawner 会连续产生多次生态变化；五只敌对同步进入前摇、取消、死亡或卸载后，也需要危险状态立即变化。

若每个事件都独立评估，则同一帧可能发生：

```text
10 个事件
→ 10 次危险评估
→ 最多 1,250 次重复世界方块读取
→ 多次等价 HUD 更新
```

单次操作虽然没有突破 125 样本上限，但总工作量仍随事件数量线性增长。

## 事件批次合同

### 支持的触发原因

```text
threat_changed   攻击状态、敌人死亡或敌人离树
 ecology_changed 生物数量、地图生态或生成上限变化
phase_changed    昼夜阶段变化
```

批次优先级为：

```text
threat_changed
→ ecology_changed
→ phase_changed
→ 其他扩展原因
```

优先级只影响诊断显示顺序，不改变最终危险计算。

### 帧边界提交

第一个事件只安排：

```gdscript
call_deferred("_flush_danger_refresh_batch")
```

同一主线程调用栈和同一帧后续事件只更新待处理原因集合。帧尾最多执行一次危险评估。

### 有界事件数量

```text
MAX_PENDING_DANGER_EVENTS = 64
```

前 64 个事件会进入批次统计。超出部分：

- 不创建额外评估；
- 不改变领域状态；
- 不影响真实敌人、攻击或掉落；
- 只增加 `dropped_danger_event_count` 诊断。

一次批次保留：

```text
event_count
coalesced_event_count
dropped_event_count
unique_trigger_count
triggers
trigger_counts
primary_trigger
trigger_key
```

例如：

```text
5 次 ecology_changed
+ 5 次 threat_changed
+ 1 次 phase_changed
= 11 个原始事件
→ 1 次实际评估
→ coalesced_event_count = 10
```

## 环境样本缓存合同

### 周期评估

危险服务继续以生产配置中的间隔运行周期评估：

```text
assessment_interval_seconds = 0.75
```

周期评估执行新的物理环境采样，以发现玩家移动、洞穴变化、岩浆变化或其他没有离散信号的世界变化。

### 事件评估

`refresh_for_events()` 只在以下条件全部成立时复用缓存：

- 已经存在成功环境样本；
- 世界和玩家仍然有效；
- 玩家仍位于同一个整数方块坐标；
- 本次刷新由离散事件批次触发。

复用内容只有：

```text
air_samples
lava_samples
total_samples
budget_exhausted
```

以下实时数据每次都会重新查询：

```text
昼夜阶段
敌对实体数量
敌对威胁权重
正在蓄力的攻击数量
精英蓄力数量
最快命中时间
地图生态 Snapshot
```

玩家跨入新方块时，事件刷新也必须执行新的环境采样。

### 采样预算

生产配置继续保持：

```text
max_samples = 125
```

诊断区分：

```text
assessment_count         逻辑危险评估次数
environment_scan_count   实际世界环境扫描次数
environment_reuse_count  复用缓存次数
environment_sample_total 累计方块读取数
max_samples_observed     任一物理扫描的最大样本数
```

`max_samples_observed` 不得超过 125。

## 多敌对前摇遥测

### Spawner 聚合

`CreatureSpawner` 监听生产生物的：

```text
attack_state_changed
died
tree_exiting
```

并提供：

```gdscript
get_nearby_hostile_windup_summary(position, radius)
```

结果包括：

```text
active_windup_count
elite_windup_count
windup_pressure
soonest_impact_seconds
source_counts
hostile_nodes_in_radius
visited_nodes
query_node_cap
scan_cap_reached
```

查询最多访问：

```text
MAX_HOSTILE_QUERY_NODES = 64
```

### 隐私和玩法边界

聚合结果不得包含：

```text
攻击者坐标
攻击者路径
精确实体位置数组
导航路线
自动瞄准目标
```

它只帮助玩家理解同时来袭的规模和时间，不替代视线、红色预警圈、移动和战斗判断。

### 已死亡实体

敌人调用 `die()` 后，在死亡动画和节点退出之前会暂时仍存在于场景树。

危险查询必须使用：

```gdscript
is_combat_target_available()
```

过滤已经死亡或排队销毁的敌人，避免 HUD 在死亡动画期间继续把它计算为有效威胁。

## 玩家反馈合同

危险 Snapshot 新增：

```text
windup_count
elite_windup_count
windup_pressure
soonest_impact_seconds
windup_urgency_label
windup_source_counts
```

HUD 在有前摇时显示：

```text
⚠ 来袭攻击 ×5（精英 ×1） · 最快 0.4 秒
```

该提示：

- 不要求玩家先瞄准某一只敌人；
- 不替代实体脚下红色预警圈；
- 不改变攻击命中范围或取消范围；
- 不拥有碰撞；
- 不阻挡鼠标或世界射线；
- 所有前摇结束后立即隐藏。

区域危险分仍只使用地图、深度、昼夜、敌对压力、岩浆和洞穴。前摇数量不重复增加危险分，避免同一敌人同时被“敌对压力”和“蓄力压力”双重计分。

## 掉落保护

`CreatureSpawner` 同时承载生物和死亡后生成的 `ItemPickup`。

旧 `clear_creatures()` 会删除全部子节点，可能在多敌对清场时误删玩家已经获得的物理掉落。

现在清理必须只处理：

```gdscript
child.is_in_group("creatures")
```

因此：

```text
三只敌人同帧死亡
→ 三个真实 ItemPickup
→ 同帧清除剩余敌人
→ 三个掉落继续存在
→ 玩家可物理拾取
→ 背包和存档恢复一次
```

## 存档合同

以下均为瞬时运行状态，不进入世界存档：

```text
待处理危险事件
批次统计
环境缓存
当前前摇数量
最快命中时间
红色预警圈
HUD 来袭攻击文本
```

世界继续只保存既有领域：

```text
exploration.version = 3
husbandry.version = 1
animal_products.version = 1
```

敌对实例和攻击前摇仍不持久化。

## 测试门禁

### 静态合同

```text
tests/developer_b/validate_multi_hostile_danger.ps1
```

验证：

- 64 事件硬上限；
- 帧尾合并；
- 三类触发原因；
- 125 样本生产预算；
- 环境缓存只在同一玩家方块复用；
- 64 节点敌对查询上限；
- 攻击、死亡和离树遥测；
- 无坐标泄漏；
- 掉落安全的生物清理；
- HUD 全局来袭攻击提示；
- 全量测试和专项工作流接入。

### 领域回归

```text
tests/qa/multi_hostile_danger_batch_regression.gd
```

覆盖：

- 10 个同步事件只评估一次；
- 70 个同步事件只评估一次，64 接受、6 丢弃；
- 清理取消已安排批次；
- 三个前摇、一个精英和最快命中聚合；
- 无攻击者坐标；
- 同方块环境缓存复用；
- 跨方块缓存失效；
- 125 样本上限；
- HUD 文本和鼠标透传。

### 真实桌面

```text
tests/qa/multi_hostile_danger_desktop_acceptance.gd
```

使用生产 `GameScene`、`VoxelWorld`、`CreatureSpawner`、五只真实僵尸、真实攻击状态机、危险服务、HUD、物理掉落、背包和保存服务，验证：

```text
五只同步生成
→ 一次危险评估
→ 五只同步蓄力
→ 五个红圈 + 一条全局提示
→ 一次危险评估
→ 五只同步取消
→ 一次危险评估
→ 三只同步死亡 + 两只卸载 + 昼夜变化
→ 一次危险评估
→ 三个掉落不被清场删除
→ 真实物理拾取
→ 保存、菜单、完整重载
```

最终 PR 还必须通过全量 Runtime、全部既有真实桌面流程和 Windows Release 实际导出启动。
