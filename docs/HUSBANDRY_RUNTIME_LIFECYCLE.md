# 畜牧核心生命周期合同

## 目标

畜牧系统包含世界绑定、受管动物持久化、喂养事务、繁殖、幼崽成长、实体交互提示和动物死亡回调。它不能继续由 `HusbandryProgressionServiceHub` 的继承覆盖手工拼接，否则 Ranch、Exploration 等更上层功能无法声明真实依赖，清理顺序也只能依靠 `super` 调用推断。

当前生产组合为：

```text
HusbandryProgressionServiceHub
└─ ServiceHubFeatureCoordinator
   ├─ husbandry_runtime
   │  ├─ AnimalHusbandryService
   │  └─ HusbandryInteractionAdapter
   │
   ├─ ranch_runtime
   │  ├─ AnimalAttractionService
   │  └─ AnimalProductService
   │
   ├─ exploration_runtime
   │  ├─ ExplorationDangerService
   │  └─ ProspectingService
   │
   └─ exploration_journal_rewards
      ├─ ExplorationJournalService
      └─ ExplorationMilestoneRewardService
```

## 显式依赖

```text
ranch_runtime
→ husbandry_runtime

exploration_journal_rewards
→ exploration_runtime
```

注册时依赖必须已经安装。正常阶段按注册/依赖顺序执行：

```text
normalize_world_state
→ begin_world
→ attach_game
→ activate
→ save_into
→ snapshot_into
```

清理和关闭反向执行：

```text
exploration_journal_rewards
→ exploration_runtime
→ ranch_runtime
→ husbandry_runtime
```

这保证 AnimalProductService 在 AnimalHusbandryService 仍然可查询受管动物时先完成序列化和清理。

## HusbandryRuntimeParticipant 责任

### install

- 验证 Inventory、CreatureSpawner 和 PlayerExperienceCoordinator；
- 创建 `AnimalHusbandryService`；
- 创建 `HusbandryInteractionAdapter`；
- 验证 Registry 和服务端口；
- 保留公共字段：

```text
husbandry_service
husbandry_interaction
```

- 保留生产节点路径：

```text
/Services/AnimalHusbandryService
/Services/HusbandryInteraction
```

- 把实体交互适配器接回 PlayerExperienceCoordinator；
- 连接喂养、准备繁殖、拒绝、出生和成长信号。

### normalize_world_state

通过 `HusbandryStateMigration` 规范化：

```json
{
  "version": 1,
  "saved_at_unix": 0,
  "animals": {}
}
```

规则：

- 只接受 `HusbandryRegistry` 支持的鸡、牛和猪；
- 拒绝敌对物种；
- 拒绝非有限坐标；
- 记录字段使用严格白名单；
- `adult / baby` 之外的阶段回退为 adult；
- 所有计时器限制在 `0..86400` 秒；
- 生命值限制在正数有界范围；
- 旧世界缺失畜牧域时补齐空域；
- 不创建不存在的受管动物。

### begin_world

- 停止上一个世界；
- 取消待提交的表现批次；
- 显式解除旧玩家实体交互端口；
- 主动断开仍存活动物的死亡回调；
- 清除上一世界瞬时和持久内存状态；
- 反序列化当前世界畜牧域。

### attach_game

- 绑定当前 VoxelWorld 和玩家；
- 调用兼容入口：

```gdscript
player.bind_entity_interaction_service(husbandry_interaction)
```

- 重绑前先解除旧玩家端口。

### activate

- 恢复受管动物；
- 应用幼崽缩放、生命和显示名；
- 恢复受管动物死亡回调；
- 开始共享畜牧模拟。

### save_into

保存前先同步所有真实受管动物的：

- 位置；
- 生命；
- 阶段；
- 成长剩余时间；
- 繁殖冷却；
- 爱心剩余时间。

参与者只向共享 Payload 写入：

```gdscript
payload["husbandry"] = husbandry_service.serialize()
```

最终仍由 SaveService 一次原子写盘。

### snapshot_into

保留既有诊断字段：

```text
husbandry
```

参与者额外提供只读生命周期证据：

- installed / active / shutdown；
- service_ready / interaction_ready；
- bound_player_id；
- feed_count / ready_count / rejection_count；
- lifecycle_batch_count；
- newborn_total / grown_total；
- lifecycle_audio_count；
- dropped_lifecycle_events；
- pending_lifecycle_events；
- last_lifecycle_summary。

这些字段不写入世界存档。

### clear / shutdown

`clear` 必须：

- 停止畜牧模拟；
- 取消尚未提交的生命周期表现批次；
- 调用 `bind_entity_interaction_service(null)`；
- 主动断开所有受管动物死亡回调；
- 清除世界、玩家、Live Entity 和记录引用。

`shutdown` 还必须：

- 断开参与者建立的领域信号；
- 从 PlayerExperienceCoordinator 解除实体交互适配器；
- Shutdown 交互适配器；
- 释放服务依赖。

## 领域事务保持不变

本轮不修改：

- 饲料类型；
- 繁殖半径；
- 爱心持续时间；
- 繁殖冷却；
- 幼崽成长时间；
- 喂养成长缩减；
- 最大受管动物数；
- managed animal ID；
- 生物属性和掉落。

喂养事务仍然是：

```text
评估当前动物与饲料
→ 消耗一个选中饲料
→ 建立/更新稳定 husbandry_id
→ 计算繁殖或成长结果
→ 失败时恢复饲料和旧记录
→ 成功后发出领域事件
```

## 有界生命事件反馈

### 为什么需要批次

同一物理/逻辑周期可能发生：

- 两对或多对动物同时繁殖；
- 多只幼崽同时成年；
- 出生与成长同时发生。

领域服务继续发出每个真实事件：

```text
baby_born
animal_grew
```

参与者仅合并表现层：

```text
N 个同步领域事件
→ 最多 64 个待提交事件
→ 帧尾一次聚合
→ 一条 Toast
→ 出生批次最多一次 craft 音效
```

### 纯策略

`HusbandryNotificationPolicy` 输入：

```text
[{kind, result}, ...]
```

输出：

```text
message
severity
duration
audio
total_count
newborn_count
grown_count
animal_count
newborn_types
grown_types
```

玩家可见消息最多展示三种动物，完整计数仍保留在结构化摘要中。

示例：

```text
2 对牛同步繁殖
→ 2 个真实幼崽
→ 2 条 baby_born
→ 牧场生命更新：新生：幼年牛 ×2
→ 1 次 craft 音效
```

两只幼崽同步成年：

```text
2 条 animal_grew
→ 牧场生命更新：成年：牛 ×2
→ 0 次额外 craft 音效
```

## 兼容合同

以下保持不变：

- `service_hub.tscn` 入口；
- 七层公共继承入口；
- `husbandry_service` 和 `husbandry_interaction` 字段；
- 两个生产节点路径；
- `HusbandryPlayer.bind_entity_interaction_service`；
- 右键喂养；
- 实体上下文提示；
- `husbandry.version = 1`；
- 旧世界数据；
- managed animal ID；
- Ranch Product 对 husbandry_id 的引用；
- 玩家、世界、物品、方块和生态 Schema。

## 质量门禁

### 静态合同

`validate_husbandry_lifecycle.ps1` 检查：

- 协调器归属；
- 参与者注册；
- Ranch 依赖 Husbandry；
- 公共字段和节点路径；
- Hub 不直接拥有服务实现；
- 生命周期方法完整；
- 玩家显式解绑；
- 64 事件上限；
- 三种可见类型上限；
- 严格迁移器；
- 服务和适配器显式 Shutdown；
- 新测试进入永久门禁。

### 领域回归

`husbandry_runtime_lifecycle_regression.gd` 覆盖：

- 旧/损坏状态规范化；
- 敌对物种和非法坐标拒绝；
- 字段白名单；
- 计时器上限；
- 出生/成长批量策略；
- 四参与者依赖图；
- 公共服务端口；
- 玩家绑定/解绑；
- 批次与音效预算；
- 共享保存 Payload；
- 逆序清理和 Shutdown。

### 真实桌面

`husbandry_runtime_lifecycle_desktop_acceptance.gd` 使用生产：

```text
GameScene
VoxelWorld
HusbandryPlayer
CreatureSpawner
AnimalHusbandryService
HusbandryInteractionAdapter
InventoryService
SaveService
```

实际执行：

1. 创建真实世界；
2. 构建平坦牧场；
3. 创建两对牛；
4. 使用一次真实右键喂养；
5. 用生产事务完成两组繁殖；
6. 验证两只真实幼崽；
7. 验证一条出生摘要和一次音效；
8. 同步推进两只幼崽成年；
9. 验证一条成长摘要且无额外出生音效；
10. 保存六只受管动物；
11. 返回菜单并验证端口和信号释放；
12. 完整重载并验证六只动物只恢复一次；
13. 执行世界启动失败清理；
14. 输出 1024×576 截图和日志证据。
