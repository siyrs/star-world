# 牧场运行时生命周期与批量产出合同

## 目标

牧场运行时由两个高频、跨世界服务组成：

```text
AnimalAttractionService
AnimalProductService
```

它们需要访问背包、玩家、生物生成器、畜牧状态、交互提示、存档和玩家反馈。此前这些职责由 `RanchProgressionServiceHub` 通过多次生命周期覆盖手工维护。

本轮把牧场运行时迁移为一个显式参与者：

```text
ServiceHubFeatureCoordinator
└─ RanchRuntimeParticipant
   ├─ AnimalAttractionService
   └─ AnimalProductService
```

同时解决大量动物同周期产出时的提示和音效风暴。

## 状态所有权

### AnimalAttractionService

唯一拥有：

- 当前玩家引用；
- 当前被饲料吸引的动物集合；
- 共享刷新累计时间；
- 动物跟随目标的设置和清除。

该服务不保存世界状态。

### AnimalProductService

唯一拥有：

- 每个 `husbandry_id` 的生产计时；
- 待生成产物数量；
- 离线推进结果；
- 世界 `ItemPickup` 提交。

其持久化结构保持：

```json
{
  "animal_products": {
    "version": 1,
    "saved_at_unix": 0,
    "records": {}
  }
}
```

### RanchRuntimeParticipant

只拥有生命周期与表现聚合状态：

- 当前绑定玩家；
- 服务安装和激活状态；
- 跟随开始/停止通知计数；
- 同一帧产物汇总缓冲；
- 批量通知和单次音效诊断。

参与者不复制动物生产计时，也不保存第二份产物记录。

## 参与者生命周期

### install

```text
读取 Inventory / CreatureSpawner / HusbandryService / HusbandryInteraction
→ 创建 AnimalAttractionService
→ 校验 setup() 成功
→ 创建 AnimalProductService
→ 校验 setup() 成功
→ 保留公共字段和节点路径
→ 把 ProductService 接入 HusbandryInteraction
→ 连接 following_changed / product_spawned
```

任何依赖缺失或 Registry 加载失败都会使安装失败。协调器不会注册一个半初始化参与者。

### normalize_world_state

参与者使用既有 `AnimalProductStateMigration`：

```text
旧世界或缺失字段
→ animal_products.version = 1
→ 不凭空创建动物记录
```

协调器按参与者注册顺序依次执行世界状态规范化：

```text
ranch_runtime
→ exploration_runtime
→ begin_world
```

因此 Hub 不再知道每个领域的迁移实现。

### begin_world

- 停止运行状态；
- 清除上一世界玩家引用；
- 清除跟随目标和待发布批次；
- 清空上一世界服务状态；
- 恢复当前世界动物产物记录。

### attach_game

- 把当前玩家交给吸引服务；
- 把当前玩家交给产物服务；
- 记录只读玩家实例 ID。

### activate

激活顺序为：

```text
HusbandryService 已恢复并激活
→ AttractionService 激活
→ ProductService 同步 managed animals
→ 生成当前玩家附近的离线待产物
```

### save_into

参与者只向共享 Payload 写入：

```gdscript
payload["animal_products"] = product_service.serialize()
```

最终仍由 `SaveService` 一次原子写盘。

### snapshot_into

保持旧诊断字段：

```text
animal_attraction
animal_products
```

参与者自己的诊断位于：

```text
feature_lifecycle.participants.ranch_runtime
```

### clear / shutdown

`clear`：

- 停止两个服务；
- 清除当前世界产品记录；
- 清除动物跟随目标；
- 释放玩家引用；
- 丢弃尚未发布的批量摘要。

`shutdown` 额外：

- 断开 Inventory 信号；
- 断开 Husbandry 信号；
- 断开参与者信号；
- 从交互适配器移除 ProductService 只读模型。

## 组合根

协调器现在由 `RanchProgressionServiceHub` 创建，而不是由探索子层创建。

```text
HusbandryProgressionServiceHub
→ RanchProgressionServiceHub
   ├─ FeatureLifecycle
   └─ ranch_runtime
→ ExplorationProgressionServiceHub
   ├─ exploration_runtime
   └─ exploration_journal_rewards
```

这样直接实例化牧场组合根时仍能获得完整牧场服务；探索层只注册自己的参与者。

生产入口保持：

```text
scenes/ui/service_hub.tscn
→ exploration_progression_service_hub.gd
```

## 批量产出摘要

### 问题

`AnimalProductService` 按动物发出 `product_spawned`。当多只鸡在同一个更新周期产蛋时，旧 Hub 会逐条执行：

```text
Toast
→ 拾取音效
→ Toast
→ 拾取音效
→ ...
```

这会让大型牧场产生消息和音频风暴。

### 合并规则

参与者收到产物事件后只写入当前帧缓冲：

```text
product_item → 累计数量
husbandry_id → 唯一动物集合
```

第一次事件通过：

```gdscript
call_deferred("_flush_product_batch")
```

安排一次帧尾提交。同一同步更新中的后续事件只累计，不再次安排。

### 提交结果

例如：

```text
鸡 A → 鸡蛋 ×1
鸡 B → 鸡蛋 ×1
鸡 C → 鸡蛋 ×1
```

世界仍生成三个真实 `ItemPickup`，但玩家只收到：

```text
牧场产物已生成：鸡蛋 ×3（3 只动物）
```

并且只播放一次拾取音效。

### 有界显示

如果未来存在多种产物：

- 所有数量仍进入 `total_count`；
- 所有类型仍进入结构化 `products`；
- 玩家消息最多显示三种类型；
- 超出部分显示“等 N 类”。

## 跟随反馈

`RanchNotificationPolicy.following_transition()` 只对零边界变化产生消息：

```text
0 → N  有动物开始跟随
N → M  不提示
N → 0  动物停止跟随
```

这避免动物进入和离开半径时逐只刷屏，同时让玩家知道手中饲料是否生效。

## 兼容合同

保持不变：

- `animal_attraction_service` 公共字段；
- `animal_product_service` 公共字段；
- `/Services/AnimalAttractionService`；
- `/Services/AnimalProductService`；
- `HusbandryInteractionAdapter.product_service`；
- 鸡蛋生产间隔和最多六个待产物；
- 六小时离线推进上限；
- 14 格产物生成半径；
- `animal_products.version = 1`；
- 鸡蛋、熟鸡蛋和熔炉配方；
- 真实 `ItemPickup` 碰撞收集；
- 已有世界和物品 ID。

## 测试门禁

### 静态合同

```text
tests/developer_b/validate_ranch_lifecycle.ps1
```

验证组合根、参与者、服务 setup/shutdown、公共字段、节点路径、批量策略和全量测试入口。

### 领域回归

```text
tests/qa/ranch_runtime_lifecycle_regression.gd
```

验证：

- 跟随零边界策略；
- 多类型产物摘要；
- 三参与者组合；
- 迁移顺序；
- 同步事件合并；
- 单次音效预算；
- 保存与诊断；
- 清理和玩家释放。

### 真实桌面

```text
tests/qa/ranch_runtime_lifecycle_desktop_acceptance.gd
```

使用生产世界、玩家、Spawner、Husbandry、Inventory、ItemPickup 和 SaveService 验证：

```text
三只鸡被饲料吸引
→ 切换物品停止跟随
→ 三只鸡进入管理
→ 同周期产出三枚鸡蛋
→ 一条摘要和一次音效
→ 三个物理拾取
→ 正式保存
→ 返回菜单清理
→ 完整重载
→ 失败启动清理
```
