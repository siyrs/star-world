# 有界敌对掩体反制测试契约

## 静态合同

`validate_bounded_hostile_cover_counter.ps1` 检查：

- 临时掩体白名单只有羊毛与玻璃板族；
- 石头、木板、门、栅栏、台阶、箱子和机器不进入破坏白名单；
- 单击 2 块、单体 12 块、线采样 64、探针 6、同目标尝试 4 的硬边界；
- 生产场景只安装一个生命周期绑定服务；
- 两种精英通过 CreatureFactory 映射到薄子类；
- 世界修改只调用 `apply_block_mutations()`；
- 禁止 Timer、线程、全局组扫描、导航网格和新存档域；
- Headless、正式桌面、工作流和统一回归入口全部存在。

## Headless 领域回归

`hostile_cover_counter_regression.gd` 使用确定性的局部世界夹具验证：

1. 羊毛和玻璃板可作为临时掩体；
2. 石头、木板、门、栅栏和台阶保持永久安全；
3. 开门、关门、栅栏、玻璃板和台阶高度具有稳定弹道语义；
4. 200 格射线仍不超过 64 个采样；
5. 射手候选不超过 6 个；
6. 同一目标达到 4 次后拒绝继续换位；
7. CreatureFactory 创建真实 cover-aware 精英；
8. 一次重击破坏两格临时墙，但只调用一次 mutation batch；
9. 玩家 override 校验阻止自然生成脆弱方块被破坏；
10. 初始 2 块加 5 次两块后达到 12 块生命周期上限；
11. 第 13 块保持不变；
12. 被墙阻挡的射手找到局部弹道；
13. 候选距离和探针数保持有界；
14. 真实射手子类复用已有 cover destination；
15. 返回菜单信号同步清除破坏和换位计数；
16. 3600 秒确定性模拟包含 120 个目标锁定周期，探针工作保持线性。

## 正式桌面验收

`hostile_cover_counter_desktop_acceptance.gd` 必须从正式 `game.tscn` 运行：

### 重击者旅程

- 创建真实深渊世界；
- 通过真实 CreatureSpawner 生成重击者；
- 在玩家与重击者之间放置羊毛和玻璃板；
- 执行正式攻击蓄力与 commit；
- 两格墙体变为空气；
- Chunk rebuild 只 flush 一次；
- 破墙这一击不降低玩家生命；
- HUD 显示“临时掩体被突破”；
- 石墙不被破坏、不触发世界 flush，也不产生隔墙伤害；
- 移除石墙后，同一个重击者的下一次攻击正常伤害玩家。

### 射手旅程

- 通过真实 CreatureSpawner 生成深渊射手；
- 同时绑定共享敌对 ProjectileRuntime 与 CoverCounter；
- 三格宽、三格高的羊毛墙阻挡弹道；
- 连续受阻后最多 6 个探针找到局部换位点；
- HUD 显示“深渊射手正在换位”；
- 新位置恢复视线；
- 正式攻击状态机向共享 ProjectileRuntime 发射投射物。

### 生命周期

- 保存真实破坏后的世界；
- 返回主菜单；
- 活动破坏计数和换位计数归零；
- `world.json` 不包含 cover counter 运行时字段；
- 快速重载同一世界；
- 方块状态由原世界 override 恢复；
- 旧重击者和射手预算不跨会话。

桌面证据：

- `hostile-cover-broken.png`；
- `hostile-cover-reposition.png`；
- `hostile-cover-report.json`；
- stdout/stderr 日志。

## 相邻回归

专项工作流同时运行：

- 敌对远程遭遇；
- 敌对攻击蓄力；
- Encounter Director；
- 结构完整性；
- 世界 mutation batching；
- 连接方块、门和碰撞语义；
- 枪械；
- Runtime Soak。

最终固定 SHA 还必须通过权威 32 阶段 Runtime、完整桌面矩阵和 Windows Release 实际导出与启动。
