# 长期规模与恢复测试说明

## 永久门禁

工作流：`.github/workflows/long-term-scale-recovery-tests.yml`

该工作流在 PR 与 `master` push 上运行 reusable Godot quality gate，包含静态合同、严格 Godot 4.7 导入、领域回归、相邻压力回归和真实桌面证据。

## 静态合同

```powershell
./tests/developer_b/validate_long_term_scale_recovery.ps1
```

验证内容：

- `catalog.pending` 在权威 world 写入前建立；
- world 写入失败会撤销标记；
- catalog 读取看到标记时拒绝旧 sidecar；
- catalog 重建成功后清除标记；
- 诊断暴露标记建立失败、清理失败和检测次数；
- 长期夹具、桌面夹具、永久 workflow、路线图和全量入口均存在；
- 未引入第二存档领域、每节点 Timer 或无界全世界扫描。

## 领域回归

```powershell
./tests/ci/Invoke-Godot.ps1 -Arguments '--headless --path . --script res://tests/qa/catalog_transaction_marker_recovery_regression.gd'
./tests/ci/Invoke-Godot.ps1 -Arguments '--headless --path . --script res://tests/qa/long_term_scale_recovery_regression.gd'
./tests/ci/Invoke-Godot.ps1 -Arguments '--headless --path . --script res://tests/qa/long_term_structure_pickup_churn_regression.gd'
```

核心断言：

- 同字节长度的新 world 与旧 catalog 在重启后由 pending 标记正确区分；
- 第一次列表只消耗一次权威读取与一次 sidecar 重建；
- 第二次列表为纯 catalog hit；
- 24 小时、288 个窗口、9 次失败、288 次最终成功和 6 次手动保存精确收敛；
- 检查点历史稳定在 12 条并精确计算淘汰数；
- 五世界本次进入过滤不泄漏旧访问或其他世界事件；
- 24 轮结构清理与 5×128 掉落压力逐轮释放所有临时节点。

相邻回归继续运行：

- bounded multi-world recovery；
- autosave long-session endurance；
- world-scoped checkpoint sessions；
- pickup shared runtime；
- structural integrity batching；
- connected block shapes；
- recent Chunk snapshot cache。

## 桌面验收

```powershell
./tests/ci/run_godot_desktop_test.ps1 `
  -Godot <godot.exe> `
  -ProjectRoot . `
  -ScriptPath 'res://tests/qa/ultrawide_high_dpi_controller_focus_desktop_acceptance.gd' `
  -OutputPath 'build\ultrawide-high-dpi-controller-focus.png' `
  -TimeoutMilliseconds 1200000
```

输出：

- `build/ultrawide-high-dpi-controller-focus.png`
- `build/ultrawide-high-dpi-controller-focus-report.json`
- stdout/stderr 日志

验收物理窗口为 3440×1440，逻辑画布为 1720×720。真实 Joypad 输入必须完成主菜单焦点移动、设置接受和取消返回。

## 全量回归

新静态与 Headless 回归加入 `tests/run_all.ps1`。最终合并前仍要求权威 `Godot quality gates`、Windows Release 导出启动、发布闭环和所有受影响的相邻永久门禁全绿。

## 外部证据

CI 成功不等于商业发布许可。真实最低/推荐硬件、独立 E4-H 和 7,200 秒最终包目标硬件 soak 仍必须由外部证据包完成。
