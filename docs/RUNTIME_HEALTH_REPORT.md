# 统一运行与保存健康报告

## 目标

F3 原先只展示帧率、Chunk、内存、输入和角色状态。机器、农业、畜牧、牧场、生态、物理掉落、结构完整性以及轻量世界目录都已经提供有界 Snapshot，但这些证据分散在不同领域，玩家与开发者无法快速回答：

- 哪个共享预算最接近上限；
- 最近一次真实保存用了多少字节和时间；
- 世界目录是否发生权威回退与自愈；
- 结构、掉落或流式队列是否溢出；
- 当前最主要的运行瓶颈是什么。

统一健康报告把这些只读证据加入现有 Runtime Telemetry 与 F3，不创建第二个采样循环，也不改变任何领域状态。

## 所有权

```text
领域服务
  └─ get_snapshot / get_runtime_snapshot / get_streaming_stats
       └─ RuntimeHealthReportService（只读聚合）
            └─ RuntimeHealthReportPolicy（纯评估）
                 └─ RuntimeTelemetryService.operations
                      └─ DiagnosticsOverlay（纯格式化）
```

唯一状态所有者仍是原领域服务。聚合层不调用领域写接口，不缓存完整状态，也不进入世界存档。

## 固定数据源

每次采样最多读取以下 11 个固定来源：

1. Chunk streaming；
2. Machine runtime；
3. Agriculture；
4. Husbandry；
5. Animal attraction；
6. Animal products；
7. Ecology；
8. Pickup stack runtime；
9. Structural integrity；
10. World catalog；
11. Save transaction evidence。

来源数量不是随世界内容增长的集合。报告不会遍历所有机器、作物、动物、方块覆盖或目录记录。

## 白名单投影

`RuntimeHealthReportPolicy` 输出最多 12 行、8 条问题：

```text
Chunk 排队
Chunk 已加载
机器总量
机器调度领域
农业摘要
畜牧容量
牧场跟随与产物
生态容量
物理掉落预算
结构候选与回退
世界目录命中 / 回退 / 自愈
最近保存字节与耗时
```

禁止进入报告的示例：

- machine `domains` 与逐机器状态；
- agriculture `crop_counts` 与逐作物位置；
- ecology `species_counts`；
- FeatureLifecycle participant dependency dictionaries；
- 世界 `block_overrides`；
- 背包和完整存档 payload。

## 健康等级

对于有明确容量的行：

```text
< 75%       正常
>= 75%      警告
>= 90%      严重
```

显式错误优先于比例：

- 最近保存失败：严重；
- 结构候选溢出：严重；
- 物理掉落类型队列拒绝：严重；
- 结构旧覆盖扫描截断：警告；
- 物理掉落预算延后：警告；
- 目录回退、自愈或 sidecar 写失败：警告；
- 农业世界批处理拒绝或不受支持回退：警告。

主要瓶颈按严重度、预算利用率和稳定 ID 排序，结果具有确定性。

### 运行分量与运营分量

顶层健康保留两个可独立检查的分量：

```text
runtime_severity    帧时间、卡顿、Chunk 排队、内存和节点
operations_severity 机器、农业、畜牧、牧场、生态、掉落、结构、目录和保存
severity            max(runtime_severity, operations_severity)
```

F3 仍展示合并后的最终状态，但测试和自动化可以区分“帧/流式异常”与“领域预算压力”。例如生态或已加载 Chunk 接近受控容量时，运营分量可以提示压力；只要 Chunk、节点、引用、Pause 和输入仍在硬边界内，lifecycle soak 不应把它误报成资源泄漏。

三轮 soak 因此继续严格验证原运行分量，并独立保留运营分量采样数、Chunk 上限、节点回落、世界引用释放、输入恢复、Pause 清理和生物容器归零。

## 兼容组合与保存证据

为保留已发布的生产入口，ServiceHub 继承链为：

```text
RanchProgressionServiceHub
  └─ RuntimeHealthServiceHub
       └─ ExplorationProgressionServiceHub  ← service_hub.tscn 继续使用此入口
```

`RuntimeHealthServiceHub` 包装正式 `save_current()`：

```text
调用原保存事务
→ 保留原成功 / 失败语义
→ 记录 elapsed_usec
→ 读取已提交 world.json 文件长度
→ 更新会话级聚合证据
```

该包装不替换 `SaveService`，不修改原子写入、备份恢复、迁移或目录自愈逻辑。旧测试、场景和扩展仍看到稳定的 `exploration_progression_service_hub.gd` 资源路径；健康层通过继承插入，不要求调用方迁移。

会话只保留：

- 尝试、成功、失败和恢复次数；
- 最近世界 ID；
- 最近成功状态；
- 最近字节、耗时和单调时钟时间戳。

## F3 显示

F3 继续使用同一个 `RuntimeTelemetryService`：

- 左栏：帧、Chunk、内存、输入、位置和碰撞；
- 右栏：统一运行与保存健康、主要瓶颈、12 行有界投影、保存与目录累计。

面板覆盖 1280×720 与 1024×576 安全区域，所有 Control 仍为 `MOUSE_FILTER_IGNORE` 与 `FOCUS_NONE`，不会抢夺游戏输入。

## 生命周期与持久化

`RuntimeHealthReport` 是生产 Exploration ServiceHub 继承得到的稳定子节点：

```text
_ready             创建并绑定 SaveService
_begin_world       记录当前世界 ID
attach_game        绑定当前世界只读 streaming Snapshot
save_current       记录真实保存结果
return/menu/fail   释放世界引用
_exit_tree         断开恢复信号并 shutdown
```

健康报告、会话保存计数、目录摘要、Telemetry history 和 UI 文本均不进入存档。

## 永久验收

领域测试覆盖：

- 12 行与 8 条问题硬上限；
- 75% / 90% 阈值；
- 主要瓶颈确定性；
- 保存失败、结构溢出、掉落拒绝、目录自愈；
- 完整领域 Dictionary 不逃逸；
- Telemetry 与顶层 Runtime Health 合并；
- 运行分量与运营分量可独立观察；
- 真实 F3 输入和鼠标穿透；
- 生产场景仍使用稳定 Exploration ServiceHub 入口；
- 三轮 soak 只把原帧/流式分量作为持续严重判定，同时继续验证全部生命周期硬边界。

真实 Windows 桌面旅程：

1. 创建并启动正式世界；
2. 通过生产 ServiceHub 执行真实保存；
3. 删除 `catalog.json`；
4. 调用正式 `list_worlds()` 触发权威回退和自愈；
5. 采样统一健康并要求目录成为主要瓶颈；
6. 真实按下 F3；
7. 验证双栏文本、1280×720 布局和鼠标穿透；
8. 保存截图、JSON、stdout/stderr；
9. 第二次目录扫描必须恢复稳态命中；
10. 删除临时世界并通过资源泄漏门禁。

最终还必须通过总 Runtime、三轮 lifecycle soak、完整桌面输入/UI 矩阵，以及 Windows Release 实际导出和启动。
