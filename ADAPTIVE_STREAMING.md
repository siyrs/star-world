# 自适应区块流式架构

## 目标

区块生成和网格构建必须在两类风险之间取得平衡：

- 构建过快会抢占主线程，造成鼠标、移动和 UI 卡顿；
- 构建过慢会让玩家走到空白边界，或让队列长期积压。

本模块只动态调整**区块构建工作预算**，不修改玩家选择的视距、画质或世界内容。

## 运行时结构

```text
RuntimeDiagnosticsCoordinator
├─ RuntimeTelemetryService
├─ AdaptiveStreamingController
│  ├─ AdaptiveStreamingPolicy
│  └─ StreamingBudgetAdapter
└─ DiagnosticsOverlay
```

### AdaptiveStreamingPolicy

纯决策模块。输入一个遥测快照和当前档位，输出目标档位及原因，不访问场景树。

当前输入：

```text
frame_sample_count
frame_ms_avg
frame_ms_peak
stutter_count
streaming.pending
input_context
paused
world_attached
```

当前档位：

```text
conservative  保守
 guarded      受限
 balanced     均衡
 throughput   吞吐
```

### StreamingBudgetAdapter

能力适配器。它只依赖目标对象公开以下属性：

```text
chunk_build_budget_ms
chunk_build_cells_per_step
max_chunk_build_steps_per_frame
chunks_per_frame
```

因此控制器不直接依赖 `VoxelWorld` 类型。未来其他世界实现只要满足同一合同即可接入。

所有写入都会被限制在世界允许的安全范围：

```text
budget_ms              0.5 .. 12.0
cells_per_step          256 .. 8192
max_steps_per_frame     1 .. 8
chunks_per_frame        1 .. 4
```

### AdaptiveStreamingController

有状态协调器，负责：

- 世界挂载时捕获基础预算；
- 热身窗口；
- 压力确认窗口；
- 恢复确认窗口；
- 调整后的冷却窗口；
- 每分钟最大普通调整次数；
- 严重帧压力绕过普通限速并立即降载；
- 禁用、退出世界和节点释放时恢复基础预算。

控制器不会：

- 修改 `render_distance`；
- 修改存档；
- 暂停世界；
- 控制玩家输入；
- 操作 UI；
- 直接创建或删除区块。

## 决策规则

### 降载

以下任一情况达到严重阈值时，最多一次降低两个档位：

```text
平均帧时间 >= 35 ms
峰值帧时间 >= 75 ms
采样窗口卡顿次数 >= 5
```

一般压力需要连续多个采样窗口确认：

```text
平均帧时间 >= 23 ms
峰值帧时间 >= 45 ms
采样窗口卡顿次数 >= 2
```

### 恢复与提速

只有同时满足下列条件，才累计恢复确认：

```text
平均帧时间 <= 17.5 ms
峰值帧时间 <= 30 ms
卡顿次数 == 0
```

低于均衡档时先逐步恢复到基础预算。达到均衡档后，只有区块队列仍有积压才允许进入吞吐档。

### 暂停与非游戏上下文

下列状态保持当前预算，不做调整：

```text
pause / death 等暂停状态
menu / loading / inventory / crafting / container
世界未连接
帧样本不足
调整冷却中
```

## 档位预算

档位基于世界启动时捕获的基础配置计算，且保持单调性：

- 保守与受限档绝不会高于基础预算；
- 吞吐档绝不会低于基础预算；
- 自定义的极低或极高基础配置不会因档位切换被反向修改；
- 退出世界时会准确恢复原基础值。

默认基础配置为：

```text
4.0 ms
2048 cells / step
2 steps / frame
1 completed chunk / frame
```

## 遥测与 F3

`RuntimeTelemetryService` 在快照中新增：

```text
adaptive_streaming {
  enabled,
  attached,
  level,
  level_name,
  profile,
  baseline,
  warmup_remaining,
  cooldown_remaining,
  pressure_streak,
  headroom_streak,
  change_count,
  recent_change_count,
  last_reason,
  last_decision_code
}
```

F3 面板显示当前档位、预算、单步格数、单帧步骤、调整次数和最后决策原因。面板仍是纯展示层，不拦截鼠标或键盘。

## 生命周期不变量

每次世界会话必须满足：

```text
menu
  → attach world
  → capture baseline
  → warmup
  → adaptive control
  → save and return
  → restore baseline
  → detach world references
  → clear chunks / collisions / creatures / pause
```

`runtime_soak_regression.gd` 会连续执行三轮真实世界会话，并验证：

- 区块队列和已加载区块有界；
- 控制器不会频繁抖动；
- 玩家视距设置不被改写；
- 返回菜单后区块、碰撞和生物清空；
- InputContext 恢复为 menu；
- SceneTree 暂停被清除；
- 控制器不保留旧世界引用；
- 遥测历史不超过固定上限。

## 发行包门禁

真实 Windows Release smoke 会运行至少 180 帧并跨越多个区块，输出：

```text
soak.frames
soak.samples
soak.max_pending_chunks
soak.max_loaded_chunks
soak.critical_samples
soak.adaptive_change_count
soak.adaptive_level
soak.adaptive_budget_ms
```

发布脚本还会扫描导出和运行日志。以下任一内容都会让 CI 失败，即使进程退出码为 0：

```text
SCRIPT ERROR
Parse Error
ObjectDB instances were leaked
Leaked instance:
Resources still in use at exit
```

## 扩展规则

增加新性能输入时：

1. 数据采集进入 `RuntimeTelemetryService`；
2. 纯阈值和档位决策进入 `AdaptiveStreamingPolicy`；
3. 世界写入仍通过 `StreamingBudgetAdapter`；
4. 防抖与生命周期进入 `AdaptiveStreamingController`；
5. 展示进入 `DiagnosticsOverlay`；
6. 必须同时补策略测试、真实生命周期 soak 和导出包 smoke。

禁止让 Player、GameUI、VoxelChunk 或 GameplayServiceHub 复制自适应阈值判断。
