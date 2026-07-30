# 有界敌对远程遭遇测试

## 门禁入口

专项工作流：

```text
.github/workflows/bounded-hostile-ranged-encounter-tests.yml
```

统一入口：

```text
tests/run_all.ps1
```

## 静态合同

`tests/developer_b/validate_bounded_hostile_ranged.ps1` 检查：

- 深渊射手、生态权重与上限；
- schema 2 敌对攻击配置；
- 原子 staged registry；
- 纯远程策略；
- 视线、瞄准和掩体预算；
- 一个共享投射物物理循环；
- 24 发正式敌对容量；
- CombatService 唯一伤害入口；
- 32 槽按攻击者冷却；
- 瞬态投射物不进入存档；
- 枪械桌面测试不再访问已释放目标；
- 测试、工作流和文档完整性。

`validate_data.ps1` 现在统一组合：

- `items.json`；
- `ranged_combat.json`；
- `firearms.json`。

所有配方、机器、采集、作物和生物掉落都在同一个物品引用闭包中验证。

## Headless 领域验收

`hostile_ranged_encounter_regression.gd` 覆盖：

1. schema 2 profile 严格加载；
2. 越界 profile 整体拒绝，旧完整注册表不被覆盖；
3. 合法距离与视线才能开始攻击；
4. 视线丢失取消蓄力；
5. 最多八个纯策略掩体方向；
6. 同一攻击者重复命中被冷却；
7. 不同攻击者可以连续造成压力；
8. 冷却字典严格限制为 32；
9. 实体墙体阻挡视线；
10. 移除墙体后真实瞄准与发射；
11. 深渊弹通过 PhysicsDirectSpaceState 命中；
12. 一颗弹只产生一次伤害事务；
13. source 与 attacker ID 全链路保持；
14. 超速投射物被运行时拒绝；
15. 24 个敌对投射物可用，第 25 个拒绝；
16. clear 后活动数归零。

相邻测试包括：

- 旧近战预警、躲避与打断；
- 深渊精英；
- 生态危险；
- 多敌人批量压力；
- 玩家箭矢；
- 枪械事务；
- Runtime Soak。

## 正式桌面验收

`hostile_ranged_encounter_desktop_acceptance.gd` 使用正式 `game.tscn` 和 `abyss_world`：

1. 创建并启动真实世界；
2. 正式 ServiceHub 挂载 24 容量敌对运行时；
3. 正式 CreatureSpawner 创建深渊射手；
4. spawn signal 自动注入共享运行时；
5. 玩家处于合法距离；
6. 射手显示真实瞄准光束；
7. 保存 `hostile-ranged-aim.png`；
8. 深渊弹命中并降低玩家生命；
9. 建造三格宽、三格高实体石墙；
10. 视线变为阻塞；
11. 阻塞期间不生成隐藏投射物；
12. 玩家生命不继续下降；
13. 保存 `hostile-ranged-cover.png`；
14. 移除掩体；
15. 玩家使用真实鼠标与正式手枪反击；
16. 射手被击败；
17. WeakRef 安全确认卸载；
18. CombatService 仍保留稳定 target ID 与 defeated 结果；
19. 活动敌对投射物归零；
20. 权威保存、返回菜单和重载；
21. `world.json` 不包含敌对投射物；
22. 重载后活动敌对弹仍为零；
23. 输出 JSON 与 stdout/stderr。

## 证据文件

```text
hostile-ranged-aim.png
hostile-ranged-cover.png
hostile-ranged-report.json
hostile-ranged-aim.stdout.log
hostile-ranged-aim.stderr.log
```

Artifact 保留 14 天，并由 GitHub Actions 提供 SHA-256 摘要。

## 完成定义

只有固定最终 SHA 同时满足以下条件才可合入：

- 静态门禁成功；
- Godot 4.7 严格导入成功；
- 主 Headless 回归成功；
- 相邻领域回归成功；
- 正式桌面旅程成功；
- 两张截图与 JSON 成功上传；
- 权威 Godot Runtime、桌面矩阵和 Windows Release 成功；
- 无 unresolved review thread。
