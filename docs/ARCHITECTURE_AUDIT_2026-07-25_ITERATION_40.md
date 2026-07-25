# Architecture Audit · 2026-07-25 · Iteration 40

## 范围

前序迭代已经解决大目录读取、写入、暂存、虚拟化、搜索和排序问题。本轮从玩家数据安全与长期维护角度审计存档删除链路。

## 发现

### 1. 玩家删除是一键物理删除

旧 `SaveBrowserPanel._delete_selected()` 直接调用：

```text
save_service.delete_world(world_id)
```

`delete_world()` 会逐文件删除整个世界目录，然后删除目录本身。玩家只需一次点击，操作不可撤销。

### 2. 搜索安全不等于删除安全

索引化浏览器已经在筛选隐藏选择时清空 world ID，解决“看不见却被删除”的误删风险。但当前可见世界仍可能因为误点击、手柄焦点或双击操作被立即永久删除。

### 3. 不能直接修改永久删除兼容 API

大量 Headless 和真实桌面测试使用 `delete_world()` 清理独立测试世界。直接把它改成软删除会导致测试回收站堆积，并破坏明确的维护级永久删除语义。

正确做法是保留兼容 API，同时新增玩家专用保护端口。

### 4. 只复制 world.json 不足以恢复

一个可恢复世界不仅包含 Primary，还包含：

- `catalog.json` Sidecar；
- `.bak`；
- 可能存在的 `.tmp`；
- 未来版本的目录级文件。

逐文件复制容易遗漏、部分成功或在大存档下产生长时间阻塞。完整目录的同文件系统重命名更接近原子事务。

### 5. 无界回收站会转化为磁盘风险

只增加回收站但不设置容量，会让磁盘使用随着删除次数持续增长。自动清理最旧条目又会在玩家不知情时永久删除数据。

本轮采用“容量满则拒绝新删除”，而不是自动清理。

## 决策

### 生产组合

新增：

```text
ProtectedSaveService
ProtectedSaveBrowserPanel
ProtectedMainMenu
```

正式 `main_menu.tscn` 使用 `ProtectedMainMenu`。权威 `SaveService` 不变，保护面板在传入服务没有 Trash 端口时挂载独立 `ProtectedDeletionService`。

### 二次确认

- 首次点击只记录当前 world ID；
- 按钮变为“确认移到回收站”；
- 再次点击同一选择才执行磁盘事务；
- 选择、查询、刷新、隐藏面板都会取消确认。

### 原子目录移动

```text
user://worlds/<world_id>
→ DirAccess.rename_absolute
user://world_trash/<trash_id>
```

随后写入 `trash.json` Manifest。Manifest 写失败必须尝试重命名回原目录。

### 容量与恢复

- 回收站最多 32 个世界；
- 满时返回 `trash_full`，不自动清理；
- Undo 使用原 world ID 恢复；
- ID 被占用时拒绝恢复且保留 Trash；
- 恢复后移除 `trash.json`，Primary、Sidecar 和 Backup 不重写。

### 维护 API

`delete_world()` 保持永久删除语义，仅供明确维护、测试清理或未来“清空回收站”动作使用。玩家 UI 静态合同禁止调用它。

## 真实验收设计

### 服务回归

- 真实保存两代以生成 Backup；
- 64 条稀疏修改；
- Trash 后活跃列表和加载均不可见；
- 冲突恢复拒绝；
- 恢复后 Primary、Sidecar、Backup 逐字节一致；
- 32 条容量填满；
- 第 33 条拒绝且不自动清理；
- 恢复一条后再接受一个删除。

### 面板回归

- 第一次点击不调用服务；
- 改变选择取消确认；
- 第二次点击调用 Trash 一次；
- 永久删除调用计数始终为 0；
- Undo 恢复；
- 查询隐藏选择取消确认；
- Trash 满时世界数量不变。

### 真实桌面

正式 GameScene 创建 12 个世界：

- 搜索隔离目标；
- 首击确认截图；
- 二击完整目录进入回收站；
- 活跃列表 12→11；
- Undo 后 11→12；
- Primary、Sidecar、Backup 逐字节不变；
- 16 条真实稀疏修改完整加载；
- 隐藏确认不移动文件；
- 三张截图和 JSON。

### 全量门禁

最终固定 SHA 必须通过：

- 静态合同、严格导入；
- 服务、面板、真实桌面专项；
- 索引/虚拟化浏览器；
- 目录暂存、权威读取、目录重建、多世界恢复；
- Save Recovery、World Catalog、统一健康；
- Runtime 与三轮 lifecycle soak；
- 完整真实桌面矩阵；
- Windows Release 实际导出和启动。

## 结论

本轮将存档删除从“单击永久销毁”升级为“二次确认、完整目录原子回收、32 条容量、冲突安全恢复和可撤销 UI”。同时保留维护级永久删除兼容 API，避免把玩家安全功能扩散到测试和基础存档合同中。
