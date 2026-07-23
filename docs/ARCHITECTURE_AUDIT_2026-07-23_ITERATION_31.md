# Architecture Audit · 2026-07-23 · Iteration 31

## 范围

本轮审计 Runtime Telemetry、F3、ServiceHub、世界保存、轻量目录，以及机器、农业、畜牧、牧场、生态、掉落和结构完整性已有诊断。目标是把真实预算与保存证据汇聚为一个玩家和开发者都可读的健康报告，而不是再造平行监控域。

## 审计发现

### 1. F3 只覆盖通用运行指标

原 F3 能显示 FPS、帧时间、Chunk 队列、内存、节点、输入、角色速度和碰撞，但无法看到：

- 机器总量与调度领域；
- 作物、动物、牧场产物；
- 生态容量；
- 物理掉落节点预算；
- 结构候选溢出或物品回退；
- 世界目录回退、自愈和耗时；
- 最近一次真实保存的字节与耗时。

各领域已有有界 Snapshot，缺少的是统一只读投影，而不是新的状态来源。

### 2. 让 Overlay 直接遍历 ServiceHub 会破坏边界

最直接的实现是让 `DiagnosticsOverlay` 查找所有服务并读取 Dictionary，但这会：

- 把领域结构和 UI 强耦合；
- 诱使显示层直接修改 Dictionary；
- 在 UI 刷新时复制大型机器、作物或动物状态；
- 形成与 Telemetry 不同的采样时刻；
- 难以在无窗口环境中单元测试。

因此 UI 只接收白名单报告，不能拥有服务发现和健康判断。

### 3. 新建第二个 Timer 会产生两条时间线

现有 `RuntimeTelemetryService` 已经以 0.5 秒周期采样，并保留最多 120 条历史。另建健康 Timer 会让：

```text
左栏帧 / Chunk 快照时间 A
右栏领域 / 保存快照时间 B
```

导出报告和屏幕显示可能互相矛盾。统一健康必须成为同一 Telemetry snapshot 的 `operations` 字段。

### 4. 保存耗时不能由 SaveService 猜测

`SaveService.save_world()` 是权威原子写入所有者，但最终游戏保存还包括 ServiceHub 各参与者的 `save_into()`、玩家状态和世界投影。只在 `SaveService` 内计时会漏掉上游组装成本。

最终 Hub 应包装完整 `save_current()` 调用，保留原返回值，再记录实际端到端耗时和已提交文件长度。它不能替换原子存储或把统计写回存档。

### 5. 健康报告必须有固定大小

某些已有 Snapshot 含有有界但仍较大的子字典，例如：

- machine `domains`；
- agriculture `crop_counts`；
- ecology `species_counts`；
- lifecycle participants；
-最近批次的逐领域摘要。

即使这些来源本身有边界，F3 也不应复制它们。最终报告只保留 12 行和 8 条问题，并使用固定字段白名单。

### 6. “当前最主要瓶颈”必须确定

如果多个领域同时处于警告，字典遍历顺序不能决定展示结果。排序合同为：

```text
严重度降序
→ 预算利用率降序
→ 稳定 ID 升序
```

因此同一快照在测试、桌面和 Release 中得到同一主要瓶颈。

## 决策

### 纯健康策略

新增 `RuntimeHealthReportPolicy`：

- 不继承 Node；
- 不访问 SceneTree、文件或 Timer；
- 只接收 Snapshot Dictionary；
- 只输出白名单投影；
- 统一 75% 警告与 90% 严重阈值；
- 支持保存失败、结构溢出、掉落拒绝和目录自愈等显式事件覆盖。

### 只读聚合服务

新增 `RuntimeHealthReportService`，固定读取 11 个来源，不遍历 ServiceHub 子节点：

```text
streaming
machines
agriculture
husbandry
animal attraction
animal products
ecology
pickups
structural integrity
catalog
save evidence
```

服务没有 `_process` 或 Timer，不创建历史，也不序列化状态。

### 最终 Hub 组合

新增 `RuntimeHealthServiceHub` 作为 `service_hub.tscn` 的最终脚本：

- 在所有既有参与者安装后创建稳定 `RuntimeHealthReport` 节点；
- 世界启动时记录 ID；
- attach 时只绑定当前世界引用；
- 保存时包装完整 `super.save_current()`；
- 菜单、失败和退出时释放引用并断开信号。

原 `ExplorationProgressionServiceHub` 和所有领域参与者保持兼容，不需要知道健康报告存在。

### 同一 Telemetry 时间线

`RuntimeDiagnosticsCoordinator` 将最终 Hub 传入现有 Telemetry。每次 `sample_now()` 在同一快照中生成：

```text
frame / memory / streaming / input
operations
health（包含 operations 严重度）
```

Telemetry history 上限仍为 120，没有第二个采样循环。

### 双栏 F3

`DiagnosticsOverlay` 保留左栏全部原诊断，在右栏使用纯 `RuntimeHealthReportFormatter` 展示：

- 当前运行与保存状态；
- 主要压力；
- 12 行固定领域摘要；
- 保存会话计数；
- 世界目录累计。

面板使用全屏安全边距和两列等宽布局，在 1280×720 与 1024×576 下保持可读，全部 Control 继续鼠标穿透。

## 真实验收设计

Windows 桌面旅程使用正式 `GameScene`、最终 ServiceHub、正式 SaveService 和正式 F3：

```text
创建世界
→ 等待流式稳定
→ 真实 save_current
→ 删除 catalog.json
→ list_worlds 权威回退并自愈
→ Telemetry sample
→ F3 键盘事件
→ 1280×720 截图与 JSON
→ 再次 list_worlds 验证稳态命中
→ 菜单清理与删除临时世界
```

必须证明：

- 保存成功、字节和耗时均可测；
- 缺失目录不隐藏世界；
- 本次 fallback 与 repair 至少各一次；
- catalog 成为该快照的确定性主要瓶颈；
- F3 同时显示原运行诊断和统一健康；
- 报告不含 `block_overrides`、`crop_counts`、`species_counts`、participant dependencies 或 domain summaries；
- 第二次目录扫描回到纯命中；
- UI 不抢鼠标；
- stderr 无脚本、解析或资源泄漏错误。

## 测试沉淀

新增：

```text
src/diagnostics/runtime_health_report_policy.gd
src/diagnostics/runtime_health_report_service.gd
src/diagnostics/runtime_health_report_formatter.gd
src/ui/runtime_health_service_hub.gd
tests/qa/runtime_health_report_policy_regression.gd
tests/qa/runtime_health_report_regression.gd
tests/qa/runtime_health_report_desktop_acceptance.gd
tests/developer_b/validate_runtime_health_report.ps1
.github/workflows/runtime-health-report-tests.yml
docs/RUNTIME_HEALTH_REPORT.md
```

升级：

```text
scenes/ui/service_hub.tscn
src/diagnostics/runtime_diagnostics_coordinator.gd
src/diagnostics/runtime_telemetry_service.gd
src/diagnostics/runtime_health_policy.gd
src/ui/diagnostics_overlay.gd
tests/run_all.ps1
docs/PRODUCT_ROADMAP.md
```

## 后续建议

统一健康报告完成后，下一阶段优先做“长期规模与恢复”：周期性真实保存、多世界目录增长、存档损坏/备份恢复/目录重建组合，以及 Release 环境加载与退出资源报告。新内容和跨 Chunk 自动化继续以真实瓶颈证据为前置条件。
