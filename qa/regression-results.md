# 回归测试结果

| 回归 ID | 问题/功能点 | 构建/commit | 测试方法 | 预期 | Developer 自测 | QA 独立结果 | 截图/日志/数据 | 状态 |
|---|---|---|---|---|---|---|---|---|
| RTC-QA-002 | BUG-QA-002 | working tree / 未提交 | production-scene desktop acceptance，调用方精确 `-OutputPath` | 内层 32/10 + 外层 exit 0，primary/named/JSON/log 齐全 | pass；`build/developer-selftest-qa002` | PASS；exit 0，32/10，10 命名截图与 JSON 齐全，无 fatal | `build/qa-independent-qa002-20260731-1057` | qa-passed |
| RTC-UI-002 | BUG-UI-002 | working tree / 未提交 | headless design system + desktop visual 1280×720；QA 补 1024×576 与真实交互状态分析 | WCAG ≥4.5、无重叠/截断、返回按钮可读 | 首轮 pass；64 checks + 32 checks/10 captures | FAIL；布局/返回通过，但 Button/Primary/Card/Selected/Ghost 多个 normal/hover/pressed/focus 低于 4.5 | `build/qa-independent-qa002-20260731-1057` | bugfixing |
| RTC-SPAWN-001 | BUG-SPAWN-001 | working tree / 未提交 | 5 profiles×6 seeds、相邻地形/合成夹具/解析器/旧档/input contract/leak 3轮 | 全绿且运行有界；用户 12 世界/设置不变 | fail/incomplete；5×3=108 通过但关键 Seed 缺失，5×6 某组合 >210s，input contract 1 fail | not-entered | `build/developer-selftest-spawn001` | bugfixing |

## 全量发布回归

- [ ] 当前源码重新构建
- [ ] 启动、新建、暂停、退出、重进
- [ ] 全部正式地图进入与通关
- [ ] 主线、关键支线和重要交互
- [ ] 碰撞、边界、掉图恢复
- [ ] 所有水域与水下流程
- [ ] 存档、读档、死亡、复活、地图切换
- [ ] UI、音频、设置、窗口焦点与分辨率
- [ ] 性能前后对比与长稳
- [ ] 日志无影响游玩的高频错误
