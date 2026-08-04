# PR #100 剩余玩家旅程迭代闭环复审

状态：**本轮代码合并条件满足后可合并；商业正式发布继续 HOLD**

目标分支：`master`  
集成分支：`agent/complete-remaining-player-journeys`  
PR：`#100 feat: complete remaining player journeys, conservation and continuous routes`

> 本报告是本轮任务清单的实现复审，不把自动化覆盖范围扩大解释为“全部无限程序化地图已经走遍”“最终导出包已经完成人工 E4 体验复审”或“目标最低硬件已经完成严格 120 分钟长稳”。最终合并必须以同一 PR head 的永久只读 CI 全绿为前提。

## 1. 本轮任务清单复审

| 任务 | 实现结论 | 关键证据 | 复审结果 |
|---|---|---|---|
| 牧场产物在真正接收前保持权威 | `ReliableAnimalProductService` 保留 `pending_count`，拾取物仅是可重建运行时表现；零接收、过期、重载均不丢失 | `ranch_product_conservation_regression.gd`、`ranch_product_expiration_conservation_regression.gd` | 通过 |
| 产物通知不可因重载或拾取物过期重复播放 | 每只动物维护有界 `_announced_pending` 账本；历史待领取数量在激活前建立基线 | 重载抑制、连续两次过期重建、账本清理回归 | 通过 |
| 已接收拾取必须在节点销毁窗口内提交 | 收集回调直接核对 `_active_pickups` 中的同一实例，在 `queue_free` 前提交 accepted 数量并移除活动引用 | 过期后重新物化再完整收集的守恒回归；真实牧场桌面闭环 | 通过 |
| 畜牧活体、冷却、死亡和多代繁殖完整重载 | 两头成年牛、第一代幼崽、冷却拒绝、第二代幼崽、真实攻击死亡、两次完整菜单重载 | `husbandry_closed_loop_stable_desktop_acceptance.gd` | 通过 |
| 牧场离线计时、满背包、收集和不复活 | 保存边界推进离线时间；满背包接触零修改；释放容量后正式收集；最终重载不复活拾取物 | `ranch_products_closed_loop_desktop_acceptance.gd` | 通过 |
| 农业失败、成长、收获和精确重载 | 受阻锄地、成长中收获、满背包成熟收获均为原子失败；真实灌溉、施肥、成熟、收获、自动补种；三次权威保存/重载 | `agriculture_closed_loop_canonical_desktop_acceptance.gd` 继承完整生产旅程 | 通过条件已建立 |
| 农业桌面门禁必须有界且可定位 | 真实 `CharacterBody3D.move_and_slide()` 建立碰撞；缺失拒绝事件不会导致数组越界中断；600 秒看门狗记录最后阶段并退出 | `MAX_TEST_SECONDS`、`_last_rejection_reason`、`_stage` | 通过 |
| 床位出生点、受阻失败、死亡重生和拆除回退 | 受阻床不覆盖旧出生点；真实死亡面板重生回床；正式持续主键挖掉床；`bed_removed` 后回退世界出生点；完整保存重载 | `rest_closed_loop_stable_desktop_acceptance.gd` | 通过 |
| 探索全部里程碑、奖励、失败和重载 | 12 次正式右键扫描覆盖 12 个唯一 Chunk、4 个深度带和 8 个里程碑；冷却与满背包失败原子；8 个 UI 按钮逐一领取；完整重载无事件重播 | `exploration_closed_loop_desktop_acceptance.gd` | 通过 |
| 探索奖励必须跨 JSON canonical 边界精确保存 | 原始旅程使用真实 `InventoryService` 反序列化再序列化后精确比较；独立 SaveService 回归验证槽位、metadata、选择槽和 58 个奖励物品 | `exploration_reward_inventory_persistence_regression.gd` | 通过 |
| 五张正式地图从出生点执行连续正常路线 | `star_continent`、`desert_ruins`、`frozen_wastes`、`sky_islands`、`abyss_world` 均从生产出生点开始；无出生后传送；正式移动/跳跃输入完成有界路线 | `player_continuous_route_buffered_jump_regression.gd` | 通过 |
| 连续路线不得把控制器漂移误判为空气墙 | 每帧双轴目标纠偏、低速到点、上坡净空、周边含对角 Chunk 碰撞加载、显式停滞诊断 | 路线规划与执行静态合同 + 五 Profile 运行时结果 | 通过 |
| 上坡跳跃不得依赖瞬时 `is_on_floor()` 样本 | 上坡开始前缓冲正式跳跃输入，停滞时仅做有界重试；平地和下坡不注入跳跃 | 缓冲跳跃回归 | 通过 |
| 永久 CI 必须只读、自动、可复跑 | PR 与 `master` push 均触发；`contents: read`；陈旧运行自动取消；领域与五个桌面旅程分离；证据 artifact 保留 | `.github/workflows/remaining-player-journeys-tests.yml` | 通过 |

## 2. 复审中发现并修复的真实缺陷

### 2.1 连续路线固定单轴输入造成转弯漂移

旧执行器按照路线方向持续按单一轴，转弯后残留横向速度把胶囊体带入方块边角。规划中心线可走，但执行器会在边角碰撞后被误报为空气墙。

修复后每帧依据目标方块中心同时校正 X/Z，接近目标时释放输入并要求低速到点；路线仍由生产输入和真实物理完成，没有降低位移、Chunk、跌落或停滞标准。

### 2.2 一格上坡从未发出跳跃

CI 证据显示五个 Profile 都在一格上坡失败，且 `jump_attempts=0`。根因是测试驱动只在同一瞬时 `is_on_floor()` 为真时按跳跃，地面状态切换窗口会吞掉唯一机会。

修复为上坡开始前缓冲正式跳跃动作，并只在实际停滞时做最多两次有界重试。没有使用传送、改坐标或放宽成功断言。

### 2.3 拾取物收集信号与 `queue_free` 生命周期竞态

`ItemPickup` 发出 `collected` 后立即安排销毁。旧服务通过会排除 queued node 的 `_active_pickup()` 再确认身份，导致已经接受的数量在销毁窗口被丢弃。

修复为直接核对注册表中的同一拾取实例，先提交 `pending_count`，再移除活动引用。零接收仍不提交。

### 2.4 过期产物重新物化重复播报

待领取拾取物自然过期后必须重建，但旧实现把每次重建都当成新产出。修复为每只动物的已公告待领取基线，只对真正增加的 pending 数量发通知。

### 2.5 农业失败可能让测试协程中断但进程不退出

旧旅程在读取最后拒绝事件时直接使用 `rejections[-1]`。若输入焦点或事件未产生，GDScript 协程会中断，桌面进程继续运行直到外层 40 分钟超时，隐藏真实失败位置。

修复后空事件得到明确失败断言；看门狗在 600 秒内报告最后阶段；真实向下 `move_and_slide()` 消除软件渲染 CI 中的一帧地面状态抖动。

### 2.6 探索 JSON 直接字典相等不是正确持久化边界

JSON 数字表示与运行时 canonical 整数 metadata 可能不同。曾出现通过包装器跳过原始断言的临时方案，复审认为不够稳健并已删除。

现在原始生产旅程直接使用 `InventoryService.deserialize()` / `serialize()` 跨 canonical 边界后比较；另有独立真实 `SaveService` 回归交叉验证。没有保留强制成功的 `_check` 覆写。

## 3. 架构与可维护性复审

- **权威状态单一来源**：产物数量、农业状态、探索奖励、出生点均由领域服务及世界存档持有，运行时节点和 UI 只是投影。
- **失败原子性**：满背包、冷却、受阻空间、成长中作物、受阻床均验证领域状态、背包和世界方块零部分修改。
- **事件幂等**：完整重载不重播出生、死亡、成熟、收获、扫描、领奖或产出反馈。
- **测试不绕过生产入口**：关键旅程使用真实按键、鼠标、射线、按钮、`CharacterBody3D` 和生产服务；调试布置只负责建立确定性场景，不直接提交被测成功结果。
- **CI 永久化**：质量门禁属于常驻 PR/主分支工作流，不依赖临时写权限工作流；临时补丁工作流均已删除。
- **故障可诊断**：路线记录每步目标、最终位置、进度、停滞窗口和跳跃次数；农业记录最后阶段；桌面旅程保存截图与 stdout/stderr。

## 4. 证据边界与剩余产品阻塞

本轮能够支持：

- 被覆盖领域达到生产场景、正式输入、真实物理/UI、成功/失败、保存/菜单/重载的 **E3 闭环**；
- 五个 Profile 从生产出生点开始完成固定 Seed 下的有界连续路线，且无出生后传送；
- 通用 Windows Release 导出与 smoke、全仓库运行时/桌面门禁可作为工程回归证据。

本轮不能支持：

- 无限程序化地图或全部随机 Seed 已完整遍历；
- 每张地图全部遗迹、洞穴、水域、高空、边界和兴趣点均已连续到达；
- 最终导出程序已由独立人员完成全地图、全内容 E4 视觉与手感复审；
- 最低/推荐目标硬件的同场景性能门槛已满足；
- 严格 120 分钟目标硬件长稳已经完成。

因此：

- **PR #100 本轮迭代合并结论**：同一最终 head 的领域门禁、五个桌面闭环、全仓库 Godot 门禁和 Windows Release smoke 全绿后，允许合并 `master`。
- **整个产品商业发布结论**：继续 `HOLD`，沿用 `qa/final-release-report.md` 中尚未解除的 E4、目标硬件性能和长稳阻塞。

## 5. 最终合并检查

合并前必须同时满足：

- PR 仍以 `master` 为 base，且 mergeable；
- PR 不包含临时写权限 workflow 或临时触发文件；
- `Remaining player journeys quality gates` 在同一 head 全部成功；
- `Godot quality gates` 在同一 head 的运行时、桌面 UI 和 Windows Release smoke 全部成功；
- PR 从 draft 转为 ready；
- 使用 expected head SHA 合并，防止验收后分支移动；
- 合并后 `master` 的 push 门禁再次运行。
