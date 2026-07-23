# 自愈式权威存档恢复合同

## 目标

`world.json` 是世界状态的唯一权威文件。原子写入已经保留 `.tmp` 与 `.bak`，但旧读取路径只把恢复候选返回到内存，不会重建损坏的主文件。因此同一个世界可能在每次加载时重复恢复，轻量目录还可能按损坏主文件的字节数重建。

本合同要求：一次成功恢复必须把权威主文件重新变为可用状态，同时保留有效备份、保持旧世界兼容，并把恢复证据投影到存档浏览器和 F3。

## 候选顺序

固定读取顺序为：

```text
world.json
→ world.json.tmp
→ world.json.bak
```

临时文件代表可能尚未完成提交的更新一代，因此优先于较旧备份。最多只记录三个候选来源，诊断大小不会随世界内容增长。

## 语法与语义验证

仅能解析为 JSON Dictionary 不代表世界可加载。以下属于**语义损坏**：

- `metadata` 不是 Dictionary；
- `player` 不是 Dictionary；
- `world` 不是 Dictionary；
- `world.block_overrides` 不是 Dictionary；
- metadata 中存在与目录不一致的世界 ID。

恢复验证只检查长期稳定的核心结构，不强制要求 Agriculture、Machine、Husbandry 或 Exploration 等新领域，以保持旧世界兼容。缺失的新领域继续由既有迁移层补齐。

## 原子主文件修复

从 `.tmp` 或 `.bak` 读到有效候选后：

```text
候选数据
→ 写入 world.json.recover
→ 重新解析恢复暂存文件
→ 将损坏主文件移动为 world.json.corrupt
→ 将恢复暂存原子提升为 world.json
→ 删除过期 .tmp 与 .corrupt
```

恢复路径不会调用普通保存轮换，因此不会把损坏主文件覆盖到唯一的**有效备份**上。成功后必须继续保留 `.bak`。

若主文件移动或恢复暂存提升失败：

- 已读取的有效候选仍可用于本次加载；
- 原候选不被删除；
- 记录主文件修复失败；
- 下一次访问继续尝试；
- 不生成声称主文件健康的新目录 sidecar。

## 目录一致性

`catalog.json` 是可丢弃派生数据。目录只在主文件重新可用后自愈：

```text
primary 原本有效
或
fallback 已成功提升为 primary
```

若主文件修复失败，世界仍可从候选显示和加载，但不会写入与损坏主文件长度绑定的新目录。成功修复后，目录中的 `save_bytes` 必须等于新 `world.json` 的实际长度。

下一次目录扫描必须是 sidecar 命中，下一次完整加载必须直接读取 primary，从而证明 **0 次重复恢复**。

## 固定大小诊断

`SaveService.get_recovery_diagnostics()` 只返回会话标量和最多三个来源：

```text
recovery_count
repair_attempt_count
repair_success_count
repair_failure_count
primary_rejection_count
last_world_id
last_source
last_repaired
last_candidate_bytes
last_primary_bytes
last_elapsed_usec / milliseconds
last_rejected_sources[<=3]
```

这些字段不进入世界存档，不复制世界 Dictionary，也不建立新 Timer 或历史队列。

## 玩家可见反馈

存档浏览器在目录耗时后追加：

```text
已自愈 N 个存档
主文件修复失败 N
```

统一 F3 保存行同时显示：

```text
恢复次数
主文件修复成功 / 失败
最后恢复来源
恢复耗时
```

成功自愈为警告证据；候选可读但主文件修复失败为严重状态。

## 永久验收

Headless 回归覆盖：

- 可解析但核心结构无效的 primary；
- backup 恢复与原子主文件重建；
- temporary 优先于旧 backup；
- 有效 `.bak` 始终保留；
- `.tmp`、`.recover`、`.corrupt` 在成功后清零；
- 目录只在主文件健康后重建；
- 下一次目录纯命中与下一次加载 0 次重复恢复；
- F3 成功修复警告和修复失败严重状态。

真实 Windows 旅程使用正式 GameScene、SaveService、SaveBrowserPanel、Runtime Telemetry 和 F3：创建多代世界、写入可解析损坏、从 backup 自愈、截图、点击“继续”、恢复完整稀疏世界状态，并生成 JSON 与 stdout/stderr Artifact。

最终候选仍必须通过权威总 Runtime、三轮 lifecycle soak、完整桌面输入/UI 矩阵和 Windows Release 实际导出与启动。
