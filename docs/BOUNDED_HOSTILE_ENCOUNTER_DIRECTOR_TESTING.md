# 有界敌对遭遇编排器测试

## 静态合同

`validate_bounded_hostile_encounters.ps1` 验证：

- 三个正式 profile、角色和物种合法；
- 单队成员 ≤ 5、危险预算 ≤ 8、半径 ≤ 36；
- Registry 使用原子 staged commit；
- Policy 保持纯函数；
- Director 只有一个有界 `_process()`，没有 Timer、线程、全图扫描或平行存档；
- ServiceHub 场景只安装一个 Director；
- HUD、Headless、桌面、工作流和统一入口全部存在。

## Headless 领域测试

`hostile_encounter_director_regression.gd` 覆盖：

- 生产配置严格加载；
- 无效 profile 拒绝整次加载并保留原注册表；
- 健康、地图、阶段、高度、现有压力和容量资格；
- 前卫、远程支援和重装编队半径；
- 正式 `CreatureSpawner` 原子创建四人深渊突袭队；
- 所有成员共享本地玩家目标；
- 角色、物种和危险预算精确；
- 冷却阻止立即叠加第二队；
- 低血量拒绝原因；
- WeakRef 成员死亡/卸载收敛；
- 世界清理后零追踪成员；
- 60 分钟确定性规划模拟不突破活动遭遇、成员或危险预算。

## 正式桌面验收

`hostile_encounter_director_desktop_acceptance.gd` 使用正式 `game.tscn`：

1. 创建真实深渊世界并切换到夜晚；
2. 生产 Director 自动绑定真实 Hub、Spawner、玩家和昼夜；
3. 强制启动四人深渊突袭队；
4. HUD 显示前卫 2、远程 1、重装 1；
5. 保存活动遭遇截图；
6. 使用真实鼠标和正式手枪逐个击败四名成员；
7. 验证弹匣冷却、目标事务、WeakRef 卸载和遭遇完成；
8. 将玩家生命降至 25%，验证新的遭遇被暂停并显示原因；
9. 保存完成/降压截图；
10. 权威保存、返回菜单并重载；
11. 验证 `world.json` 不包含遭遇状态，重载后零活动成员。

## 相邻回归

专项工作流同时运行：

- 深渊射手真实物理；
- 近战预警；
- 生态与精英；
- 多敌人压力与竞技场批处理；
- 玩家枪械与猎弓；
- Runtime Soak。

最终固定 SHA 还必须通过仓库 32 阶段 Runtime、完整桌面矩阵和 Windows Release 导出启动。

## 证据

桌面 Artifact 必须包含：

- `hostile-encounter-active.png`；
- `hostile-encounter-complete.png`；
- `hostile-encounter-report.json`；
- stdout/stderr。

JSON 中必须为 `failures: []`，并记录角色、物种、击败成员、活动/完成快照和重载快照。
