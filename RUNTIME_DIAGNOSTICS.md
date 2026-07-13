# 运行诊断与发行验收

## 目标

运行诊断不是临时调试代码，而是稳定性基础设施。它必须满足：

- 不修改玩法或存档状态；
- 不拦截鼠标和键盘玩法输入；
- 不依赖具体 World、Player 或 UI 实现类；
- 可在开发窗口和正式导出包中工作；
- 可输出机器可读报告；
- 指标采集、阈值判断、预算控制和 UI 展示彼此分离；
- 源码运行正常并不能替代最终 Windows Release 验收。

## 模块

```text
Game
└─ RuntimeDiagnosticsCoordinator
   ├─ RuntimeTelemetryService
   ├─ AdaptiveStreamingController
   │  ├─ AdaptiveStreamingPolicy
   │  └─ StreamingBudgetAdapter
   └─ DiagnosticsOverlay
```

### RuntimeDiagnosticsCoordinator

组合根，负责：

- 从 `GameplayServiceHub` 获取 InputContext、GameplayInput 和 CreatureSpawner；
- 创建遥测、区块预算控制器和 F3 面板；
- 世界成功启动后挂载 World / Player；
- 返回菜单或启动失败时恢复基础预算并解除运行时引用；
- 向发行验收提供最新快照和报告写入入口。

它不计算指标、不判断阈值，也不绘制业务 UI。

### RuntimeTelemetryService

采样服务使用 `PROCESS_MODE_ALWAYS`，因此暂停界面中仍可观察状态。

每个采样窗口包含：

```text
fps
frame_sample_count
frame_ms_avg
frame_ms_peak
stutter_count
memory_mib
node_count
draw_calls
streaming {
  loaded,
  building,
  pending,
  last_work_usec,
  focus_chunk
}
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
creature_count
pickup_count
input_context
mouse_mode
paused
player_position
health {
  status,
  severity,
  healthy,
  issues[]
}
```

历史默认最多保留 120 个快照，避免诊断本身造成无界内存增长。

### RuntimeHealthPolicy

纯策略模块，不访问场景树。输入快照，输出：

```text
healthy
warning
critical
```

当前检查：

- 平均帧时间；
- 峰值帧时间；
- 采样窗口卡顿次数；
- 区块排队数量；
- 静态内存；
- 场景节点数量。

帧率评价要求达到最小帧样本数，避免把世界启动时的单个重帧误判成持续异常。

### AdaptiveStreamingController

区块构建预算控制器。它根据遥测持续调节：

```text
chunk_build_budget_ms
chunk_build_cells_per_step
max_chunk_build_steps_per_frame
chunks_per_frame
```

它不会修改玩家选择的 `render_distance`。策略、防抖、世界能力适配和 UI 展示分属不同模块，详细合同见 [ADAPTIVE_STREAMING.md](ADAPTIVE_STREAMING.md)。

### DiagnosticsOverlay

按 `F3` 切换。

展示：

- FPS、平均/峰值帧时间和卡顿次数；
- 区块加载、构建、排队和实际预算耗时；
- 自适应流式档位、预算、调整次数和原因；
- 节点、内存和 Draw calls；
- 生物、掉落物；
- 输入上下文、鼠标模式和暂停状态；
- 玩家位置；
- 健康检查原因。

整棵 UI 树必须满足：

```gdscript
mouse_filter = Control.MOUSE_FILTER_IGNORE
focus_mode = Control.FOCUS_NONE
```

诊断面板不能改变：

- `Input.mouse_mode`；
- InputContext；
- `SceneTree.paused`；
- Player 输入；
- 世界、背包或存档状态。

## Windows 发行包 Smoke

源码场景通过不代表导出的 EXE 可用。正式门禁使用：

```powershell
.\tests\release\run_windows_export_smoke.ps1 `
  -Godot C:\path\to\godot.exe
```

脚本会：

1. 使用 `Windows Desktop` preset 导出 Release；
2. 检查 EXE 与 PCK 存在且非空；
3. 启动导出的程序；
4. 传入：

```text
--verbose
--
--release-smoke
--smoke-soak-frames=180
--smoke-output=<absolute-report-path>
```

5. 创建并进入真实体素世界；
6. 跨越多个区块运行至少 180 帧；
7. 检查自适应预算、队列和健康状态；
8. 获取实际 Viewport 截图；
9. 输出 JSON、PNG 和完整 stdout/stderr；
10. 检查进程退出码、报告内容和退出资源清理。

### ReleaseSmokeRunner

只在显式命令行参数存在时启用。普通玩家启动不会创建测试世界或自动退出。

导出包内验收：

- Game 根和服务组合成功；
- 世界启动 signal 成功；
- 出生区块有可见网格和碰撞；
- WorldRoot 与 Player 可见；
- Player Camera 是 Viewport 当前相机；
- 输入上下文为 gameplay；
- RuntimeDiagnostics 和 AdaptiveStreamingController 已挂载；
- 跨区块运行期间队列和已加载区块保持有界；
- 持续健康状态不会停留在 critical；
- 自适应控制不会频繁抖动；
- Viewport 图像不是空白或单色；
- PNG 和 JSON 可以写入指定路径。

JSON `soak` 证据包含：

```text
frames
samples
max_pending_chunks
max_loaded_chunks
critical_samples
adaptive_change_count
adaptive_level
adaptive_budget_ms
final_snapshot
```

## 退出资源门禁

Release smoke 在退出前执行明确生命周期：

```text
停止生物
→ 解除诊断与世界引用
→ AudioService.shutdown
→ 等待音频服务器结算
→ AudioService.dispose
→ 清理世界区块和碰撞
→ 销毁 Game
→ 等待 SceneTree 清理
→ 退出进程
```

PowerShell 驱动会扫描导出和运行日志。以下任一内容都会直接让 CI 失败，即使 Godot 或 EXE 返回 0：

```text
SCRIPT ERROR
Parse Error
ObjectDB instances were leaked
Leaked instance:
Resources still in use at exit
```

ANGLE 后端回退或无声卡环境的已知设备警告不会被误判为资源泄漏。

## CI 证据

每个 PR 和 `master` 更新会上传：

```text
desktop-acceptance-<run>
  desktop-acceptance.png

windows-release-smoke-<run>
  StarWorld.exe
  StarWorld.console.exe（存在时）
  StarWorld.pck
  release-smoke.json
  release-smoke.png
  export.stdout.log
  export.stderr.log
  release-smoke.stdout.log
  release-smoke.stderr.log
  release-smoke.driver.log
```

源码桌面验收负责真实按钮和鼠标路由；导出包 smoke 负责最终打包产物、跨区块运行和退出清理。两者不能互相替代。

## 自动化边界

相关专项测试：

```text
runtime_diagnostics_regression.gd
adaptive_streaming_regression.gd
audio_lifecycle_regression.gd
runtime_stability_regression.gd
runtime_soak_regression.gd
desktop_acceptance_regression.gd
```

`runtime_soak_regression.gd` 连续执行三轮世界生命周期，验证区块、碰撞、生物、暂停、输入上下文和运行时引用均能回收。

## 扩展规则

新增指标时：

1. 数据采集进入 `RuntimeTelemetryService`；
2. 阈值判断进入 `RuntimeHealthPolicy`；
3. 预算决策进入 `AdaptiveStreamingPolicy`；
4. 防抖和生命周期进入 `AdaptiveStreamingController`；
5. 文本展示进入 `DiagnosticsOverlay`；
6. 必须补对应回归和发行包证据；
7. 不允许让业务模块依赖 DiagnosticsOverlay。

新增发行验收时：

1. 优先扩展 `ReleaseSmokeRunner` 的公开合同；
2. 输出结构化 JSON 证据；
3. 保持普通启动路径无副作用；
4. 必须设置超时，禁止 CI 永久挂起；
5. 不以 headless 结果替代真实窗口或导出产物；
6. 不允许仅凭退出码忽略脚本错误和资源泄漏。
