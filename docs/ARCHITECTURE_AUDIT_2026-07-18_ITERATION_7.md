# 全仓架构审计 · 2026-07-18 · 第七轮

## 审计基线

```text
master@870c3b0720871db69f500dada0da383fbe64d4cf
```

审计范围包括：

- `scenes/game` 与 `scenes/ui` 生产组合；
- ServiceHub 七层继承链；
- 世界开始、附加、激活、保存、返回、失败和退出路径；
- 探矿、日志、奖励、生态和危险；
- 背包事务、合成、存档和 UI 输入上下文；
- 全量 Runtime、真实桌面与 Windows Release 工作流；
- 最近六轮主分支增量的兼容合同。

原则：先降低跨功能生命周期风险，再增加更多会继续扩大 Hub 条件分支的新内容。

## 总体结论

项目的领域服务已经比较清晰，但生产组合层仍通过深继承把每个新领域接入同一组生命周期方法。当前继承链为：

```text
GameplayServiceHub
→ ToolProgressionServiceHub
→ CharacterProgressionServiceHub
→ RepairProgressionServiceHub
→ HusbandryProgressionServiceHub
→ RanchProgressionServiceHub
→ ExplorationProgressionServiceHub
```

这种结构在功能数量较少时直接，但继续加入探索、生态、精英敌人、Machine Base 或建筑连接后，会放大以下风险：

- 每层必须正确调用 `super`；
- 保存字段可能在不同层使用不同策略写入；
- 返回菜单和世界启动失败的清理顺序难以审计；
- `_exit_tree` 信号断开容易遗漏；
- 新功能必须修改顶层 Hub；
- 真实玩家反馈逻辑与领域安装逻辑混在同一脚本。

本轮采用增量组合而非大重写：先迁移“探索日志 + 里程碑奖励”，验证参与者合同、公共兼容和完整发行路径，再逐步迁移其他领域。

## 本轮发现与处置

### P0 · 世界生命周期必须保持单一事务

#### 1. 各继承层直接修改 `current_state`

当前探索、牧场、养殖和角色层都在 `save_current()` 中先写入 `current_state`，再交给父级生成最终 payload。

影响：

- 字段归属分散；
- 新功能可能绕过最终 SaveService 事务；
- 无法统一列出保存参与者；
- 保存顺序只能通过阅读整条继承链推断。

处置：第一批参与者只实现 `save_into(payload)`，仍写入父级最终使用的同一状态对象，不允许自行保存。日志/奖励领域已迁移；探矿暂时保留在继承层以控制风险。

#### 2. 清理顺序依赖人工排列

奖励依赖日志，日志依赖探矿。清理时若先清探矿再处理日志信号，可能产生中间 snapshot 或重复 UI 刷新。

处置：协调器的 `clear` 和 `shutdown` 固定使用注册逆序。安装、开始、附加、激活、保存和 snapshot 使用正序。

### P1 · 已完成优化

#### 3. 探索 Hub 同时拥有安装、状态、UI 和反馈

原 `ExplorationProgressionServiceHub` 直接：

- 创建日志服务；
- 创建奖励服务；
- 连接奖励成功和失败信号；
- 配置日志 UI；
- 恢复奖励状态；
- 保存奖励；
- 生成奖励 snapshot；
- 在三条退出路径清理奖励和日志。

影响：顶层继承脚本继续增长，任何奖励 UI 或通知修改都会触碰世界生命周期代码。

处置：新增 `ExplorationJournalRewardParticipant`。顶层 Hub 只注册参与者并保留兼容公共字段；参与者拥有日志/奖励的安装、状态、UI 和反馈。

#### 4. 没有统一参与者合同

此前无法用一个测试回答：某个功能是否处理了世界开始、保存、返回、失败和退出。

处置：新增 `ServiceHubFeatureCoordinator`，注册时要求完整实现：

```text
install
begin_world
attach_game
activate
save_into
snapshot_into
clear
shutdown
```

不完整参与者和重复 ID 会被拒绝。

#### 5. 生命周期缺少有界诊断

深继承顺序出现问题时，测试只能从最终状态推断，无法看到某个阶段是否调用过两次。

处置：协调器记录每个阶段次数和最近 48 条阶段历史，并通过角色诊断 snapshot 暴露。历史上限防止长时间运行无限增长。

#### 6. 玩家不知道新奖励已经可领取

里程碑在扫描后会变成 `claimable`，但玩家只有主动打开 J 日志才会发现。

处置：参与者监听权威奖励 snapshot，在 active gameplay 中首次出现新 claimable 状态时提示：

```text
探索里程碑可领取：…（按 J 查看）
```

载入阶段先建立基线，因此继续世界不会重复提示已有待领奖励。重复 `refresh()` 也不会刷屏。

### P1 · 继续保留的兼容入口

本轮没有修改：

- `service_hub.tscn` 脚本入口；
- 七层继承的外部可见类；
- `exploration_journal_service` 字段；
- `exploration_reward_service` 字段；
- 两个服务的节点路径；
- 保存 schema；
- 探索记录和奖励状态版本；
- J 键、Overlay ID 和 UI 调用方式。

这样可以让已有测试和生产代码继续运行，同时为后续迁移提供可复用合同。

## 审计发现的后续优化点

### 1. 探矿和危险仍由顶层继承层管理

它们拥有真实世界和玩家依赖，迁移风险高于日志/奖励。下一批应把两个服务作为一个参与者迁移，确保：

```text
地图 profile
→ danger attach/activate
→ prospecting attach
→ player bind
→ exploration serialize
→ clear/shutdown
```

需要覆盖错误地图校准、世界失败和玩家替换。

### 2. 牧场和养殖 Hub 重复相同生命周期模板

`RanchProgressionServiceHub` 与 `HusbandryProgressionServiceHub` 都重复：

- `_ready` 创建服务；
- `_begin_world` 反序列化；
- `attach_game` 绑定玩家；
- `activate_gameplay` 激活；
- `save_current` 序列化；
- 三种退出路径清理；
- snapshot 聚合。

参与者合同稳定后可按“牧场产物 → 吸引 → 养殖”顺序迁移。

### 3. 部分反馈连接仍由 Hub 持有

装备、农业、休息、养殖和牧场信号都由继承层连接。长期目标应让领域参与者持有自己建立的连接，Hub 只提供：

```text
publish_message
play_audio
register_interaction_extension
```

### 4. 协调器当前只安装在顶层探索 Hub

这是刻意的增量策略。直接下移到基础 Hub 会同时改变所有继承层的生命周期顺序。

当至少两个参与者完成真实桌面和 Release 验收后，再考虑：

- 在基础 Hub 创建协调器；
- 保留顶层转发方法；
- 给旧子类提供迁移窗口；
- 用顺序回归固定旧行为。

### 5. 敌对攻击仍缺少可读前摇

`BaseCreature` 目前在进入攻击范围且冷却结束时立即造成伤害，玩家无法通过动画或方向提示规避。

建议下一条玩家闭环：

```text
进入攻击范围
→ 锁定朝向
→ 有界前摇
→ 目标仍在有效范围才命中
→ 离开范围或击退则取消
→ HUD/模型可读提示
```

先实现普通僵尸前摇，再引入少量地图精英，避免一次加入复杂行为树。

### 6. GitHub Actions 前置步骤持续重复

当前专项工作流重复 checkout、Godot 安装、严格导入、桌面 wrapper 和 artifact 上传。

建议在生命周期参与者第二批稳定后提取 reusable workflow，避免同时进行运行时架构迁移和 CI 平台大改。

## 本轮交付

### 生产代码

- `ServiceHubFeatureCoordinator`；
- `ExplorationJournalRewardParticipant`；
- `ExplorationProgressionServiceHub` 增量组合化；
- 新奖励可领取单次提示；
- 生命周期诊断 snapshot。

### 测试

- 静态生命周期合同；
- 协调器顺序和幂等回归；
- 生产 Hub 兼容与保存/清理回归；
- 真实右键、J 键、鼠标领取、返回菜单、重载和失败启动验收；
- 独立 CI 质量门禁；
- 全量 Runtime、全部桌面流程和 Windows Release 复验。

### 文档

- 本审计；
- `SERVICE_HUB_FEATURE_LIFECYCLE.md`；
- README 与产品路线更新。

## 合入标准

本轮只有在以下全部成立时允许合入 `master`：

1. Godot 严格导入成功；
2. 生命周期静态合同成功；
3. 协调器正序/逆序和幂等回归成功；
4. 日志与奖励既有回归成功；
5. 新奖励提示只出现一次；
6. 返回菜单、完整重载和启动失败均清理正确；
7. 全量 Runtime 与领域回归成功；
8. 全部既有真实桌面流程成功；
9. 新专项真实桌面成功并保存截图和日志；
10. Windows Release 实际导出并启动；
11. 日志无脚本错误、解析错误和资源泄漏；
12. 分支基于最新 `master` 且无并行改动回退。
