# Agriculture Runtime Lifecycle

## 目标

农业不再由 `CharacterProgressionServiceHub` 同时负责创建、读取、世界绑定、保存、交互注册、音效与清理。生产组合统一为第六个显式生命周期参与者：

```text
ServiceHubFeatureCoordinator
├─ machine_runtime
├─ agriculture_runtime
├─ husbandry_runtime
├─ ranch_runtime
├─ exploration_runtime
└─ exploration_journal_rewards
```

农业仍保留原公开字段和节点路径：

```text
hub.agriculture_service
hub.agriculture_interaction
hub.agriculture_runtime_participant

/AgricultureService
/AgricultureInteraction
```

旧调用方、Player 与测试不需要通过场景路径重新查找服务。

## 所有权

```text
AgricultureRuntimeParticipant
├─ FertilizableAgricultureService
│  ├─ CropRegistry
│  ├─ SoilMoistureService
│  ├─ FertilizerRegistry
│  └─ Atomic Harvest Transaction
├─ AgricultureInteractionAdapter
├─ AgricultureStateMigration
└─ AgricultureNotificationPolicy
```

Participant 是以下行为的唯一组合所有者：

- 创建农业服务与交互适配器；
- 注册和注销方块交互 Extension；
- 规范化 `agriculture` 存档；
- 世界开始与反序列化；
- VoxelWorld 与 Inventory 绑定；
- 激活与暂停友好处理；
- 保存到共享 Payload；
- 写入有界角色诊断；
- 返回菜单、启动失败与退出清理；
- 农业音效和成熟批量反馈。

Character 继承层只保留兼容字段，不再直接写入农业 Dictionary 或管理农业信号。

## 生命周期

### Install

```text
Character Hub ready
→ 注册 agriculture_runtime
→ 创建 AgricultureService
→ 创建 AgricultureInteraction
→ 注册 BlockInteraction Extension
→ 连接农业事件
→ 发布兼容字段
→ 保持未激活
```

安装失败时必须移除已创建节点，不能留下半注册 Extension。

### Normalize / Begin

```text
加载世界
→ AgricultureStateMigration 严格白名单
→ 清空旧世界农业状态
→ 反序列化作物与土壤
→ 暂不推进实时 Process
```

### Attach / Activate

```text
绑定当前 VoxelWorld 与 Inventory
→ 应用最多六小时离线成长
→ 建立真实方块状态
→ activate
→ 开启可暂停 Process
```

离线恢复发生在 Participant 尚未 Active 时，因此不会重放“作物成熟”提示或音效。

### Save

农业只通过世界共享保存事务写入：

```json
{
  "agriculture": {
    "version": 2,
    "saved_at_unix": 0,
    "crops": {},
    "soil_moisture": {
      "version": 1,
      "soils": {}
    }
  }
}
```

Participant 不自行打开文件，不维护第二份农业存档。

### Clear / Shutdown

```text
Return to menu / failed start
→ deactivate
→ detach world
→ clear crops and soil
→ clear pending maturity feedback

Exit tree
→ disconnect agriculture signals
→ unregister interaction Extension
→ shutdown service
```

清理顺序由 Coordinator 逆序执行。当前完整顺序：

```text
exploration_journal_rewards
→ exploration_runtime
→ ranch_runtime
→ husbandry_runtime
→ agriculture_runtime
→ machine_runtime
```

## 暂停合同

Gameplay ServiceHub 使用 `PROCESS_MODE_ALWAYS`，使 UI 与输入可在暂停时工作。农业服务必须显式覆盖为：

```gdscript
process_mode = Node.PROCESS_MODE_PAUSABLE
```

因此以下状态暂停时保持不变：

- 作物阶段计时；
- 土壤手动湿润剩余时间；
- 水源重新评估周期；
- 农业运行累计时间；
- 成熟事件队列。

真实 Pause Menu、死亡暂停和 `SceneTree.paused = true` 使用同一合同。恢复后从原状态继续，不补算暂停期间时间。

## 原子成熟收获

旧实现自行计算背包容量，然后逐项 `add_item`；若中间失败再逐项 `remove_item`。这会复制 Inventory 规则，并在 metadata、堆叠策略或并发状态变化时产生回滚风险。

生产收获现在使用现有 Inventory Transaction：

```text
读取成熟作物与全部产物
→ can_transact_items({}, additions)
→ 容量不足：作物和背包均不变
→ 写入自动补种或 Air 世界状态
→ transact_items({}, additions) 一次提交
→ 成功后更新农业领域状态
```

若预演后背包状态发生变化，最终事务失败：

```text
恢复成熟作物方块
保持农业领域状态
不发布 crop_harvested
返回 inventory_race
```

成功事件包含实际提交的 Transaction 结果，便于测试与诊断。

## 严格存档规范化

`AgricultureStateMigration` 使用白名单重建状态：

| 项目 | 上限 |
|---|---:|
| 作物记录 | 4,096 |
| 土壤记录 | 4,096 |
| 坐标绝对值 | 1,048,576 |
| 作物累计阶段时间 | 6 小时 |
| 手动湿润剩余时间 | 6 小时 |

规范化规则：

- 只接受 CropRegistry 中存在的作物；
- 重新根据位置生成 `crop@x,y,z` 与 `soil@x,y,z`；
- 丢弃非法、重复和越界坐标；
- Stage 限制到注册作物的最终阶段；
- NaN / INF 时间归零；
- 负保存时间归零；
- 未知根字段和记录字段全部丢弃；
- 记录按稳定 key 顺序截断，避免非确定恢复。

## 成熟反馈批量化

多块作物在同帧成熟时，不为每块农田创建 Toast 和音效。

```text
crop_stage_changed × N
→ 只收集进入最终阶段的事件
→ 每帧末尾一次 flush
→ AgricultureNotificationPolicy 聚合
→ 一条玩家消息
→ 一次 pickup 音效
```

预算：

| 项目 | 上限 |
|---|---:|
| 待处理成熟事件 | 64 |
| 消息中显示的作物类型 | 3 |

超过三种时消息只显示前三种并附加“另有 N 种作物”。超过 64 条的事件计入诊断，但不扩大队列。

## 运行诊断

`get_runtime_snapshot()` 只返回聚合信息：

```text
active / shutdown / world_attached
process_mode / processing
crop_count / mature_crop_count / crop_counts
soil_count
runtime_process_count / runtime_elapsed_seconds
atomic_harvest_count / rejection_count
last_atomic_harvest
```

它不会把完整 `_crops` 或 `_soils` Dictionary 复制到 F3 / Character Snapshot。

Participant 另提供：

```text
maturity_batch_count
matured_crop_total
maturity_audio_count
dropped_maturity_events
各类农业交互音效计数
last_maturity_summary
```

这些诊断均为当前进程瞬时状态，不进入世界存档。

## 永久测试

### 静态合同

```text
tests/developer_b/validate_agriculture_runtime.ps1
```

检查生命周期所有权、暂停模式、原子事务、状态预算、反馈预算、兼容字段和 CI 接线。

### 领域回归

```text
tests/qa/agriculture_runtime_lifecycle_regression.gd
```

覆盖：

- 4,096 作物与土壤上限；
- 严格白名单和异常时间；
- 成熟通知聚合；
- 背包满零写入；
- 一次原子收获；
- 提交竞争回滚；
- 真实 `SceneTree.paused` 冻结和恢复；
- 六参与者生产组合；
- 保存、菜单清理、完整重载和不重播提示。

### 真实桌面

```text
tests/qa/agriculture_runtime_desktop_acceptance.gd
```

通过真实 GameScene 执行：

```text
真实 VoxelWorld
→ 鼠标右键开垦两块土地
→ 播种小麦和胡萝卜
→ Esc 打开真实 Pause Menu
→ 验证农业运行时间冻结
→ 恢复并推进成熟
→ 验证一条成熟批次
→ 真实中心射线收获
→ 原子产物和自动补种
→ 1024×576 截图
→ 正式保存
→ 返回菜单
→ 完整重载
→ 无产物复制、无提示重播
```

专项工作流同时重跑既有农业、灌溉、肥料和 ServiceHub 生命周期验收。完整 Godot 与 Windows Release 仍是合入 `master` 的最终门禁。
