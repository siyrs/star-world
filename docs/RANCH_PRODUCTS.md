# 牧场吸引与动物产物系统

## 目标

本系统把既有农业与动物繁殖连接成可持续牧场循环：

```text
种植小麦 / 胡萝卜 / 小麦种子
→ 手持正确饲料吸引动物
→ 喂养并纳入持久牧场
→ 成年鸡周期性产下鸡蛋
→ 玩家靠近后生成可拾取鸡蛋
→ 熔炉烹饪为熟鸡蛋
```

实现必须保持以下边界：

- Player 只转发输入意图；
- BaseCreature 只暴露通用移动能力，不认识饲料和物种；
- HusbandryService 继续拥有动物身份、成长与繁殖状态；
- AnimalAttractionService 只拥有短时吸引意图；
- AnimalProductService 只拥有产物计时与待投放数量；
- UI 和提示层只读取快照，不直接修改领域状态；
- 所有持久状态通过组合根进入同一个世界保存事务。

## 模块结构

```text
RanchProgressionServiceHub
├─ HusbandryProgressionServiceHub
├─ AnimalAttractionService
│  ├─ AnimalAttractionRegistry
│  ├─ AnimalAttractionPolicy
│  └─ BaseCreature attraction capability
├─ AnimalProductService
│  ├─ AnimalProductRegistry
│  ├─ AnimalProductPolicy
│  ├─ ItemPickup
│  └─ AnimalProductStateMigration
└─ HusbandryInteractionAdapter
   └─ product status decoration
```

## 吸引行为

`data/animal_attraction.json` 描述：

- 检查频率；
- 目标保持时间；
- 每个物种的吸引半径；
- 每个物种靠近玩家后的停止距离。

饲料映射不在该文件重复定义，而是继续读取 `data/husbandry.json`。这样鸡、牛、猪的繁殖饲料与吸引饲料不会发生配置漂移。

### 决策顺序

动物移动优先级为：

```text
受击逃跑
→ 饲料吸引
→ 敌对追击（仅敌对生物）
→ 自然游荡
```

`AnimalAttractionPolicy` 只计算：

- 选中物品是否为该物种的饲料；
- 动物是否位于吸引半径内；
- 是否已经进入停止距离。

`AnimalAttractionService` 扫描 CreatureSpawner 下的被动动物，并调用：

```gdscript
set_attraction_target(player, timeout_seconds, stop_distance)
clear_attraction_target()
```

BaseCreature 不读取 Inventory，也不读取 Husbandry 数据。

### 性能预算

- 默认每 0.25 秒刷新一次；
- 不为每只动物创建独立 Timer；
- 只扫描 CreatureSpawner 当前直接拥有的动物；
- 吸引目标使用短时租约，服务停止或物品切换后自动失效；
- 远距离持久动物仍受 Husbandry 的 48 格模拟半径控制。

## 动物产物

`data/animal_products.json` 描述：

- 支持产物的物种；
- 产物物品；
- 生产间隔；
- 每只动物最大待投放数量；
- 是否仅成年动物生产；
- 离线推进上限；
- 玩家靠近后投放 Pickup 的距离。

当前内容：

```text
成年持久鸡
→ 每 180 秒产生 1 个鸡蛋
→ 每只鸡最多积累 6 个待投放鸡蛋
```

自然生成但从未被玩家喂养的鸡不会进入产物系统，避免随机生物造成无界存档与产物增长。

## 生产状态

世界状态新增：

```text
animal_products {
  version,
  saved_at_unix,
  records {
    husbandry_id {
      species_id,
      remaining_seconds,
      pending_count
    }
  }
}
```

生产记录使用 Husbandry 的稳定 ID，而不是场景节点路径或实例 ID。

### 在线推进

```text
同步持久动物只读快照
→ 过滤成年且支持产物的动物
→ 推进统一计时
→ 达到间隔后增加 pending_count
→ 玩家在投放半径内时生成 ItemPickup
→ 成功生成后 pending_count 清零
```

多个待投放产物合并为一个带数量的 Pickup，避免离线返回时突然创建大量节点。

### 离线推进

加载时最多计算六小时离线时间。产物数量始终受 `max_pending` 限制：

```text
长时间离线
→ 推进计时
→ 最多积累配置上限
→ 玩家靠近动物后再投放
```

玩家远离牧场时，鸡蛋保留在领域状态中，不会因为世界 Pickup 的生命周期结束而丢失。

### 幼崽与死亡

- 幼年鸡没有生产记录；
- 幼崽成年后才创建新的生产计时；
- 动物死亡或移出 Husbandry 后，对应生产记录会被清理；
- 生产服务不拥有动物生命和成长状态。

## 交互提示

HusbandryInteractionAdapter 仍是实体提示统一入口。它先生成繁殖提示，再追加产品状态：

```text
鸡
生命 4 / 4 · 成年 · 可繁殖 · 下次鸡蛋约 2 分 15 秒

[鼠标左键] 攻击
[鼠标右键] 喂食小麦种子，进入繁殖状态
```

存在待投放产物时：

```text
鸡蛋待收集 ×3
```

幼年鸡显示：

```text
成年后开始产出鸡蛋
```

## 物品闭环

新增物品：

```text
鸡蛋
熟鸡蛋
```

熔炉配方：

```text
鸡蛋 ×1
→ 4 秒
→ 熟鸡蛋 ×1
```

熟鸡蛋恢复 4 点饥饿和 3 点饱和度。

## 事务与失败保护

- 产物先增加到持久 pending，再尝试生成世界 Pickup；
- 玩家不在附近、实体未加载或投放依赖缺失时，pending 不减少；
- 只有 Pickup 节点成功加入世界后才提交 pending 清零；
- 生产状态与 Husbandry ID 一一对应；
- 未知物种、未知物品和损坏记录在加载时被忽略；
- 存档迁移不会凭空创建动物或产物。

## 扩展方式

增加新动物产物时：

1. 在 `items.json` 注册产物；
2. 在 `animal_products.json` 增加一个物种配置；
3. 必要时增加加工配方；
4. 扩展数据验证；
5. 增加领域与真实桌面验收。

核心服务不应增加物种 ID 分支。

未来可扩展：

- 牛奶与铁桶采集；
- 羊毛剪取与再生；
- 鸡蛋孵化；
- 自动收集设施；
- 牧场状态面板；
- 不同品质或稀有产物。

## 质量门禁

必须通过：

- `validate_ranch.ps1`；
- `ranch_products_regression.gd`；
- `ranch_products_desktop_acceptance.gd`；
- 完整 Godot 既有 Runtime 回归；
- 完整既有桌面输入/UI 回归；
- 实际 Windows Release 导出与 180 帧 smoke；
- 日志无脚本错误、解析错误和资源泄漏。
