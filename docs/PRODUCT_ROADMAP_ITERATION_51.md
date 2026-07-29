# 星的世界 · Product Roadmap · Iteration 51

## 已完成：异常会话恢复与安全退出

本轮把“长期规模与恢复”从存档文件可靠性推进到完整应用生命周期：

- 新增严格 `session_recovery.json` 会话标记；
- 异常退出后主菜单显示“恢复上次世界”；
- 恢复始终读取最近权威 `world.json`，不保存第二份世界状态；
- 主菜单退出、暂停菜单“保存并退出游戏”和 Windows 窗口关闭共享单一协调器；
- 最终保存失败时取消退出，保留世界、Pause、Runtime Health 和恢复标记；
- 正常退出后清除 primary/tmp/bak/recover/corrupt 全部提示文件；
- 损坏主标记不会提升旧 backup，避免错误恢复提示；
- 模拟重启、失败退出、真实鼠标三阶段桌面旅程和 Windows Release 成为永久门禁。

详细合同：

- [CRASH_SAFE_SESSION_RECOVERY.md](CRASH_SAFE_SESSION_RECOVERY.md)
- [CRASH_SAFE_SESSION_RECOVERY_TESTING.md](CRASH_SAFE_SESSION_RECOVERY_TESTING.md)
- [ARCHITECTURE_AUDIT_2026-07-29_ITERATION_51.md](ARCHITECTURE_AUDIT_2026-07-29_ITERATION_51.md)

## 对总体路线图的影响

Persistence & Release Domain 现在形成完整闭环：

```text
周期自动保存
→ 权威原子保存
→ 保存来源与检查点历史
→ 当前世界进入会话隔离
→ 异常退出标记
→ 应用重启恢复入口
→ 最终保存与安全退出
```

可靠性不再只停留在文件层，玩家能够看到并操作恢复结果。

## 下一阶段重点

### 1. 世界备份管理产品化

当前 `.bak` 主要服务自动恢复。下一步可评估受控的玩家可见历史快照，但必须先定义：

- 总磁盘预算；
- 每世界数量上限；
- 快照创建频率；
- 原子恢复与冲突策略；
- 存档浏览器虚拟化与回收站交互；
- 大世界真实 I/O 压力。

不得简单复制无限多个 `world.json`。

### 2. Release 级启动恢复压力

继续验证：

- 真实导出 EXE 被终止后的下一次启动；
- 大存档下 marker 读取不拖慢主菜单；
- 多世界目录与异常 marker 同时存在；
- 更新程序重启与恢复提示的优先级；
- 超宽屏、高 DPI 和控制器操作恢复卡片。

### 3. 内容扩展

在可靠保存、恢复、退出和长期运行门禁稳定后，可以开始更大玩法闭环；新增内容仍必须复用现有世界状态所有权、生命周期、预算和真实桌面验收。
