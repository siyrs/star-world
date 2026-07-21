# 有界相邻机器自动化

## 玩家规则

第一阶段自动化不提供电网、管道或远距离物流。玩家只需要使用现有箱子：

```text
机器正上方箱子
       ↓ 自动供料 / 燃料
      机器
       ↓ 自动收取产物
机器正下方箱子
```

箱子必须与机器垂直相邻。没有上方箱子时机器仍可手动使用；没有下方箱子时产物留在机器输出槽。

当前支持所有注册到 `MachineInteractionRouter` 且使用稳定位置 ID 的生产机器，首批包括：

- Furnace；
- Stonecutter。

自动化不会判断具体机器类型。槽位方向、事务上限和实际输入合法性仍由 Machine Capability 与领域服务决定。

## 为什么不做全局物流网络

Machine Base 已经统一机器运行、保存和交互。如果自动化继续引入全局机器扫描、每机器 Timer、路径搜索或万能管理器，会重新制造新的生命周期和性能中心。

本实现由 `MachineRuntimeParticipant` 创建，并只增加一个共享 Scheduler Domain：

```text
MachineRuntimeParticipant
└─ MachineRuntimeScheduler
   ├─ furnace
   ├─ stonecutter
   └─ automation
```

自动化 Domain 不代表持久机器实例，因此它的运行 Snapshot 对聚合机器数量贡献 `0`。Tool 继承层只保留兼容服务字段，不拥有自动化生命周期。

## 有界预算

| 预算 | 上限 |
|---|---:|
| 周期 | 0.5 秒 |
| 每周期机器 | 16 |
| 每周期物品 | 64 |
| 单事务物品 | 8 |
| 每周期容器槽位 | 256 |
| 每周期事务探测 | 128 |

超过预算的机器由 round-robin 游标留到后续周期。游标只属于当前运行进程，不进入存档。

## 事件维护的候选目录

常规周期不会重新遍历全部持久机器。Automation Service 在安装时绑定机器领域的：

```text
machine_changed
machine_removed
```

机器创建或移除时更新有序候选缓存。世界重载后只执行一次目录重建，此后每周期直接从缓存中取最多 16 台机器。

因此机器数量增长时，周期成本由硬预算控制；不会每 0.5 秒扫描 `machines.furnaces`、`machines.stonecutters`、已加载 Chunk 或 Block Override 全表。

## 原子搬运

### 上方箱子到机器

```text
读取一个箱子槽位
→ 查询机器 Slot Capability
→ 通过 Machine Router 执行精确数量插入
→ 机器领域验证配方 / 燃料
→ 成功后同时减少箱子槽位并增加机器槽位
```

不支持的物品保持原位。机器输出槽不能被自动插入。

### 机器到下方箱子

```text
读取机器 extract 槽位
→ ContainerStorage 使用 InventoryTransactionPolicy 预演完整加入
→ 预演成功才提交箱子槽位
→ 机器扣除完全相同的数量
```

如果下方箱子无法接收全部请求物品：

```text
箱子不变
机器输出不变
无成功事件
```

自动化不会把一次事务拆成无法追踪的部分成功。

## 世界与生命周期

自动化生命周期由现有 `machine_runtime` 参与者统一管理，不增加新的 FeatureLifecycle 参与者：

```text
MachineRuntimeParticipant.install
→ 创建 Automation Service
→ 注册 automation Scheduler Domain
→ 绑定 Furnace / Stonecutter 事件

Begin World
→ 停止 Scheduler
→ 清空旧 World、游标、缓存和统计
→ 恢复机器状态

Attach Game
→ 绑定当前 VoxelWorld
→ 从恢复后的机器服务重建一次候选目录

Activate
→ 与 Furnace / Stonecutter 一起启动共享 Scheduler

Return to Menu / World Start Failed
→ 停止共享 Scheduler
→ 清空机器与自动化瞬时状态
→ 释放 World

Shutdown
→ 解绑机器和 Router 信号
→ 关闭 Automation、Router、机器领域和 Scheduler
```

## 存档边界

继续保存：

```text
machines.furnaces
machines.stonecutters
containers.containers
world block overrides
```

明确不保存：

```text
automation_jobs
round-robin cursor
candidate cache
transfer counters
last cycle
activation notification state
```

重载只恢复真实机器、箱子和物品；不会重放搬运历史或复制产物。

## 玩家反馈

某台机器在当前世界首次发生真实自动搬运时发布一次说明：

```text
已启用熔炉相邻箱子自动化：上方供料，下方收货
```

后续周期不重复提示，也不为每件物品播放音效。

## 测试合同

永久测试覆盖：

- 上下相邻位置与稳定 ID；
- 箱子原子事务成功和失败回滚；
- Furnace 原料、燃料和输出；
- Stonecutter 原料和输出；
- 不支持物品零写入；
- 下方箱满时零部分写入；
- 20 台机器 round-robin；
- 16 / 64 / 8 / 256 / 128 硬预算；
- `emit_events=false` 时零自动搬运；
- 候选缓存不在常规周期重建；
- 真实 VoxelWorld 方块和真实箱子 UI；
- 单次保存、返回菜单和完整重载；
- 自动化瞬时状态不进入存档；
- Windows Release 完整导出与启动。
