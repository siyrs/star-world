# 虚拟化存档浏览器合同

## 问题

世界目录的磁盘成本已经由以下边界控制：

```text
Primary 修复          8
完整世界读取         32
Sidecar 写入         16
瞬时目录暂存         64
```

但旧存档浏览器每次 `refresh()` 都会：

```text
queue_free 全部现有行
→ 为全部世界重新创建 HBoxContainer
→ 重新创建选择按钮和继续按钮
→ 重新连接全部信号
```

当世界数量增长时，目录扫描虽然有界，UI 节点创建、释放、布局和信号连接仍会随世界数线性增长。目录积压还依赖玩家反复点击刷新或重新打开面板才能继续收敛。

## 固定 24 行复用池

存档浏览器只创建固定 **24 行**：

```text
MAX_VISIBLE_ROWS := 24
```

每行包含一个选择按钮和一个“继续”按钮。刷新只更新现有控件的文本、可见性和绑定 world ID，不再释放或创建行节点。

世界数量超过 24 时使用分页：

```text
上一页
第 N / M 页 · 每页最多 24 个
下一页
```

分页只切换内存中的白名单 metadata，不调用 `list_worlds()`，不读取磁盘，也不推进目录恢复预算。所有世界仍可访问，最后一页不足 24 项时隐藏未使用槽位。

## 自动渐进整理

首次显式刷新仍同步执行一次有界 `list_worlds()`。若诊断显示以下任一积压：

```text
主文件待修复
权威 metadata 待读
瞬时目录暂存
Sidecar 待建
```

面板在可见期间自动执行跨帧整理：

```text
每帧最多 1 次有界 list_worlds()
最多 6 个自动轮次
```

合同常量为：

```text
MAX_AUTO_SETTLE_PASSES := 6
```

自动整理不新增 Timer、线程或持久队列。积压归零后立即 `set_process(false)`；面板隐藏时停止，重新显示后只在剩余预算内继续。永久故障或无法收敛的目录最多获得 6 次自动尝试，不会形成无限主菜单循环。

## 选择与分页

- 选择状态按稳定 world ID 保存；
- 删除或刷新后若世界不再存在，选择自动清空；
- 当前页在世界数量变化后被限制到有效范围；
- 每一页复用同一批 24 行；
- 页面切换不会调用存档服务；
- “继续”按钮仍直接发出真实 world ID，完整加载不受分页和列表预算限制。

## 有界诊断

`SaveBrowserPanel.get_virtualization_snapshot()` 只返回固定标量：

```text
row_pool_limit
row_pool_size
visible_row_count
page_index
page_count
total_world_count
row_create_count
render_count
refresh_count
auto_settle_limit
auto_settle_pass_count
remaining_auto_settle_passes
auto_settle_active
```

`get_visible_world_ids()` 最多返回当前 24 个 world ID，用于分页合同和真实桌面验收。它不包含世界 payload。

## 72 个世界真实行为

72 个健康世界全部删除 `catalog.json` 时：

```text
显式刷新 1 次
自动整理 4 次
总扫描 5 次
```

目录在不需要玩家重复点击的情况下收敛：

- 所有 72 个世界始终可通过三页访问；
- 每页最多 24 个节点；
- 完整世界累计读取恰好 72 次；
- 暂存 entry 被跨帧复用；
- 最终 72/72 sidecar 命中；
- 稳态完整读取、目录写入和暂存均为 0；
- 24 个行节点从创建到退出始终不增加。

## 永久验收

- Headless：72 世界、三页、固定 24 行、分页零扫描；
- Headless：可收敛积压自动运行 4 轮后停止；
- Headless：永久积压最多运行 6 轮后停止；
- Headless：重复刷新不创建新行；
- 真实桌面：正式 GameScene、MainMenu、SaveBrowserPanel 和 SaveService；
- 真实桌面：72 个世界、24 行池、三页访问、自动目录整理和截图；
- 所有 `world.json` 在整理前后逐字节不变；
- 相邻目录暂存、权威读取、目录重建、多世界恢复与 Save Recovery 回归；
- 总 Runtime、三轮 lifecycle soak、完整桌面矩阵和 Windows Release 实际导出与启动。
