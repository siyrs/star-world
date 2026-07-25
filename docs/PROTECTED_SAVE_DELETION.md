# 受保护的存档删除合同

## 问题

旧存档浏览器的玩家删除路径为：

```text
选择世界
→ 点击“删除所选”
→ 立即逐文件删除目录
→ 不可撤销
```

即使查询和隐藏选择已经安全化，一次误点击仍会永久删除 `world.json`、`catalog.json`、`.bak` 与可能存在的 `.tmp`。

## 兼容边界

现有 `SaveService.delete_world()` 保持不变，用于测试清理、维护工具和明确的永久删除流程。

玩家界面不得调用该 API。正式菜单通过独立 `ProtectedSaveService` 使用：

```text
trash_world(world_id)
restore_trashed_world(trash_id)
```

这样保存、加载、迁移、目录恢复和 F3 合同不需要改变。

## 二次确认

第一次点击“删除所选”只会：

```text
记录当前 world ID
→ 按钮变为“确认移到回收站”
→ 显示可撤销说明
```

它不会调用任何磁盘操作。

只有在选择未改变、查询未隐藏目标，并再次点击同一按钮时，才允许进入回收站事务。

以下行为会立即取消确认：

- 选择另一世界；
- 搜索或排序重新应用；
- 当前选择被筛选隐藏；
- 刷新列表；
- 关闭存档面板。

## 原子回收站

回收站目录为：

```text
user://world_trash
```

删除时对完整世界目录执行同文件系统原子重命名：

```text
user://worlds/<world_id>
→
user://world_trash/<trash_id>
```

完整目录一起移动，因此保留：

- `world.json` Primary；
- `catalog.json` Sidecar；
- `world.json.bak`；
- `world.json.tmp`；
- 目录中的未来兼容文件。

目录移动成功后写入固定白名单 `trash.json`：

```text
version
trash_id
world_id
name
map_id
seed
save_bytes
deleted_unix
deleted_unix_usec
deleted_at
```

`deleted_unix_usec` 是跨会话可比较的 Unix 微秒时间戳。多个世界在同一秒内快速删除时，撤销顺序仍按真实操作时间确定；旧 Manifest 缺少该字段时回退到秒级时间，以保持兼容。

如果 Manifest 写入失败，系统必须把目录重命名回原位置。回滚也失败时记录明确诊断，不能假装删除成功。

## 32 条容量边界

```text
MAX_TRASH_ENTRIES := 32
```

回收站已满时，新删除返回 `trash_full`，原世界保持活跃。

系统不会为了腾出空间而自动永久清理旧存档。释放空间必须通过恢复或明确的维护级 `purge_trashed_world()`。

物理回收站目录即使 Manifest 损坏也占用容量，并通过 `invalid_entry_count` 暴露；系统不会因损坏 Manifest 而绕过 32 条硬上限。

## 撤销恢复

“撤销删除”恢复最近的有效回收站条目：

```text
回收站目录
→ 原 world ID 目录
→ 删除内部 trash.json
→ 重新进入正常 list_worlds()
```

如果原 world ID 已被重新占用，恢复返回 `world_exists`，回收站条目保持不变。

恢复不会生成新 world ID，也不会重写 Primary、Sidecar 或备份。

恢复完成后：

- 清空当前查询，让恢复世界可见；
- 重新构建正常存档索引；
- 已消费条目不能重复恢复；
- 若回收站仍有更早条目，撤销按钮指向新的最近条目。

## 状态所有权

权威保存服务继续负责：

- 创建；
- 保存；
- 加载；
- 迁移；
- 恢复；
- 目录投影。

保护服务只负责完整目录移动、Manifest、容量和恢复。

正式 `ProtectedSaveBrowserPanel` 在传入服务没有回收站端口时，挂载一个独立 `ProtectedDeletionService`。两者共享文件目录，但不共享可变世界 Dictionary。

## 有界诊断

`get_trash_diagnostics()` 只返回固定标量：

```text
trash_capacity
trash_entry_count
invalid_entry_count
trash_success_count
restore_success_count
purge_success_count
failure_count
last_operation
last_reason
last_world_id
last_trash_id
undo_available
```

没有世界 payload、无限历史或目录内容复制。

## 真实验收

### Headless 服务

- Primary、Sidecar、Backup 完整移动；
- 活跃列表和加载立即排除已删除世界；
- 原 ID 冲突时拒绝恢复且不消费条目；
- 恢复后 Primary、Sidecar、Backup 逐字节一致；
- 64 条稀疏修改完整加载；
- 第 33 个删除因容量拒绝；
- 同一秒内快速删除仍精确指向最新 Undo 条目；
- 恢复一个条目后可接受原本被阻止的世界；
- 不自动清理任何旧条目。

### Headless 面板

- 第一次点击只确认；
- 第二次点击才调用 `trash_world()`；
- 永不调用 `delete_world()`；
- 选择变化和筛选隐藏会取消确认；
- Undo 恢复并清空查询；
- `trash_full` 保持世界不变。

### 真实 Windows 桌面

正式 `GameScene`、最终 `ServiceHub`、真实 `SaveService`、正式 `MainMenu` 和 `ProtectedSaveBrowserPanel`：

- 创建 12 个真实世界；
- 目标拥有 Primary、Sidecar、Backup 和 16 条稀疏修改；
- 首击截图证明文件未变；
- 二击后完整目录进入回收站；
- 活跃列表从 12 降为 11；
- Undo 恢复后回到 12；
- Primary、Sidecar、Backup 逐字节不变；
- 完整加载恢复全部修改；
- 筛选隐藏已确认目标时不移动任何文件；
- 输出确认、删除、恢复三张截图与机器可读 JSON。

## 合入门禁

- 新静态合同和严格 Godot 导入；
- 服务、面板与真实桌面专项；
- Indexed/Virtualized Save Browser；
- World Catalog、Save Recovery、Bounded Read/Write/Trash；
- Runtime 与三轮 lifecycle soak；
- 完整桌面输入/UI 矩阵；
- Windows Release 实际导出和启动。
