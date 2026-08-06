# Architecture Audit · Iteration 58 · 2026-08-06

## 审计范围

- `SaveService` / `AtomicJsonStore` / world catalog sidecar；
- 自动保存定点调度、失败退避和手动保存交错；
- 检查点历史与跨世界本次进入过滤；
- 结构完整性、物理掉落和 Chunk 热返回相邻合同；
- 超宽屏、高 DPI 逻辑缩放和控制器焦点。

## 发现 1：world 与 catalog 之间缺少显式崩溃标记

### 风险

`world.json` 原子替换成功后，进程可能在 `catalog.json` 写入前退出。目录扫描原本以 world 文件字节数校验 sidecar；若新旧 world 恰好同字节长度，旧 catalog 可能被误接受，造成列表元数据落后于权威存档。

### 修正

增加 `catalog.pending`：

- world 写入前建立；
- world 写入失败时撤销；
- catalog 成功后清除；
- 重启扫描发现时拒绝旧 sidecar；
- 复用权威读取 32、sidecar 重建 16 和主文件修复 8 的既有预算；
- 标记检测、建立失败和清理失败进入有界诊断。

该修正不改变 `world.json` schema，不复制 payload，也不把 catalog 升级为权威状态。

## 发现 2：单项长稳存在，但缺少跨领域固定提交资格

### 现状

仓库已有 8 小时自动保存、256 世界浏览器、12 条检查点、128 掉落和结构批处理测试，但它们由不同迭代形成，无法直接证明同一固定提交在下一阶段全部边界上共同收敛。

### 修正

新增永久 `long-term-scale-recovery` 门禁：

- 24 小时调度与检查点确定性夹具；
- 同字节 stale catalog 跨服务重启恢复；
- 24 轮结构与 5×128 掉落生命周期；
- 既有多世界恢复、连接形状、Chunk cache 和相邻长稳复审；
- 3440×1440、2×逻辑缩放和真实 Joypad 焦点证据。

## 发现 3：长期证据不能扩大状态所有权

### 决定

- 不增加新的保存 participant；
- 不持久化 autosave schedule、checkpoint timeline 或 pending marker；
- 不在每个掉落或结构上增加 Timer；
- 不为资格报告扫描全世界节点；
- 不新增管道、电网、跨 Chunk 物流或 Boss 内容；
- 不把 CI 的高 DPI 模拟描述为真实设备 E4-H。

## 复审结论

Iteration 58 通过一个最小生产修复和组合资格门禁推进下一阶段。它提高跨文件崩溃一致性，并把既有预算放入长周期、跨会话、跨领域的同一证据链。商业发布仍然只能在外部真实硬件和独立体验证据完成后解除 HOLD。
