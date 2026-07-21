# 架构审计：Iteration 17

日期：2026-07-21

## 审计范围

本轮从上一阶段的 Machine Base、Stonecutter 和 Machine Capability 出发，重点检查：

- 机器能力是否已经形成可被新功能消费的闭环；
- 下一步自动化会不会重新引入具体机器分支；
- 容器是否具备与玩家背包相同的原子事务边界；
- 大量机器是否会形成新的全局扫描；
- 自动化运行状态是否会污染世界存档；
- 玩家是否能够从世界结构直接理解自动化规则。

## 发现 1：路线图仍把已完成的 Capability 列为下一阶段

Machine Capability 已经提供：

```text
get_machine_capabilities
can_insert
can_extract
insert_transaction
extract_transaction
```

继续停留在“建立能力合同”不会形成新玩家价值。下一步应当通过一个真实功能验证能力层能否被跨机器消费。

本轮选择现有箱子作为最小自动化载体，而不是先增加第三种机器或大型物流网络。

## 发现 2：现有箱子只有便捷搬运，没有原子事务端口

玩家手动点击箱子时允许尽量搬运，这适合 UI，但自动化需要完整成功或零写入。

旧容器 API 只有：

```text
add_item
remove_from_slot
transfer_from_inventory
transfer_to_inventory
```

如果下方箱子只剩部分空间，自动化可能难以保证机器扣除数量与箱子接收数量完全一致。

修复：`ContainerStorageService` 复用 `InventoryTransactionPolicy`，新增：

```text
can_transact_items
transact_items
```

从而允许 Machine Router 的提取 Proxy 先预演完整加入，再一次提交。

## 发现 3：只限制处理数量仍可能遍历全部机器

一个看似有界的实现可能这样工作：

```text
每 0.5 秒获取所有 Furnace ID
→ 获取所有 Stonecutter ID
→ 排序全部 ID
→ 最后只处理前 16 台
```

实际处理有上限，但目录读取和排序仍随世界机器总数线性增长。

修复：Automation Service 在安装时绑定机器领域的创建/变化与移除信号，维护有序候选缓存。世界恢复后只重建一次，常规周期不再重新枚举完整机器目录。

## 发现 4：直接增加自动化管理器会复制生命周期

不合理方案：

```text
AutomationManager
├─ 自己的 Timer
├─ 自己的机器目录
├─ 自己的保存文件
├─ 自己的世界扫描
└─ 自己的输入输出实现
```

修复：自动化实现为 Machine Runtime 的第三个 Scheduler Domain：

```text
furnace
stonecutter
automation
```

它没有独立 Timer，不写文件，不增加 FeatureLifecycle 参与者数量，也不改变机器存档 Schema。

## 发现 5：远距离物流会过早扩大状态空间

电网、管道、路径搜索和跨 Chunk 网络都会引入：

- 网络拓扑持久化；
- Chunk 加载边界；
- 路径失效；
- 大范围扫描；
- 迁移和修复工具；
- 新的 UI 与调试成本。

当前产品阶段不需要这些复杂度。

修复：规则固定为机器正上方箱子供料、正下方箱子收货。空间关系本身就是玩家 UI，不需要新增连接器物品、管道方块或配置面板。

## 发现 6：自动化反馈容易形成新的 Toast 风暴

逐物品或逐周期提示会重复上一阶段已经解决的完成反馈问题。

修复：只在某台机器当前世界第一次发生真实自动搬运时提示一次。常规周期只记录结构化诊断，不播放逐物品音效。

## 最终设计

```text
VoxelWorld physical blocks
        │
        ├─ chest above
        │     ↓
MachineAutomationService
        │     ↓ MachineInteractionRouter
        ├─ FurnaceService
        └─ StonecutterService
              ↓
        chest below
```

预算：

```text
0.5 秒 / 周期
16 台机器 / 周期
64 件物品 / 周期
8 件 / 事务
256 个容器槽位 / 周期
128 次事务探测 / 周期
```

## 兼容性

保持不变：

- Machine Runtime Scheduler；
- Furnace 与 Stonecutter 节点路径；
- `machines.version = 1`；
- `machines.furnaces`；
- `machines.stonecutters`；
- `containers.version = 1`；
- 现有箱子 UI 与手动整组搬运；
- Machine Capability Schema 1；
- 世界 Block numeric ID；
- 存档事务和 Windows Release 流程。

## 验收要求

只有以下证据全部成功后才允许合并：

1. Godot 严格导入；
2. 静态预算和架构合同；
3. 原子箱子事务回归；
4. Furnace / Stonecutter 自动输入输出回归；
5. 20 台机器 round-robin；
6. 真实世界方块与真实箱子 UI；
7. 正式保存、菜单清理和完整重载；
8. 全量 Runtime 与领域回归；
9. 完整真实桌面矩阵；
10. Windows Release 实际导出和启动。

## 下一阶段建议

完成本轮后，优先级调整为：

```text
Agriculture Runtime Participant
→ 门、栅栏、梯子和玻璃板连接形状
→ 多机器长时间运行与离线恢复压力
→ GitHub Actions reusable workflow
→ 在真实数据证明需要时再评估更远距离物流
```
