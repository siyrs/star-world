# 有界枪械战斗测试与验收

## 测试层级

本功能不能只通过 profile 单元测试验收。永久门禁分为四层：

1. 静态架构与数据合同；
2. 注册表、制作、装备 metadata 与持久化回归；
3. 真实 Godot PhysicsDirectSpaceState 命中扫描与事务回归；
4. 正式 `game.tscn` 的鼠标、键盘、手柄、截图、保存和重载。

## 静态门禁

`validate_bounded_firearms.ps1` 验证：

- 6 个物品、6 个配方、3 个枪械 profile；
- 与基础和弓箭数据无重复 ID；
- 半自动、全自动、泵动身份准确；
- 弹匣不超过 64；
- 每枪不超过 12 条射线；
- 最大距离 128；
- 单枪原始伤害预算不超过 48；
- 命中扫描无 Timer、线程、逐弹丸节点、存档和直接 `take_damage`；
- 备用弹只在换弹完成时提交；
- 枪械生产代码无 `KEY_R`、`JOY_*` 或物理手柄事件；
- 主手装备优先的第一人称模型合同；
- 工作流、文档和全量测试入口永久存在。

## 注册表回归

`firearm_registry_regression.gd` 使用真实服务验证：

- 默认物品和配方注册表原子包含枪械扩展；
- 工作台真实制作火药、轻型弹药和手枪；
- 装备事务保留 `magazine_rounds`；
- `EquipmentService.update_slot_metadata()` 精确修改弹匣；
- inventory/equipment 现有 schema 保存并恢复备用弹、武器和弹匣；
- 越界弹匣、射速、弹丸数、伤害和距离使整个 profile registry 失败。

## 运行时回归

`firearm_runtime_regression.gd` 在真实 3D 物理空间中验证：

- 手枪命中真实碰撞体；
- 一枪弹匣减一、耐久减一、备用弹不变；
- 冷却期间第二次按下被拒绝；
- 空弹匣零消耗；
- 换弹开始不提前扣备用弹；
- 取消换弹零损失；
- 完成换弹原子扣备用弹并填充弹匣；
- 弹匣和备用弹保存重载；
- 霰弹 7 条射线对同一大目标只产生一次目标伤害事务；
- `pellet_hits` 大于一且伤害按命中数聚合；
- 全自动每 0.1 秒最多一枪，不超过弹匣；
- HitscanRuntime 最多 12 条射线、128 格，没有 per-shot Timer 节点。

## 正式桌面验收

`firearm_desktop_acceptance.gd` 在 1024×576 的正式游戏中：

1. 创建真实星辰大陆世界；
2. 装备带 2 发弹匣的星火手枪；
3. 验证第一人称模型读取主手装备；
4. 真实鼠标左键开火并命中生物；
5. 验证弹匣、备用弹和耐久事务；
6. 真实键盘 `R` 开始换弹；
7. 截图换弹进度、弹匣和备用弹 HUD；
8. 等待原子换弹完成；
9. 真实手柄右扳机开火；
10. 真实手柄左肩键再次换弹；
11. 截图命中与准备状态；
12. 权威保存、返回菜单和重载；
13. 验证备用弹、耐久和弹匣恢复；
14. 验证换弹瞬态没有进入 `world.json`；
15. 输出 JSON、stdout 和 stderr。

## 相邻门禁

专项 CI 同时执行：

- 弓箭注册表与真实投射物；
- 控制器 gameplay；
- 第一人称 viewmodel；
- 装备与近战；
- 背包原子事务；
- Runtime Soak。

仓库权威 `Godot quality gates` 继续要求 32 阶段 Runtime、完整桌面矩阵和 Windows Release 实际导出启动。

## 证据

专项工作流上传：

```text
bounded-firearm-domain-<run>
bounded-firearm-evidence-<run>
```

桌面证据包含：

```text
firearm-combat-reload.png
firearm-combat-hit.png
firearm-combat-report.json
firearm-combat-reload.stdout.log
firearm-combat-reload.stderr.log
```

只有固定最终 SHA 的所有门禁完成且无失败、无排队、无运行中任务，PR 才能转 Ready 并 squash 合入 `master`。
