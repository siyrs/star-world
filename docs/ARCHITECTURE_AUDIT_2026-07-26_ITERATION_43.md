# Architecture Audit · 2026-07-26 · Iteration 43

## 范围

本轮从上一版有界自动保存、统一运行健康和 Windows Release 证据继续审计保存可观察性与生命周期身份，扫描：

- `RuntimeHealthServiceHub`、`RuntimeHealthReportService` 与 F3 formatter；
- 自动保存参与者的真实保存调用窗口；
- 暂停菜单手动保存和返回主菜单最终保存；
- 运行健康历史、世界 ID 与 `world.json` 边界；
- 领域、真实桌面、CI 和发行门禁。

## 发现

### P0 · 保存来源不可见

运行健康只统计成功、失败、字节和耗时。手动保存、自动保存、返回主菜单保存都汇入同一组数字，出现失败时无法判断是哪条玩家旅程触发，也无法确认自动保存是否真的执行。

### P1 · 只保留最后一次结果

最近一次结果会覆盖前一次。自动保存成功后紧接手动保存，或者返回主菜单失败后恢复成功，历史关系会丢失。直接保留无限列表又会让长时间运行诊断无界增长。

### P1 · 成功退出后保留旧世界 ID

保存失败时保留 world attachment 是正确的，但成功返回主菜单后报告仅 detach world 引用，没有显式结束世界身份。下一世界开始前查询健康快照可能仍看到旧世界 ID。

### P1 · 给每条保存路径复制 API 会形成平行保存域

为自动、手动和退出各增加一个保存方法会复制 payload 构造、原子写入与信号语义。正确做法是在组合根维护同步、短生命周期的来源上下文，同时仍调用唯一 `save_current()`。

## 决策

1. `RuntimeHealthReportService` 成为检查点时间线唯一状态所有者；
2. 固定保留最近 12 条事件，形成**有界历史**，累计来源计数和淘汰数保持精确；
3. 来源严格限定为 manual、autosave、return_to_menu、system；
4. 自动保存来源通过其真实 `saving` 窗口推断，不改写自动保存领域，也不增加另一条写盘 API；
5. 返回主菜单只设置同步上下文并复用原事务；
6. 成功返回或启动失败调用 `end_world()`，保存失败继续保留世界身份；
7. F3 通过纯 formatter 展示来源、历史预算、最近检查点与下一次自动保存；
8. 时间线完全不进入 `world.json`。

## 实现

- 新增 `SaveCheckpointTimelinePolicy` 与 `SaveCheckpointTimelineFormatter`；
- 健康报告记录 sequence、来源、结果、字节、耗时与单调时间；
- 12 条历史、4 类来源、当前世界过滤和自动保存倒计时均使用严格白名单；
- `RuntimeHealthServiceHub.save_current_with_reason()` 为未来维护调用提供显式上下文，但仍复用原 `save_current()`；
- `return_to_menu()` 设置 return_to_menu 上下文，失败后立即恢复默认上下文；
- F3 增加保存来源、检查点历史、最近检查点和自动保存状态；
- 安全属性读取避免测试或兼容 Hub 缺少新端口时产生无效属性访问。

## 测试沉淀

```text
tests/developer_b/validate_save_checkpoint_timeline.ps1
tests/qa/save_checkpoint_timeline_regression.gd
tests/qa/save_checkpoint_timeline_desktop_acceptance.gd
.github/workflows/save-checkpoint-timeline-tests.yml
```

领域测试覆盖有界历史、精确累计、严格投影、生命周期身份、显式来源上下文和不持久化。

真实桌面验收使用真实 Escape、暂停菜单按钮、未暂停自动保存、背包变化、F3 输入、1280×720 截图和 JSON 报告。最终仍要求完整桌面矩阵和 Windows Release 成功后才能合并主分支。
