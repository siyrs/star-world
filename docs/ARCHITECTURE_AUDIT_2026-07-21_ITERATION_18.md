# 架构审计：Iteration 18

日期：2026-07-21

## 审计范围

本轮基于 Machine Capability 与相邻箱子自动化完成后的最新 `master`，继续检查长期运行、暂停一致性、状态所有权和下一阶段路线图，重点覆盖：

- Agriculture 是否仍在继承层重复拥有生命周期；
- Pause / Death 是否真实停止作物与土壤计时；
- 成熟收获是否真正复用背包原子事务；
- 异常世界存档能否导致无界作物/土壤恢复；
- 多作物同帧成熟是否造成反馈风暴；
- Character Snapshot 是否随农田数量线性膨胀；
- 迁移后是否保留旧世界、交互、公开字段和真实桌面体验。

## 发现 1：农业有两个生命周期所有者

迁移前：

```text
CharacterProgressionServiceHub
├─ 创建 AgricultureService
├─ 创建 AgricultureInteraction
├─ 注册 BlockInteraction Extension
├─ deserialize agriculture
├─ attach_world
├─ save agriculture
├─ clear agriculture
├─ 连接农业音效
└─ 注销 Extension
```

与此同时，项目已经使用 `ServiceHubFeatureCoordinator` 管理 Machine、畜牧、牧场和探索。

问题不是继承本身，而是农业的领域状态、世界引用、交互注册和保存都仍由 UI 组合继承层直接持有。世界启动失败、返回菜单和退出树各自需要手写清理，容易出现漏解绑或重复清理。

修复：新增 `AgricultureRuntimeParticipant`，Character 层只保留兼容字段。

## 发现 2：农业在真实暂停中继续运行

`GameplayServiceHub` 必须使用：

```gdscript
process_mode = Node.PROCESS_MODE_ALWAYS
```

因为暂停菜单、输入上下文和死亡 UI 仍要处理事件。

原农业服务只调用：

```gdscript
set_process(true)
```

没有覆盖继承的 Always 模式，因此 `SceneTree.paused = true` 时仍可能推进：

- 作物阶段；
- 土壤湿润剩余时间；
- 水源刷新计时；
- 成熟事件。

这是实现与产品语义不一致，而不是单纯性能问题。

修复：生产农业显式设置 `PROCESS_MODE_PAUSABLE`，并增加真实 SceneTree 和真实 Pause Menu 验收。

## 发现 3：成熟收获复制 Inventory 算法

旧流程：

```text
Agriculture 自己遍历背包槽位
→ 估算每种产物容量
→ 逐种 add_item
→ 中途失败时逐种 remove_item
```

问题：

- 重复维护最大堆叠和 metadata 合并规则；
- 与 `InventoryTransactionPolicy` 漂移；
- 多产物逐项提交会暴露中间状态；
- 回滚按 item_id 移除，不能证明恢复原槽位和 metadata；
- 预演与提交之间状态变化时缺少明确失败合同。

修复：使用现有 `can_transact_items` 与一次 `transact_items`。若最终提交竞争失败，恢复成熟世界方块，农业领域状态不变。

## 发现 4：农业存档恢复没有记录硬上限

旧反序列化会遍历保存中的所有 Crop 和 Soil 记录。即使正常世界规模有限，损坏或人工修改的 JSON 可以包含极大量记录，导致：

- 加载时间和内存无界；
- 世界绑定时大量方块写入；
- F3 快照复制完整状态；
- 离线推进遍历放大。

修复：严格 State Migration：

```text
Crops ≤ 4,096
Soils ≤ 4,096
Abs coordinate ≤ 1,048,576
Elapsed ≤ 6 hours
Manual hydration ≤ 6 hours
```

所有记录按稳定 key 排序后截断，未知字段与非法作物全部丢弃。

## 发现 5：成熟反馈缺少批量边界

多个作物可能因以下原因同帧成熟：

- 离线恢复；
- 大 Delta；
- 灌溉后同步推进；
- 肥料推进；
- 测试或管理命令。

逐作物 Toast 和音效会复制 Machine 与 Ranch 已经解决的反馈风暴。

修复：只收集进入最终阶段的事件，每帧末尾合并：

```text
最多 64 条事件
最多显示 3 种作物
一条消息
一次音效
```

离线恢复时 Participant 尚未 Active，因此不重播成熟历史。

## 发现 6：农业运行诊断复制完整领域状态

旧 `get_snapshot()` 直接返回 `serialize()`，包含完整 Crop/Soil Dictionary 和新的 `saved_at_unix`。F3 或 Character Snapshot 每次读取都会：

- 深复制所有农田记录；
- 产生与诊断无关的系统时间变化；
- 让快照成本随农田数量线性增长；
- 混淆“持久状态”与“运行诊断”。

修复：新增有界 Runtime Snapshot，只返回总数、成熟数、按作物类型计数、运行累计和事务统计。

## 最终结构

```text
CharacterProgressionServiceHub
├─ Equipment / Attribute / Combat
├─ agriculture_runtime (participant registration only)
└─ Rest

AgricultureRuntimeParticipant
├─ FertilizableAgricultureService (pausable)
├─ AgricultureInteractionAdapter
├─ AgricultureStateMigration
└─ AgricultureNotificationPolicy
```

Coordinator 现有六个参与者：

```text
machine_runtime
agriculture_runtime
husbandry_runtime
ranch_runtime -> husbandry_runtime
exploration_runtime
exploration_journal_rewards -> exploration_runtime
```

## 兼容性

保持：

- `agriculture` 世界存档字段；
- 旧 Crop ID、Stage Block 与位置 ID；
- `soil_moisture` 子结构；
- 右键开垦、浇水、播种、肥料和收获；
- 水桶 metadata 替换；
- 自动补种；
- 最多六小时离线成长；
- `hub.agriculture_service`；
- `hub.agriculture_interaction`；
- `AgricultureService` / `AgricultureInteraction` 节点路径；
- Block numeric ID 与 Seed 结果；
- 统一 Save Transaction 和 Windows Release 流程。

新增 Schema 2 只表示严格规范化后的农业根结构；旧版本和缺少 version 的存档仍通过白名单恢复。

## 验收要求

只有以下证据全部成功后允许合并：

1. Godot 严格导入；
2. Agriculture Runtime 静态合同；
3. 4,096 Crop / Soil 状态预算；
4. 异常时间、坐标、Stage 与未知字段规范化；
5. 原子成熟收获；
6. 背包满零写入；
7. 提交竞争世界回滚；
8. 真实 `SceneTree.paused` 冻结；
9. 六参与者组合与逆序清理；
10. 真实开垦、两种作物、Pause UI、成熟批次和鼠标收获；
11. 正式保存、返回菜单和完整重载；
12. 既有 Agriculture / Irrigation / Fertilizer 回归；
13. 全量 Runtime 和真实桌面矩阵；
14. Windows Release 实际导出与启动。

## 下一阶段建议

完成本轮后优先级更新为：

```text
连接型建筑统一形状合同
→ 门开关与双格状态
→ 栅栏和玻璃板邻接连接
→ 梯子真实攀爬
→ 大规模世界重建与保存压测
→ GitHub Actions reusable workflow
```

在连接型建筑中必须避免分别实现预览、碰撞、网格与保存方向。下一轮应先建立纯方向/邻接策略和单一形状合同，再增加可玩行为。
