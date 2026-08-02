# 性能基线与优化对比

## 固定环境

- 分支/commit：`codex/commercial-release-gameplay-polish` / `c1054d8834bbabdf6e6035f909e66cb7c5084717`
- 构建产物：`build/release-readiness-fresh-pwsh7/StarWorld.exe`，SHA-256 `C42EB5D17F683EB8BCD52C19A9F36EBF811B1788623878D5276A7D9FFC09F95C`，2026-07-31 10:14:13 +08:00；PCK `38B6E33400D1E0A3C0E2D8BB72EE6AD664603AADD9A19B58286ADDEF9F90C305`，10:14:16（2026-07-31 10:52 +08:00 重新用 `Get-FileHash` 完整核验）。
- 操作系统/CPU/GPU/内存：待采集
- Godot/渲染器/窗口模式/分辨率/VSync：待采集
- 采样工具、采样周期与场景脚本：待确定

## 指标

| 场景 | 阶段 | 平均 FPS | 最低 FPS | 1% Low | 平均/峰值帧时 | CPU | GPU | 内存/峰值 | 显存 | GC 次数/峰值停顿 | 加载时间 | 运行时长 | 原始证据 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fresh release smoke 初始世界 | baseline | 50（终态采样） | 待采集 | 待采集 | avg 20.016 ms / peak 29.109 ms | 待采集 | 待采集 | 内部 `0.0 MiB`，无效，待外部采样 | 待采集 | 未暴露 | export 7.75 s；runner 7.74 s | 180 帧/约 6.5 s | `build/release-readiness-fresh-pwsh7/release-smoke.json` |

## 长稳趋势

| 时间点 | 地图/场景 | Working Set | Private Bytes | CPU | FPS/帧时 | 错误计数 | 备注 |
|---|---|---|---|---|---|---|---|

## 初始观察

- release smoke 自身 16 checks 与 visual/soak `ok=true`，无 stutter；终态 draw calls 186、nodes 2116。
- 运行健康仍为 warning：初始世界 chunk 队列 pending=62，超过 warning=48；需更长时间序列确认是否收敛，不能只改阈值。
- 内部 `memory_mib=0.0` 不可信；必须补 Windows 进程内存采样后才可形成发布性能结论。
- stderr 有字体导出缺失 warning，见 `BUG-UI-001`。
