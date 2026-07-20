# 多敌对危险事件合并与来袭攻击可读性合同

## 目标

随着地图生态从单只普通僵尸扩展到五只敌对上限、条件精英和可躲避攻击前摇，危险系统必须同时满足：

1. 玩家能够理解多个敌人正在做什么；
2. 同一帧的大量生态和战斗事件不会线性放大环境扫描、HUD 更新和诊断数据；
3. 优化只减少重复评估，不吞掉攻击、死亡、掉落、背包或保存等领域结果。

生产数据流：

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

一次完整危险评估会读取最多 125 个世界方块。五只敌对同步生成、进入前摇、取消、死亡或卸载时，可能在同一帧内重复读取同一环境。

```text
10 个事件
→ 10 次危险评估
→ 最多 1,250 次重复世界方块读取
→ 多次等价 HUD 更新
```

单次虽然受 125 样本保护，但总量仍随事件数线性增长。

## 事件批次合同

### 支持的触发原因

```text
threat_changed   攻击状态、敌人死亡或敌人离树
ecology_changed  生物数量、地图生态或生成上限变化
phase_changed    昼夜阶段变化
```

批次诊断优先级：

```text
threat_changed
→ ecology_changed
→ phase_changed
→ 其他扩展原因
```

优先级只影响诊断顺序，不改变危险计算。

### 帧边界提交

第一个事件只安排：

```gdscript
call_deferred("_flush_danger_refresh_batch")
```

同一主线程调用栈和同一帧的后续事件只更新待处理原因集合。帧尾最多执行一次危险评估。

### 有界事件数量

```text
MAX_PENDING_DANGER_EVENTS = 64
```

前 64 个事件进入批次统计。超出部分：

- 不创建额外评估；
- 不改变真实敌人、攻击、死亡或掉落；
- 不影响背包或存档；
- 只增加 `dropped_danger_event_count` 诊断。

批次保留：

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

### 兼容信号

旧监听者仍可使用：

```gdscript
immediate_danger_refreshed(trigger, snapshot)
```

一个批次只进行一次评估，但会对批次中的每个**唯一原因**各发一次旧信号，并复用同一个 Snapshot。例如混合批次会依次发出：

```text
threat_changed
 ecology_changed
phase_changed
```

新的结构化信号：

```gdscript
danger_refresh_batch_completed(summary)
```

每个批次只发一次。

## 环境样本缓存合同

### 周期评估

危险服务继续以生产配置间隔运行：

```text
assessment_interval_seconds = 0.75
```

周期评估执行新的物理环境采样，以发现玩家移动、洞穴变化、岩浆变化和其他没有离散信号的世界变化。

### 事件评估

`refresh_for_events()` 只在以下条件全部成立时复用缓存：

- 已存在成功环境样本；
- 世界和玩家仍有效；
- 玩家仍位于同一个整数方块坐标；
- 本次刷新由离散事件批次触发。

复用内容仅包括：

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

只访问敌对候选，最多：

```text
MAX_HOSTILE_QUERY_NODES = 64
```

`ItemPickup`、被动生物和其他无关子节点不消耗该敌对查询预算。

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

区域危险分仍只使用地图、深度、昼夜、敌对压力、岩浆和洞穴。前摇数量不重复增加危险分，避免同一敌人被双重计分。

## 种群清理与世界清理

`CreatureSpawner` 同时承载生物和死亡后生成的 `ItemPickup`。两类清理需求不能共用同一语义。

### 完整世界生命周期清理

```gdscript
clear_creatures()
```

用于：

- 进入新世界；
- 返回主菜单；
- 世界启动失败；
- 清理旧世界全部瞬时节点。

它会删除生物、旧世界掉落和其他 Spawner 瞬时子节点，防止跨世界泄漏。

### 运行时种群清理

```gdscript
clear_creature_population()
```

用于当前世界中的种群重置或测试清场。它只处理：

```gdscript
child.is_in_group("creatures")
```

因此：

```text
三只敌人同帧死亡
→ 三个真实 ItemPickup
→ 同帧清除剩余两只敌人
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
- 兼容信号和结构化批次；
- 125 样本生产预算；
- 环境缓存只在同一玩家方块复用；
- 64 敌对节点查询上限；
- 攻击、死亡和离树遥测；
- 无坐标泄漏；
- 完整世界清理与掉落安全种群清理双入口；
- HUD 全局来袭攻击提示；
- 全量测试和专项工作流接入。

### 领域回归

```text
tests/qa/multi_hostile_danger_batch_regression.gd
```

覆盖：

- 10 个同步事件只评估一次；
- 旧兼容信号保留三个唯一原因；
- 70 个同步事件只评估一次，64 接受、6 丢弃；
- 清理取消已安排批次；
- 三个前摇、一个精英和最快命中聚合；
- 无攻击者坐标；
- 敌对查询不被掉落占用预算；
- 种群清理保留掉落；
- 世界清理删除掉落；
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
→ 三只同步死亡 + 两只运行时卸载 + 昼夜变化
→ 一次危险评估
→ 三个掉落不被种群清理删除
→ 真实物理拾取
→ 保存、菜单、完整重载
```

最终 PR 还必须通过全量 Runtime、全部既有真实桌面流程和 Windows Release 实际导出启动。
