# 运行诊断与发行验收

## 目标

运行诊断不是临时调试代码，而是稳定性基础设施。它必须满足：

- 不修改业务状态；
- 不拦截鼠标或键盘玩法输入；
- 不依赖具体 World、Player 或 UI 实现类；
- 可在开发窗口和正式导出包中工作；
- 可输出机器可读报告；
- 指标阈值与展示分离，便于后续自适应性能策略复用。

## 模块

```text
Game
└─ RuntimeDiagnosticsCoordinator
   ├─ RuntimeTelemetryService
   └─ DiagnosticsOverlay
```

### RuntimeDiagnosticsCoordinator

组合根，负责：

- 从 `GameplayServiceHub` 获取 InputContext、GameplayInput 和 CreatureSpawner；
- 世界成功启动后挂载 World / Player；
- 返回菜单或启动失败时解除运行时引用；
- 向发行验收提供最新快照和报告写入入口。

它不计算指标，也不绘制 UI。

### RuntimeTelemetryService

采样服务，`PROCESS_MODE_ALWAYS`，因此暂停界面中仍可观察状态。

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
streaming { loaded, building, pending, last_work_usec, focus_chunk }
creature_count
pickup_count
input_context
mouse_mode
paused
player_position
health { status, severity, healthy, issues[] }
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

阈值是运行时基线，不是硬编码玩法规则。后续自动降视距、性能提示和耐久报告应复用该策略，而不是复制判断。

### DiagnosticsOverlay

按 `F3` 切换。

展示：

- FPS、平均/峰值帧时间和卡顿次数；
- 区块加载、构建、排队和预算耗时；
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
- 世界或背包状态。

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
-- --release-smoke --smoke-output=<absolute-report-path>
```

5. 等待最多 60 秒；
6. 检查进程退出码；
7. 检查 JSON 报告和 PNG 截图；
8. 检查报告 `ok=true`。

### ReleaseSmokeRunner

只在显式命令行参数存在时启用，普通玩家运行不会创建测试世界或自动退出。

导出包内验收：

- Game 根和服务组合成功；
- 世界启动 signal 成功；
- 出生区块有可见网格和碰撞；
- WorldRoot 与 Player 可见；
- Player Camera 是 Viewport 当前相机；
- 输入上下文为 gameplay；
- RuntimeDiagnostics 已挂载；
- Viewport 图像不是空白或单色；
- PNG 和 JSON 可以写入指定路径。

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
```

源码桌面验收负责真实按钮和鼠标路由；导出包 Smoke 负责最终打包产物。两者不能互相替代。

## 扩展规则

新增指标时：

1. 数据采集进入 `RuntimeTelemetryService`；
2. 阈值判断进入 `RuntimeHealthPolicy`；
3. 文本展示进入 `DiagnosticsOverlay`；
4. 必须补 `runtime_diagnostics_regression.gd`；
5. 不允许让业务模块依赖 DiagnosticsOverlay。

新增发行验收时：

1. 优先扩展 `ReleaseSmokeRunner` 的公开合同；
2. 输出结构化 JSON 证据；
3. 保持普通启动路径无副作用；
4. 必须设置超时，禁止 CI 永久挂起；
5. 不以 headless 结果替代真实窗口或导出产物。
