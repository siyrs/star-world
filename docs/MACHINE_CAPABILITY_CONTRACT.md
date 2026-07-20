# Machine Capability Contract

## 目标

Machine Base 已统一 Furnace 和 Stonecutter 的调度、生命周期、保存和交互入口。本合同继续统一“其他系统如何安全使用机器”，避免轻量自动化重新判断具体机器类型。

```text
MachineInteractionRouter
├─ get_machine_capabilities
├─ can_insert / can_extract
├─ insert_transaction
└─ extract_transaction
```

自动化调用方只认识机器类型 ID、机器实例 ID、槽位和方向，不读取 Furnace/Stonecutter 私有状态。

## 能力 Schema

```json
{
  "schema_version": 1,
  "machine_type": "furnace",
  "machine_id": "furnace@1,2,3",
  "max_transfer_items": 64,
  "slots": [
    {
      "id": "input",
      "directions": ["insert"],
      "transaction_limit": 64,
      "allow_metadata": false
    },
    {
      "id": "output",
      "directions": ["extract"],
      "transaction_limit": 64,
      "allow_metadata": false
    }
  ]
}
```

当前生产合同：

| 机器 | 槽位 | 自动方向 |
|---|---|---|
| Furnace | input | insert |
| Furnace | fuel | insert |
| Furnace | output | extract |
| Stonecutter | input | insert |
| Stonecutter | output | extract |

手动 UI 仍可把未加工原料取回；能力方向只约束自动化端口，不改变现有玩家操作。

## 原子插入

```text
读取指定背包槽
→ 校验机器、槽位、方向、容量和 64 件预算
→ 机器服务校验配方或燃料语义
→ 精确移除请求数量
→ 提交机器槽位
```

服务在移除源物品之前完成语义和容量检查。单线程事务调用中，成功后不会再进入可失败分支。

失败时：

- 机器槽位不变；
- 背包槽位不变；
- 不产生成功事件；
- 返回稳定失败原因。

## 原子提取

```text
读取机器槽位
→ 校验 extract 方向和请求数量
→ InventoryTransactionPolicy 预演完整加入
→ 背包一次提交
→ 机器减少同样数量
```

背包空间不足时不会执行部分提取。现有手动机器 UI 可以保留旧的尽量转移行为；自动化端口必须全部成功或零写入。

## 预算

| 项目 | 上限 |
|---|---:|
| 单次机器搬运 | 64 件 |
| 注册机器类型 | 16 |
| 持久机器实例 | 4,096 |
| 离线推进 | 4 小时 |
| 单机器模拟迭代 | 512 |

本轮不引入独立 Timer、电网、管道、路径搜索或无限吞吐。

## 持久化边界

保存内容继续只有：

```json
{
  "machines": {
    "version": 1,
    "furnaces": {},
    "stonecutters": {}
  }
}
```

以下内容不进入世界存档：

- 最近一次搬运；
- 成功/拒绝计数；
- 自动化任务；
- 目标缓存；
- 路径或机器扫描结果。

## 诊断

`MachineInteractionRouter.get_snapshot()` 提供：

- 注册机器类型和能力；
- 转移尝试、成功与拒绝数；
- 插入和提取物品总数；
- 最近一次转移结果。

诊断只属于当前运行进程。

## 扩展规则

新增机器时：

1. 注册稳定 `machine_type`；
2. 声明持久槽位；
3. 为每个槽位声明 `insert`、`extract` 或两者；
4. 保持单事务上限不超过 64；
5. 复用 Inventory 原子加入事务；
6. 不在 Router 中增加具体机器类型分支；
7. 增加静态、领域、桌面和 Release 验收。
