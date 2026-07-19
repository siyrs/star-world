# 全仓架构审计 · 第十一轮 · 2026-07-19

## 审计范围

本轮基于：

```text
master@69a6eb6732914067e61258cef8f72a4f2d1875a5
```

重新检查：

- ServiceHub 七层继承与功能参与者；
- 畜牧、动物吸引和动物产物；
- Inventory、ItemPickup、Furnace 和玩家反馈；
- 世界保存、离线推进和菜单/失败清理；
- 牧场、生命周期和全量 Runtime 测试；
- GitHub Actions 专项与 Windows Release 门禁；
- 当前产品路线图与实际主分支状态。

## 总体结论

探索运行时迁移完成后，牧场层成为最明显的下一处生命周期耦合。它已经具备成熟的领域服务和持久化合同，但组合方式仍停留在继承覆盖：

```text
RanchProgressionServiceHub
├─ 创建服务
├─ 接入交互
├─ 恢复状态
├─ 绑定玩家
├─ 激活
├─ 保存
├─ 诊断
├─ 玩家通知
└─ 清理
```

同时，产物服务按动物发送事件，而表现层也按动物发送 Toast 和音效。该设计在一只鸡的验收中正常，但会随牧场规模线性放大反馈噪声。

本轮处理顺序：

```text
生命周期状态所有权
→ 世界状态规范化
→ 公共兼容入口
→ 批量玩家反馈
→ 领域回归
→ 真实桌面
→ Windows Release
```

## 已处理问题

### P1 · 牧场 Hub 直接拥有领域实现

#### 现状

`RanchProgressionServiceHub` 直接预加载：

```text
AnimalAttractionService
AnimalProductService
AnimalProductStateMigration
```

并覆盖世界开始、游戏绑定、激活、保存、返回菜单、失败启动、诊断和退出。

#### 风险

- 新增牧场服务需要继续扩大继承层；
- 生命周期顺序只能靠阅读 `super` 链推断；
- 服务安装失败无法被组合根拒绝；
- 清理行为分散在 Hub 和服务 `_exit_tree()`；
- 领域反馈与保存路径耦合。

#### 处置

新增：

```text
RanchRuntimeParticipant
```

Hub 只保留公共字段、协调器注册和通用生命周期转发。

### P1 · 协调器位于过高的探索专用层

#### 现状

`ServiceHubFeatureCoordinator` 由 `ExplorationProgressionServiceHub` 创建。

#### 风险

直接实例化 `RanchProgressionServiceHub` 时无法获得参与者组合；牧场服务若迁移为参与者，就必须由探索子类反向拥有父领域。

#### 处置

协调器下移到牧场组合根：

```text
RanchProgressionServiceHub
→ FeatureLifecycle
→ ranch_runtime
```

探索子类继续注册：

```text
exploration_runtime
exploration_journal_rewards
```

生产 `service_hub.tscn` 入口不变。

### P1 · 世界迁移仍由具体 Hub 特判

#### 现状

探索 Hub 直接调用探索运行时参与者的：

```text
normalize_world_state
```

增加牧场参与者后，Hub 将需要再了解一套迁移器。

#### 风险

参与者越多，继承层越像领域迁移总表；迁移顺序没有统一诊断。

#### 处置

协调器新增可选阶段：

```text
normalize_world_state
```

所有实现该方法的参与者按注册顺序变换同一个状态。阶段进入有界诊断历史。

### P1 · 多动物产出造成反馈风暴

#### 现状

每个产物提交都执行：

```text
product_spawned
→ Toast
→ play_pickup
```

三十只鸡在接近同一时间完成生产，就可能产生三十条消息和三十次音效。

#### 风险

- 关键战斗和危险提示被挤出队列；
- 音效重叠；
- 大型牧场体验反而更差；
- UI 负载随动物数量线性增加。

#### 处置

参与者按帧合并产物事件：

```text
多个领域事件
→ 保留多个真实 ItemPickup
→ 一条结构化产量摘要
→ 一条 Toast
→ 一次音效
```

玩家消息最多展示三种产物，结构化 Snapshot 仍保留全部类型和数量。

### P1 · 动物吸引缺少结果反馈

#### 现状

玩家手持正确饲料时动物会跟随，但没有明确提示当前有多少只动物响应；切换物品后也没有结束反馈。

#### 处置

只对零边界变化提示：

```text
0 → N  开始跟随
N → M  静默
N → 0  停止跟随
```

避免逐只变化刷屏。

### P1 · 服务 setup 无法表达安装失败

#### 现状

两个牧场服务的 `setup()` 返回 `void`。

#### 风险

Registry 缺失或依赖为空时，组合根仍可能把半初始化服务公开给玩家和 UI。

#### 处置

`setup()` 改为返回 `bool`，校验：

- Registry 已加载；
- Inventory 有效；
- Spawner 有效；
- HusbandryService 有效；
- ItemRegistry 有效。

参与者只在两个服务都成功后完成安装。

### P1 · 长期信号只依赖场景退出断开

#### 现状

吸引服务连接 Inventory，产物服务连接 Husbandry。正常世界切换只调用 `clear()`，长期信号到场景退出才断开。

#### 处置

两个服务新增显式 `shutdown()`；参与者 Shutdown 统一：

- 清理运行状态；
- 断开信号；
- 清除依赖引用；
- 释放交互适配器的 ProductService。

## 兼容性审计

### 节点和字段

保持：

```text
animal_attraction_service
animal_product_service
/Services/AnimalAttractionService
/Services/AnimalProductService
```

探索公共字段和节点路径也保持不变。

### 存档

保持：

```text
animal_products.version = 1
```

没有增加新的存档顶级字段。批量通知、跟随数量和生命周期诊断均为瞬时状态。

### 产品数值

保持：

- 鸡蛋生产间隔 180 秒；
- 每只鸡最多 6 个待产物；
- 最多 6 小时离线推进；
- 14 格拾取生成半径；
- 鸡蛋和熟鸡蛋 ID；
- 熔炉配方；
- 物理拾取。

### 继承入口

保持：

```text
Gameplay
→ Tool
→ Character
→ Repair
→ Husbandry
→ Ranch
→ Exploration
```

本轮只减少覆盖实现，不删除兼容层。

## 测试发现与处置

### 1. 组合测试仍把生产根视为 Ranch 脚本

旧牧场测试通过脚本路径判断组合根。这种断言无法表达“生产入口是探索子类、牧场服务由父层参与者安装”。

新的门禁改为检查：

- `ranch_runtime` 参与者存在；
- 公共字段存在；
- 节点路径存在；
- 交互适配器引用权威 ProductService；
- 生命周期 Snapshot 有三名参与者。

### 2. 同步事件与玩家消息不是一一关系

领域服务仍必须逐动物发出 `product_spawned`，因为每个产物有独立 `husbandry_id` 和真实世界位置。测试不能通过减少领域事件伪造“批量”。

因此验收同时要求：

```text
3 个 product_spawned
3 个 ItemPickup
1 个 product_batch_announced
1 次音效
```

### 3. 清理需要验证引用而不只验证 active=false

服务停止处理不足以证明没有旧场景引用。新的回归和桌面验收检查：

```text
bound_player_id == 0
ProductService inactive
AttractionService inactive
失败启动后 current_world_id 为空
```

## 后续优化点

### P1 · Husbandry 核心仍在继承层

本轮只迁移牧场扩展。`AnimalHusbandryService` 和 `HusbandryInteractionAdapter` 仍由 `HusbandryProgressionServiceHub` 手工管理。

下一次迁移应先建立：

```text
husbandry_runtime
→ ranch_runtime depends on husbandry_runtime
```

并保留玩家实体交互端口。

### P1 · 多敌对事件需要同帧合并

探索危险参与者现在会响应每个 `ecology_changed`。多个敌对生物同一帧生成或清理时，虽然每次环境采样只有 125 个点，但仍可能重复刷新。

建议增加：

```text
same-frame refresh coalescing
+ refresh reason aggregation
+ immediate refresh budget diagnostics
```

### P1 · 多敌对前摇视觉预算

在增加第二只精英前，应真实验证：

- 三到五个预警圈；
- 焦点提示优先级；
- 目标查询次数；
- 同时死亡和多掉落收集；
- 危险事件合并。

### P2 · Machine Base

熔炉和修理台都已成熟，应提取小型机器能力，而不是继续复制：

```text
输入/输出
进度/阻塞
暂停/离线
序列化
只读 Snapshot
```

### P2 · 建筑连接形状

下一建筑闭环优先：

```text
门
→ 栅栏连接
→ 梯子
→ 玻璃板连接
```

形状、碰撞、预览和提交必须共享同一合同。

### P3 · CI 重复安装成本

专项工作流持续增加。应提取 reusable workflow，统一：

```text
checkout
→ setup Godot
→ strict import
→ static validators
→ domain scripts
→ optional desktop script
→ artifact
```

## 本轮交付

- `RanchRuntimeParticipant`；
- `RanchNotificationPolicy`；
- 协调器状态规范化阶段；
- 牧场组合根下移；
- Setup/Shutdown 服务合同；
- 跟随开始和结束反馈；
- 同帧产物批量摘要；
- 静态生命周期门禁；
- 领域回归；
- 双真实桌面验收；
- Ranch 与 ServiceHub CI 更新；
- 架构与审计文档。

## 合入标准

1. Godot 严格导入成功；
2. Ranch、ServiceHub 和相邻静态合同成功；
3. 牧场原有领域回归成功；
4. 新生命周期和批量策略回归成功；
5. 原有单鸡真实桌面流程成功；
6. 三鸡批量产出真实桌面流程成功；
7. 全量 Runtime 成功；
8. 全部既有桌面流程成功；
9. Windows Release 实际导出并启动；
10. 最终候选基于最新 `master` 且日志无脚本错误或资源泄漏。
