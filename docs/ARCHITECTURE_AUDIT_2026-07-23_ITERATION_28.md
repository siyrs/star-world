# Architecture Audit · 2026-07-23 · Iteration 28

## 范围

本轮从最新 `master@d898ca83adeb46ea6ddaf513019e71323e061675` 审计：

- `.github/workflows` 中最近增加的规模、耐久和真实桌面专项；
- `Invoke-Godot.ps1`、`run_godot_headless_test.ps1` 与 `run_godot_desktop_test.ps1`；
- GitHub Actions Checkout、`setup-godot`、严格导入和 Artifact 上传；
- 总 `Godot quality gates` 的 Runtime、桌面矩阵和 Windows Release；
- 各领域静态合同对工作流内容的永久检查。

最近几轮已经形成六个结构高度一致的专项：

```text
Shared Pickup Runtime
Mixed Runtime Endurance
Recent Chunk Cache
Machine Scale
Agriculture Scale
World Mutation Scale
```

每个专项都有真实领域脚本、真实桌面脚本、JSON 报告和 1024×576 截图。功能覆盖是必要的，但 YAML 实现出现了明显重复。

## 结论

六个调用文件合计包含十二个 Windows Job。每个 Job 重复维护：

```text
Checkout
→ setup-godot 4.7.0
→ PowerShell shell
→ Godot 等待包装器
→ timeout
→ upload-artifact
```

这不是运行时业务逻辑，而是同一种 CI 基础设施的十二份复制。后续更换 Godot 版本、修复 Windows 等待语义、调整 Artifact 保留或增加安全限制时，任何遗漏都会产生门禁漂移。

本轮提取一个 `workflow_call` 可复用工作流，并将六个近期专项迁移为声明式调用。总 Windows Release 门禁继续保持显式、唯一和权威。

## 发现 1：同一 Godot 安装合同复制十二次

原六个专项拥有：

```text
6 个领域 Job
+
6 个桌面 Job
=
12 次 actions/checkout
12 次 setup-godot
```

配置完全相同：

```yaml
version: 4.7.0
use-dotnet: false
include-templates: false
```

### 风险

- 某个工作流可能仍停留在旧 Godot；
- 某个工作流可能遗漏 `use-dotnet: false`；
- Runner 迁移需要逐文件修改；
- 静态合同只能检查结果，不能消除复制源头。

### 修复

统一到：

```text
.github/workflows/reusable-godot-quality-gate.yml
```

调用方只提供 Godot 版本覆盖时才改变默认值；首批全部使用模板默认 `4.7.0`。

## 发现 2：可靠等待规则仍可能在新专项中重新复制错误

项目曾经真实发现 Windows GUI 子系统 Godot 被 PowerShell 提前返回，造成测试假绿。现在已有：

```text
Invoke-Godot.ps1
run_godot_headless_test.ps1
run_godot_desktop_test.ps1
```

但每个新工作流仍需要开发者记住选择正确包装器。

### 修复

模板固定规则：

| 场景 | 唯一入口 |
|---|---|
| 严格导入与普通领域脚本 | `Invoke-Godot.ps1` |
| 需要 stdout/stderr 的主领域脚本 | `run_godot_headless_test.ps1` |
| 真实窗口、输入与截图 | `run_godot_desktop_test.ps1` |

调用方不再能够直接写 `godot --headless`。

## 发现 3：Artifact 失败语义分散

各专项都需要在桌面失败后继续上传：

```text
PNG
JSON
stdout
stderr
```

此前每个工作流独立维护：

```yaml
if: always()
uses: actions/upload-artifact@v4
retention-days: 14
```

新增专项容易遗漏 `always()`、上传 stderr 或使用错误的 `if-no-files-found`。

### 修复

模板统一上传行为，同时让调用方声明：

- Artifact 名称；
- 文件路径；
- 缺失文件是 `warn` 还是 `error`；
- 保留天数。

证据内容仍由领域测试产生，模板不伪造报告。

## 发现 4：领域清单必须保持在调用方

把所有脚本硬编码到模板会形成新的万能工作流，并让领域所有权消失。

### 决策

调用方继续明确声明：

```text
static_validators
domain_scripts
primary_headless_script
desktop_script
artifact_paths
```

因此代码审查仍能从一个小型调用文件看到该领域究竟验证什么，只是不再看到重复实现细节。

## 发现 5：完整 Windows Release 不能被过度抽象

总门禁包含：

- 数十个领域脚本；
- 完整桌面输入和 UI 矩阵；
- Godot 导出模板；
- Windows 可执行文件导出；
- 真实启动；
- 发行证据。

把它强行迁入首批模板会隐藏发行语义，也会让模板承担过多可选分支。

### 决策

`.github/workflows/godot-tests.yml` 保持显式实现，继续作为唯一权威 Windows Release 门禁。

Reusable workflow 只覆盖重复的专项领域/桌面结构。

## 发现 6：复杂基础设施专项不应为了统一而统一

以下工作流拥有额外服务器或发布权限：

```text
GitHub Release auto-update
→ 本地 HTTP Range Server
→ Windows 安装助手

Publish Windows Release
→ Tag 校验
→ Release 创建/覆盖
```

它们不符合普通领域 + 桌面模板，暂不迁移。

## 生产 CI 结构

```text
六个专项调用文件
└─ reusable-godot-quality-gate.yml
   ├─ domain
   │  ├─ Checkout
   │  ├─ Setup Godot
   │  ├─ strict import
   │  ├─ static validators
   │  ├─ captured headless（可选）
   │  ├─ awaited domain scripts
   │  └─ domain evidence（可选）
   └─ desktop（可选）
      ├─ Checkout
      ├─ Setup Godot
      ├─ real desktop runner
      └─ visual / JSON / logs

Godot quality gates
└─ explicit full Runtime + desktop matrix + Windows Release
```

## 已迁移调用方

```text
pickup-shared-runtime-tests.yml
mixed-runtime-endurance-tests.yml
recent-chunk-cache-tests.yml
machine-scale-tests.yml
agriculture-scale-tests.yml
world-scale-tests.yml
```

每个调用方保留：

- 原 workflow name；
- 原 concurrency group；
- 原 cancel-in-progress；
- 原领域 Job 显示名称；
- 原桌面 Job 显示名称；
- 原超时；
- 原脚本顺序；
- 原截图、JSON 和日志路径。

## 权限与供应链边界

Reusable workflow 固定：

```yaml
permissions:
  contents: read
```

不允许：

- `secrets: inherit`；
- `contents: write`；
- 创建 Release；
- 创建 Tag；
- 修改 PR；
- 上传未声明路径。

仍然使用既有固定 major 版本：

```text
actions/checkout@v4
chickensoft-games/setup-godot@v2
actions/upload-artifact@v4
```

后续供应链版本调整只需修改模板并由六个真实专项共同验收。

## 静态验收

新增：

```text
tests/developer_b/validate_reusable_ci_workflows.ps1
```

验证：

- `workflow_call` 输入完整；
- 模板无独立 `push` / `pull_request`；
- 只读权限且不继承 Secrets；
- Checkout、Setup 和 Upload 的实现数量恰好各为两个；
- 六个调用文件不包含 `runs-on`、Checkout、Setup 或 Upload；
- 每个调用仍声明原静态、领域、桌面和 JSON 证据；
- 完整 Windows Release 仍显式存在；
- 全量静态入口永久包含该验证器。

## 真实验收

迁移不是文本级替换即结束。固定候选必须真实完成：

- 六个 reusable domain Job；
- 六个 reusable desktop Job；
- 128 掉落暂停可视化；
- 混合机器/作物/敌对/掉落/Chunk 截图；
- Chunk 热返回；
- 512 机器；
- 2,048 作物；
- 3,000+ 世界修改；
- 全部相邻专项；
- 总 Runtime 与长期 soak；
- 完整桌面矩阵；
- Windows Release 实际导出和启动。

## 未改变的业务合同

本轮不修改：

- 游戏运行时代码；
- 世界、机器、农业或掉落存档；
- 方块和物品 ID；
- 测试断言；
- 性能阈值；
- 桌面截图分辨率；
- Release 更新协议。

这是 CI 基础设施单一事实来源优化，不以减少测试覆盖换取更短 YAML。

## 后续

完成后优先考虑：

```text
工作流所有权清单
→ 安全的 changed-domain 计划报告
→ 证明分支保护不会因 path filter 挂起
→ 再决定是否减少无关专项执行
```

在获得 required-check 和变更影响图的真实证据之前，不直接给专项添加激进 `paths` 过滤。运行时间优化必须建立在不丢失门禁的基础上。
