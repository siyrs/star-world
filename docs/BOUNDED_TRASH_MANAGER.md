# 有界存档回收站管理合同

## 背景

受保护删除已经保证：

- 玩家删除需要二次确认；
- 完整世界目录原子进入 `user://world_trash`；
- 回收站最多 32 个物理目录；
- 最近一次有效删除可通过 Undo 恢复；
- Primary、Sidecar 和 Backup 不被重写。

但仅有“撤销最近一次”不能形成长期可用闭环：

- 玩家无法恢复更早的指定世界；
- 回收站达到 32 条后无法从 UI 释放容量；
- Manifest 损坏的物理目录占用容量，却没有安全管理入口；
- 永久清理若没有独立二次确认，会重新引入不可逆误操作。

## 状态所有权

`ProtectedSaveService` 继续作为回收站唯一状态所有者。

新增只读投影：

```text
list_trash_slots(limit = 32)
```

它返回最多 32 个严格白名单槽位，不返回世界 payload：

```text
trash_id
world_id
name
map_id
seed
save_bytes
deleted_unix
deleted_unix_usec
deleted_at
valid
restorable
purgeable
reason
```

有效 Manifest 产生可恢复槽位；缺失或损坏 Manifest 产生：

```text
valid = false
restorable = false
purgeable = true
reason = manifest_missing_or_invalid
```

不安全目录名只显示诊断，不允许 UI 拼接路径或清理。

## 物理容量与损坏条目

容量根据 `user://world_trash` 下的物理目录数量计算，而不是有效 Manifest 数量。

```text
MAX_TRASH_ENTRIES := 32
MAX_TRASH_SCAN_ENTRIES := 64
```

- 正常生产状态最多 32 个物理目录；
- 损坏 Manifest 仍占用一个容量单位；
- 扫描最多检查 64 个目录，异常外部溢出通过 `overflow_entry_count` 报告；
- 管理页每次只投影 32 个槽位，清理后下一批异常条目才进入窗口；
- 不自动永久清理任何玩家数据。

## 跨会话顺序

每次删除写入 Unix 微秒时间戳，并保证：

```text
deleted_unix_usec = max(now_usec, previous_latest_usec + 1)
```

因此即使系统时钟分辨率不足或同一秒快速连续删除，跨会话排序仍严格单调。Trash ID 只用于时间完全相同时的确定性 tie-break。

## 管理页预算

`SaveTrashManagerPanel` 固定拥有：

```text
MAX_VISIBLE_ROWS := 24
MAX_TRASH_ENTRIES := 32
```

行为合同：

- 最多两页；
- 创建时只分配 24 行；
- 隐藏管理页只绑定服务，不执行目录扫描；
- 首次打开页面时执行一次有界扫描；
- 翻页只重新绑定行，不调用 `list_trash_slots()`；
- 显式刷新、恢复或永久清理后才重新扫描一次；
- 不使用 Timer、Thread 或逐条后台任务；
- 页面显示物理容量、有效条目、损坏条目与异常溢出。

## 指定恢复

每个有效行提供“恢复”按钮，也可选中后使用“恢复所选”。

恢复调用：

```text
restore_trashed_world(trash_id)
```

它必须：

- 精确恢复所选 Trash ID，而不是最近一次；
- 使用原 world ID；
- 原 ID 冲突时拒绝且不消费条目；
- 恢复完整目录；
- 删除内部 `trash.json`；
- 不重写 Primary、Sidecar 或 Backup；
- 重新进入正常 `list_worlds()` 与索引路径。

损坏条目的恢复按钮必须禁用。

## 永久清理

管理页是玩家唯一可见的永久清理入口。

第一次点击“永久清理所选”只会：

```text
记录当前 trash_id
→ 按钮变为“确认永久清理”
→ 显示不可撤销警告
```

第二次点击同一条目才调用：

```text
purge_trash_slot(trash_id)
```

以下行为取消确认：

- 选择另一条目；
- 翻页；
- 刷新；
- 关闭管理页。

`purge_trash_slot()` 可以清理有效或损坏 Manifest 的安全物理目录，但不能操作不安全目录名。

## 生产组合

正式存档浏览器新增“管理回收站”按钮。

```text
ProtectedSaveBrowserPanel
├─ Active Save Browser
└─ SaveTrashManagerPanel
```

管理页作为同一存档面板内的覆盖层：

- 返回时恢复已有索引化存档浏览器；
- 恢复世界后刷新底层活动世界索引；
- 永久清理只更新回收站和 Undo 状态；
- 不修改 `MainMenu`、`SaveService` 或世界 Dictionary。

## 有界诊断

`get_trash_diagnostics()` 增加：

```text
trash_scan_capacity
valid_entry_count
invalid_entry_count
overflow_entry_count
scan_count
latest_deleted_unix_usec
```

所有字段都是固定标量，不暴露目录列表或世界 payload。

## 永久测试

### 服务层

- 四个世界快速连续删除；
- 跨 Service 重建保持最新有效 Undo；
- 一个 Manifest 损坏后仍计入物理容量；
- 损坏槽位可见、不可恢复、可清理；
- 精确恢复较旧的指定条目；
- Primary、Sidecar、Backup 逐字节一致；
- 48 条稀疏修改完整加载；
- 清理损坏槽位精确释放一个容量单位。

### UI 层

- 32 条形成 24 + 8 两页；
- 翻页不增加服务扫描；
- 损坏行禁用恢复；
- 首次永久清理只确认；
- 改变选择取消确认；
- 二次点击只清理所选槽位；
- 指定恢复较旧条目；
- 玩家管理页永久删除活动世界调用为 0。

### 真实 Windows 桌面

正式 `GameScene` 创建 33 个真实世界：

- 32 个进入回收站，1 个因容量保持活跃；
- 其中 1 个 Manifest 被损坏；
- 管理页显示 31 有效 + 1 损坏和两页固定行池；
- 指定恢复较旧世界，完整验证 Primary、Sidecar、Backup 与 16 条修改；
- 永久清理损坏槽位先确认后执行；
- 释放容量后，原本被阻止的第 33 个世界可以进入回收站；
- 返回活动浏览器后，恢复世界可立即搜索；
- 输出完整、确认和收敛三张截图与机器可读 JSON。

## 合入门禁

- 静态合同与严格 Godot 导入；
- 服务、UI 和真实桌面专项；
- Protected/Indexed/Virtualized Save Browser；
- World Catalog、Save Recovery、Bounded Read/Write/Recovery；
- Runtime 与三轮 lifecycle soak；
- 完整桌面输入/UI 矩阵；
- Windows Release 实际导出和启动。
