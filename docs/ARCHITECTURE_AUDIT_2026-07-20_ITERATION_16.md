# 全仓架构审计 · Iteration 16 · 2026-07-20

## 范围

本轮基于：

```text
master@9d0c085e9da9d4265b6310a482bb4834ba899b4a
```

重点审查：

- MachineRuntimeScheduler；
- FurnaceService；
- StonecutterService；
- MachineInteractionRouter；
- InventoryService 与 InventoryTransactionPolicy；
- 机器保存、菜单清理、重载与桌面测试；
- 下一阶段轻量自动化扩展风险。

## 结论

Machine Base 已经证明第二个机器领域可以共享调度、保存和生命周期，但“机器输入输出能力”仍没有统一合同。若直接新增自动送料或运输，调用方必须知道具体机器类型和私有槽位，从而重新形成类型分支和重复事务实现。

本轮优先建立 Capability Contract，而不是增加第三种机器或完整物流网络。

## 发现与处理

### P0 · 自动提取存在部分成功语义

现有手动 `transfer_to_inventory()` 会尽量加入背包，并把成功加入的部分从机器扣除。对玩家点击而言这是合理的便利行为，但自动化需要严格全部成功或零写入，否则上游任务无法判断剩余数量和重试边界。

处理：新增 `extract_transaction()`，先调用 Inventory 原子事务预演完整请求数量。背包不足时机器和背包均不变化。

### P0 · 自动插入无法指定精确数量

现有 `transfer_from_inventory()` 会根据源背包槽和机器容量尽量转移。自动化需要有界数量，例如每次只搬运 2 件，而不能把整个 64 件源栈全部投入。

处理：新增受控 Inventory Proxy，只向机器服务暴露请求数量，并从真实源槽精确移除同样数量。

### P1 · 输入输出方向没有权威合同

机器 Router 只知道槽位名称，不知道槽位是否允许自动插入或提取。

处理：新增 schema 1 能力描述：

```text
slot id
→ directions
→ transaction_limit
→ metadata policy
```

现有字符串注册兼容转换为：

```text
output → extract
其他槽位 → insert
```

### P1 · 自动化可能重新判断具体机器类型

错误扩展方式：

```gdscript
if machine_type == "furnace":
    ...
elif machine_type == "stonecutter":
    ...
```

处理：所有能力查询和事务集中在 MachineInteractionRouter，由注册槽位和服务公共端口驱动。静态测试禁止 Router 中出现生产机器类型判断。

### P1 · 缺少统一搬运预算

没有硬上限时，未来自动化调用方可能一次搬运任意数量。

处理：所有能力事务最多 64 件；槽位可设置更低的 `transaction_limit`，但不能超过全局上限。

### P1 · 自动化诊断与存档边界不清晰

搬运计数、最近结果和目标缓存属于瞬时运行证据，不应进入世界存档。

处理：诊断只进入 Character Snapshot；机器保存继续只有 `machines.version = 1`、Furnace 和 Stonecutter 状态。

## 本轮实现

新增：

```text
MachineCapabilityPolicy
MachineTransferInventoryProxy
```

升级：

```text
MachineInteractionRouter
├─ get_machine_capabilities
├─ get_slot_contract
├─ can_insert
├─ can_extract
├─ insert_transaction
└─ extract_transaction
```

## 兼容性

保持不变：

- `machines.version = 1`；
- `machines.furnaces`；
- `machines.stonecutters`；
- Furnace 与 Stonecutter 手动 UI；
- Machine Runtime Scheduler；
- 世界位置机器 ID；
- 菜单、失败启动和 Shutdown 清理；
- 四小时离线推进；
- 512 次模拟迭代；
- 旧方块、物品、配方与 numeric ID。

## 测试门禁

### 静态

`validate_machine_capability.ps1`：

- 能力策略和 Proxy 存在；
- 64 件上限；
- 方向和槽位合法；
- 提取必须使用 Inventory 原子事务；
- Router 不判断具体机器类型；
- 回归与桌面验收永久接入。

### 领域

`machine_capability_regression.gd`：

- 显式和兼容槽位能力；
- 精确数量插入；
- 方向、物品、容量和预算拒绝；
- 满背包零写入；
- 部分与整槽提取；
- Furnace/Stonecutter 同一能力端口；
- 诊断与保存边界。

### 真实桌面

`machine_capability_desktop_acceptance.gd`：

- 生产 GameScene 和 ServiceHub；
- 两个真实机器领域；
- 共享 Scheduler；
- 生产 Machine UI；
- 真实满背包；
- 自动插入和提取；
- 保存、菜单和完整重载；
- 1024×576 截图和日志证据。

## 下一阶段

Capability Contract 通过后，下一步可以增加一个有界自动搬运参与者：

```text
最多扫描 16 台机器
→ 每 Tick 最多 64 件
→ 只使用 Capability Contract
→ 不创建每机器 Timer
→ 不保存瞬时任务
```

在完成该小型闭环前，不引入电网、管道、长距离传送或万能 MachineManager。
