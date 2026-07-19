# 全仓架构审计 · 2026-07-19 · 第十轮

## 审计范围

本轮基于：

```text
master@4f14f28e113eb84b5a51c9059f91cb3c97d1a682
```

审查：

- 根目录 README、总体架构和产品路线；
- 七层 ServiceHub 继承链；
- Feature Lifecycle Coordinator；
- 探矿、危险、日志与奖励服务；
- 玩家右键使用与输入绑定；
- 昼夜、生态、精英危险压力；
- 保存、返回菜单、启动失败和退出清理；
- 静态数据合同、领域回归和真实桌面矩阵；
- 当前 21 套 GitHub Actions 专项与主质量流水线。

审计原则：

1. 不回退输入、保存、发行和旧世界兼容；
2. 不通过大重写破坏现有公共字段；
3. 先移出生命周期编排，再考虑继续拆分领域规则；
4. 玩家可见反馈必须和真实状态同步；
5. 迁移必须经过生产桌面和最终 Windows Release。

## 总体结论

项目当前已经具有成熟的：

- 数据驱动世界、资源和生态；
- 原子背包与保存事务；
- 真实输入、桌面和发行验收；
- 有界运行预算与诊断；
- 探索、地图材料和精英成长路线；
- 可观察、可躲避的敌对攻击。

当前最明显的结构性风险仍然是 ServiceHub 深继承。第七轮已经迁移日志和奖励，但探矿与危险仍由顶层 Hub 手工管理，使第二个参与者依赖一个没有显式生命周期身份的运行时。

本轮完成第二批迁移，并新增显式参与者依赖合同。

## 发现与处置

### P0 · 保持主分支可靠性

#### 1. 分支必须基于最新主分支

本轮从：

```text
master@4f14f28e113eb84b5a51c9059f91cb3c97d1a682
```

创建，不修改已有方块 numeric ID、物品 ID、地图 ID、Seed、探索 Schema 或精英生态结果。

#### 2. 迁移不能只通过 Headless

探索运行时同时涉及：

- 真实玩家绑定；
- 鼠标右键；
- HUD；
- 昼夜信号；
- 敌对生成；
- 返回菜单；
- 完整重载。

因此本轮增加独立真实桌面流程，并继续要求主质量流水线和 Windows Release 成功。

### P1 · 已完成优化

#### 3. 探索 Hub 仍是危险和探矿的生命周期所有者

迁移前 `ExplorationProgressionServiceHub` 直接：

```text
new DangerService
→ setup
→ connect danger_changed
→ setup HUD

new ProspectingService
→ setup
→ connect scan signals
→ deserialize
→ attach world/player
→ bind player
→ save
→ snapshot
→ clear
```

影响：

- Hub 同时知道服务实现、UI、信号、保存和玩家端口；
- 新增扫描反馈需要修改继承顶层；
- 日志参与者依赖 Hub 的字段赋值时机；
- 清理顺序只能靠阅读代码推断；
- 继续迁移其他系统时难以复用。

处置：新增 `ExplorationRuntimeParticipant`，完整承担危险与探矿生命周期。

#### 4. 参与者依赖没有显式合同

日志和奖励依赖探矿记录，但协调器只维护注册顺序。

错误顺序只会在 `install()` 内以通用失败暴露，无法指出具体缺失依赖。

处置：参与者可声明：

```gdscript
get_dependencies() -> Array[StringName]
```

协调器现在拒绝：

```text
participant_dependency_missing
participant_dependency_cycle
```

并在诊断中暴露：

```text
participant_dependencies
```

当前依赖：

```text
exploration_runtime
└─ exploration_journal_rewards
```

#### 5. 返回菜单没有显式解绑玩家探矿端口

旧清理只调用：

```text
ProspectingService.clear()
```

它会清空内部 `world` 和 `player`，但旧玩家仍可能保留：

```text
player.prospecting_service
```

虽然正常场景随后会释放玩家，但在启动失败、过渡帧或测试替身中，这仍是一个悬空能力引用。

处置：Runtime Participant 在 `begin_world`、`clear` 和 `shutdown` 中显式调用：

```gdscript
bind_prospecting_service(null)
```

完整重载时再绑定同一个生产服务端口。

#### 6. 危险 HUD 最多滞后一个轮询周期

危险服务每 `0.75` 秒评估一次。该预算适合玩家移动、深度和环境变化，但不适合高信号离散事件：

- 白天切到夜晚；
- 敌对生物生成；
- 敌对清场；
- 深渊精英出现或消失。

处置：参与者监听：

```text
phase_changed
ecology_changed
```

并立即执行一次有界 `refresh_now()`。

环境采样仍最多 125 个方块，不扩大预算。

#### 7. 危险反馈只有上升，没有恢复

玩家收到“危险”或“极高”提示后，即使完成清场或返回白天，也没有明确结束反馈。

处置：新增稳定 Tier 转换反馈：

```text
dangerous / severe
→ safe / guarded
→ 区域危险已缓解
```

相同 Tier 的轮询不重复提示。

### P1 · 建议下一轮处理

#### 8. Hub 继承链仍有五个以上直接领域层

当前只迁移了：

- 探矿与危险；
- 日志与奖励。

仍直接存在：

- Repair；
- Husbandry；
- Ranch Attraction；
- Ranch Products；
- Agriculture / character progression 中的部分生命周期。

建议下一批选择状态边界清晰且依赖较少的牧场产物和吸引服务，继续验证组合方式，而不是一次性重写整条继承链。

#### 9. Coordinator 只支持“依赖已安装”，还没有拓扑规划

当前显式依赖能够拒绝错误顺序，但仍要求调用方按正确顺序注册。

在参与者超过四到五个后，可考虑：

```text
批量声明
→ 拓扑排序
→ 安装计划
→ 循环依赖报告
```

当前参与者只有两个，不应提前引入复杂图框架。

#### 10. 危险即时刷新可能在高频生态变化中重复采样

目前生态 Snapshot 只有真实变化时才发信号，危险采样有 125 硬上限，因此成本可控。

增加大量敌对和批量卸载前，应补充：

- 同帧多次生态事件合并；
- 最大即时刷新频率；
- 三到五只敌对同时生成/消失压测；
- F3 中显示轮询与事件刷新次数。

### P2 · 功能推进建议

#### 11. 多敌对预警可读性

深渊精英已经完成，但下一只精英前应先验证：

```text
3–5 个敌对同时前摇
→ 预警圈重叠
→ 焦点提示优先级
→ 危险压力刷新
→ CPU / 物理预算
```

#### 12. Machine Base

Furnace 已经成熟，下一步可提取：

- 输入/输出能力；
- 进度和阻塞；
- 燃料/能源端口；
- 有界离线推进；
- 位置序列化；
- 只读 UI Snapshot。

不应把 FurnaceService 直接扩展为万能机器管理器。

#### 13. 建筑连接形状

当前门、栅栏、梯子和玻璃板仍有扩展空间。新增连接规则时必须统一：

```text
放置预览
→ 方块方向/连接策略
→ 网格
→ 碰撞
→ 保存与重载
```

## 本轮交付

- `ExplorationRuntimeParticipant`；
- 显式参与者依赖验证；
- Hub 探矿/危险职责移除；
- 玩家探矿端口显式解绑；
- 昼夜和生态即时危险刷新；
- 危险缓解反馈；
- 静态生命周期合同升级；
- 领域依赖、保存、重载和清理回归；
- 独立真实探索运行时桌面验收；
- 既有日志/奖励桌面复验；
- 架构合同和审计文档。

## 合并标准

只有以下全部成功才允许进入 `master`：

1. Godot 严格导入；
2. ServiceHub 静态合同；
3. Prospecting、Ecology/Danger、Journal、Reward 相邻合同；
4. 生命周期依赖和逆序清理回归；
5. 真实危险升级与缓解；
6. 真实右键探矿；
7. 返回菜单旧玩家解绑；
8. 完整重载记录恢复；
9. 既有奖励通知、J 键和领取流程；
10. 全量 Runtime 与领域回归；
11. 全部真实桌面矩阵；
12. Windows Release 实际导出与启动；
13. 日志无脚本错误、解析错误、ObjectDB 或资源泄漏。
