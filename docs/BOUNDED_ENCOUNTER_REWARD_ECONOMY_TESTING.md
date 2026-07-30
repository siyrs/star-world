# 遭遇奖励与弹药经济测试

## 静态合同

`validate_bounded_encounter_rewards.ps1` 检查：

- 奖励 profile 与正式 Encounter profile ID 一一闭合；
- 奖励物品存在于正式物品注册表；
- 数量、类型数和高效阈值不超过硬上限；
- 注册表保持 staged commit；
- Reward Service 只使用现有 Director、成员死亡、RangedCombat 和 Inventory 信号；
- ServiceHub 只安装一个 Reward Service；
- 不新增 Timer、线程、全图扫描或平行保存字段；
- Headless、桌面、统一测试入口与 CI 工作流都存在。

## Headless 回归

`encounter_reward_economy_regression.gd` 使用真实 InventoryService 和信号驱动服务，覆盖：

1. 正式奖励配置严格加载；
2. 一条越界配置使整次 staged reload 失败；
3. 失败 reload 保留上一份完整注册表；
4. 6 发深渊突袭获得准确高效奖励；
5. 8 发不再获得高效加成；
6. 遭遇开始创建一个账本；
7. 射击按目标实例 ID 归入正确小队；
8. 最后一名成员死亡后才触发奖励；
9. 最后一发已经计入 shot count；
10. 火药、轻型弹和霰弹由一个背包事务同时提交；
11. 重复 completion 不重复发奖；
12. 成员卸载不被误判为击败；
13. 两队同时存在的未命中射击不双重计费；
14. 满背包时零部分写入；
15. 腾出空间后自动原子重试；
16. claim history 固定在 256 条；
17. pending 固定在 8 条；
18. 3600 秒确定性经济模拟不出现非线性奖励增长或无限弹药。

## 正式桌面验收

`encounter_reward_economy_desktop_acceptance.gd` 在正式 `game.tscn`、真实深渊世界和 1024×576 窗口中执行：

- 自动绑定 Director、Inventory、RangedCombat 和 Spawner；
- 装备真实星火手枪；
- 启动四人深渊突袭队；
- 真实鼠标逐个击败四名成员；
- 验证最后一发进入经济账本；
- 验证补给、消耗和净弹药 HUD；
- 保存奖励领取截图；
- 将三种奖励堆栈和全部背包槽填满；
- 启动三人深渊游猎队并真实击败；
- 验证完整奖励保持 pending，没有部分写入；
- 保存待领取截图；
- 腾出两个槽后自动重试；
- 通过卸载控制队证明不能伪造奖励；
- 权威保存、返回菜单和重载；
- 确认所有奖励瞬态字段不进入 `world.json`。

## 相邻回归

专项 CI 同时重跑：

- Encounter Director；
- 敌对远程和近战预警；
- 枪械与猎弓；
- Inventory 原子事务；
- 多敌人压力；
- Runtime Soak。

## 权威验收

固定最终 SHA 必须同时通过：

- Godot 4.7 严格项目导入；
- 专项 Headless；
- 正式桌面旅程；
- 32 阶段 Runtime；
- 完整桌面矩阵；
- Windows Release 导出和真实启动；
- ObjectDB、活动遭遇、奖励账本和待领取记录清零。

## 证据

CI 上传：

- `encounter-reward-granted.png`；
- `encounter-reward-pending.png`；
- `encounter-reward-report.json`；
- Headless 和相邻回归 stdout/stderr；
- Windows Release 证据。
