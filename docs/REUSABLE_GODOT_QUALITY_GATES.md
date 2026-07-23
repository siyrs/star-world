# Reusable Godot Quality Gates

## 目标

项目已经拥有大量专项工作流。每个专项都需要真实执行：

```text
Checkout
→ 安装 Godot 4.7
→ 严格项目导入
→ PowerShell 静态合同
→ Godot 领域回归
→ 可选真实桌面验收
→ 可视化和机器可读证据上传
```

这些步骤此前在每个 YAML 中重复维护。一次 Godot 版本、等待包装器或 Artifact 规则调整，需要修改多个文件，并且容易出现某个专项继续使用旧命令的漂移。

本合同通过 GitHub Actions `workflow_call` 建立一个可复用实现，同时保留每个领域自己的测试清单、超时和证据名称。

## 结构

```text
专项调用工作流
└─ reusable-godot-quality-gate.yml
   ├─ domain
   │  ├─ Checkout
   │  ├─ Setup Godot
   │  ├─ strict import
   │  ├─ static validators
   │  ├─ optional captured headless script
   │  ├─ awaited domain scripts
   │  └─ optional domain evidence
   └─ desktop（可选）
      ├─ Checkout
      ├─ Setup Godot
      ├─ run_godot_desktop_test.ps1
      └─ screenshot / JSON / stdout / stderr
```

## 已迁移范围

首批迁移六个具有相同两层结构、并且已经拥有真实可视化证据的专项：

| 调用工作流 | 领域重点 | 桌面证据 |
|---|---|---|
| `pickup-shared-runtime-tests.yml` | 共享掉落寿命、稳定锚点、资源复用 | 128 个真实掉落与 Pause |
| `mixed-runtime-endurance-tests.yml` | 掉落堆叠与相邻领域回归 | 机器、作物、敌对、掉落、Chunk 往返 |
| `recent-chunk-cache-tests.yml` | LRU、热恢复、卸载 Patch | 三轮连接区卸载和热返回 |
| `machine-scale-tests.yml` | 活动索引、自动化和精确完成 | 512 台真实机器 |
| `agriculture-scale-tests.yml` | 成长批次、水分缓存和精确成熟 | 2,048 株真实作物 |
| `world-scale-tests.yml` | 世界修改与 Chunk 重建合并 | 3,000+ 修改与完整重载 |

调用工作流只声明：

- 静态验证器；
- 领域脚本；
- 可选主脚本日志捕获；
- 领域和桌面超时；
- 桌面脚本与截图路径；
- Artifact 名称与文件清单。

它们不再复制 `runs-on`、Checkout、`setup-godot`、`upload-artifact` 或具体运行包装器。

## 输入合同

### 领域层

```text
domain_job_name
domain_timeout_minutes
static_validators
primary_headless_script
primary_headless_output_base
primary_headless_timeout_milliseconds
domain_scripts
domain_artifact_name
domain_artifact_paths
domain_artifact_if_no_files
```

`static_validators` 和 `domain_scripts` 都使用换行分隔。模板按声明顺序执行，任意一项失败都会立即阻断当前领域 Job。

普通领域脚本必须经过：

```text
tests/ci/Invoke-Godot.ps1
```

需要保留 stdout/stderr 的主脚本必须经过：

```text
tests/ci/run_godot_headless_test.ps1
```

因此不会重新引入 Windows GUI 子系统 Godot “PowerShell 提前返回、测试假绿”的问题。

### 桌面层

```text
desktop_job_name
desktop_timeout_minutes
desktop_script
desktop_output_path
desktop_timeout_milliseconds
desktop_artifact_name
desktop_artifact_paths
desktop_artifact_if_no_files
```

只要 `desktop_script` 非空，桌面 Job 就会在领域 Job 成功后运行，并统一通过：

```text
tests/ci/run_godot_desktop_test.ps1
```

真实桌面脚本仍然负责产品输入、场景、保存、重载和 1024×576 截图断言。模板只负责可靠启动、等待、超时和证据上传，不替代领域验收。

## 失败语义

| 失败位置 | 结果 |
|---|---|
| YAML 或 `workflow_call` 无效 | GitHub 在 Job 创建前拒绝调用 |
| 严格导入失败 | 不运行领域脚本 |
| 静态验证器失败 | 不运行后续领域或桌面 Job |
| 领域脚本超时/非零退出 | Job 失败并保留已声明日志 |
| 桌面脚本失败 | Artifact 仍以 `always()` 上传 |
| 必需证据缺失 | `if-no-files-found: error` 阻断 |
| 可选领域日志缺失 | 调用方可选择 `warn` |

## 权限与安全

模板固定为：

```yaml
permissions:
  contents: read
```

首批调用不使用 `secrets: inherit`，不会获得仓库写权限，也不会创建 Release、Tag 或提交。

## Windows Release 边界

完整 `Godot quality gates` 继续显式保留：

```text
全量 Runtime 与领域回归
→ 完整桌面输入/UI 矩阵
→ 安装导出模板
→ Windows Release 导出
→ 真实启动
→ 证据上传
```

Windows Release 是唯一权威发行门禁，不通过 reusable workflow 隐藏或拆散。专项模板只统一重复的领域和桌面准备步骤。

## 永久静态合同

`tests/developer_b/validate_reusable_ci_workflows.ps1` 验证：

- 模板只由 `workflow_call` 触发；
- 所有输入和等待包装器存在；
- Checkout、Godot Setup 和 Artifact Upload 只在模板的两个 Job 中实现；
- 六个调用工作流不重新出现 `runs-on` 或 Setup 步骤；
- 每个调用仍声明原有静态、领域、桌面和 JSON 证据；
- 调用工作流保留并发取消；
- 全量 Windows Release 门禁继续显式存在；
- 模板和调用保持只读、无共享 Secrets。

## 后续迁移条件

其他专项只有同时满足以下条件才迁移：

- 结构确实是相同的严格导入、验证器、领域脚本和可选桌面脚本；
- 没有领域专用服务、服务器或发布步骤；
- 原 Job 名称、超时和证据路径可通过输入完整表达；
- 迁移后的固定候选通过原专项和总 Windows Release 门禁。

包含本地 HTTP Range Server、Windows 更新安装助手、GitHub Release 发布或复杂多 Job 拓扑的工作流暂不强行套入模板。
