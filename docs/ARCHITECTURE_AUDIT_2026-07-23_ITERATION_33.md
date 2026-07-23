# Architecture Audit · 2026-07-23 · Iteration 33

## 范围

本轮沿“长期规模与恢复”路线继续审计世界存档、备份恢复、轻量目录与统一运行健康之间的组合边界。重点不是增加第三份持久副本，而是确认现有 `.tmp` / `.bak` 在主文件损坏后能否真正恢复长期稳定状态。

## 发现

### 1. 恢复只发生在内存

旧 `AtomicJsonStore.read_dictionary()` 在 primary 失败后会返回 temporary 或 backup，但不会重建 `world.json`。结果是：

```text
每次进入世界
→ 再次发现损坏 primary
→ 再次读取同一 fallback
→ 再次发出恢复事件
```

玩家本次可以继续，但磁盘状态永远没有恢复。

### 2. 可解析不等于有效世界

旧原子存储只检查 JSON 是否能解析为 Dictionary。像下面这样的内容属于**可解析但无效**：

```json
{
  "metadata": {"id": "world-a"},
  "player": "broken",
  "world": {"block_overrides": "broken"}
}
```

它会阻止系统继续检查健康 backup，随后迁移层可能把部分缺失领域补成默认值，掩盖实际损坏。

### 3. 普通保存不能直接用于恢复提升

若从 `.bak` 读取成功后直接调用普通 `write_dictionary()`：

```text
删除旧 .bak
→ 将损坏 primary 重命名为 .bak
→ 写入恢复数据
```

这会用损坏主文件**覆盖唯一有效备份**。即使新 primary 写入成功，故障窗口内也失去了最后的健康候选。

### 4. 目录可能为损坏主文件背书

旧 `list_worlds()` 从 backup 得到 metadata 后，仍使用损坏 `world.json` 的文件长度创建 `catalog.json`。恢复后目录可能稳定命中，但完整加载仍在不断读取 backup，形成两个互相矛盾的“健康”信号。

## 决策

### 稳定核心语义验证

在 AtomicJsonStore 增加可注入 validator。SaveService 只验证 metadata、player、world、block overrides 和世界 ID 这些跨版本稳定结构。新领域仍由迁移层补齐，避免破坏旧世界。

### 独立恢复暂存

恢复使用 `.recover`，损坏 primary 临时移动为 `.corrupt`。新 primary 提升成功后删除过期 `.tmp` / `.corrupt`，但不修改 `.bak`。提升失败时恢复原 primary 路径并保留候选。

### 恢复后目录才能自愈

只有 primary 原本有效，或 fallback 已成功提升为 primary，才允许写入新的 `catalog.json`。目录字节数必须来自新 primary 的实际长度。

### 恢复可观测但有界

SaveService 只保留计数、最后来源、字节、耗时和最多三个被拒来源。存档浏览器显示本会话自愈数量，F3 将成功修复标记为警告、修复失败标记为严重。

## 永久测试设计

Headless 测试使用真实 AtomicJsonStore 与 SaveService，覆盖：

- parseable semantic corruption；
- backup 与 temporary 顺序；
- backup preservation；
- primary promotion；
- catalog byte binding；
- steady sidecar hit；
- zero repeated recovery；
- F3 recovery severity。

真实桌面测试使用正式 GameScene：创建三代存档、损坏 primary、打开存档浏览器、截图自愈状态、打开 F3、点击继续并核对完整世界覆盖。所有日志继续经过脚本错误、解析错误、ObjectDB 和资源泄漏扫描。

## 合入门禁

固定候选必须完成：

- 新恢复专项的严格导入、静态合同、Headless 与真实桌面；
- World Catalog、Runtime Health、Integration 等相邻回归；
- 权威总 Runtime 与三轮 lifecycle soak；
- 完整真实桌面输入/UI 矩阵；
- Windows Release 实际导出、启动与 Artifact。

在真实桌面和 Windows Release 全部成功前，PR 保持 Draft，不同步 `master`。
