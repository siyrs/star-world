# 地图与内容覆盖矩阵

> 五个正式地图是同一 `game.tscn` 下由 `data/map_profiles.json` 驱动的程序化世界 Profile，不是五个独立场景。源码未实现传统主线/支线/通关/结算；“通关”列按无设计通关条件标记，不能调用函数伪造。本轮（2026-08-02 Claude）每张图完成正常入口的可重复发布验收旅程：`tests/qa/profile_deep_journey_regression.gd` 141 checks 全过（真实菜单进入、固定 seed 112358、隔离 QA 世界、pre/post manifest 契约）。

| 地图 ID | 地图名称 | 正常入口 | 出生点 | 水域 | 高空 | 地下/洞穴 | 边界 | 通关条件 | 已进入 | 完整探索 | 已通关 | 存档 | 死亡复活 | 任务 | 剩余问题 | 回归状态 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| star_continent | 星辰大陆 | 主菜单→创建新世界→选择星辰大陆（真实鼠标点击✓） | 数据驱动安全扫描✓ | ✓ 河流（生成器确定性定位；入/游/出/重入 water_lava_lifecycle） | 玩家建造/地形高处 | 动态洞穴/深层矿区 | ✓ 区块接缝连续（seam_breaks=0)、Y<-12 恢复 | 无设计通关条件 | ✓ 深度旅程 | ✓ 验收旅程（河流+建造 place/mine+农业服务+夜间巡逻 continent_night_patrol+勘探扫描） | 不适用 | ✓ save_current 往返+持久化身份匹配 | ✓ 死亡→真实「重生」按钮→alive/health 恢复 | ✓ 勘探发现记录 | 无 | deep-journey-pass |
| desert_ruins | 荒漠遗迹 | 主菜单→创建新世界（真实鼠标✓） | 数据驱动安全扫描✓ | 未发现正式水体（按设计✓） | 地表结构/建造 | ✓ 地下富矿 946 矿石块 | ✓ 接缝连续、Y<-12 恢复 | 无设计通关条件 | ✓ 深度旅程 | ✓ 验收旅程（沙海 625 列+ruin_pillar 装饰 2 特征+地下矿路+ruin_prospecting_kit） | 不适用 | ✓ 持久化身份匹配 | ✓ 死亡→重生 | ✓ 勘探发现记录 | 无 | deep-journey-pass |
| frozen_wastes | 极寒冰原 | 主菜单→创建新世界（真实鼠标✓） | 数据驱动安全扫描✓ | ✓ 冰层+冰下水（生成器确定性定位） | 高峰/冰面 | 冰下水体/洞穴 | ✓ 接缝连续、Y<-12 恢复 | 无设计通关条件 | ✓ 深度旅程 | ✓ 验收旅程（冰面+冰下水+hunger_multiplier=1.35 入场验证+frost_prospecting_kit） | 不适用 | ✓ 持久化身份匹配 | ✓ 死亡→重生 | ✓ 勘探发现记录 | 无 | deep-journey-pass |
| sky_islands | 天空群岛 | 主菜单→创建新世界（真实鼠标✓） | 数据驱动安全扫描✓ | 无流体（按设计✓） | ✓ 289 高地形列（多浮岛） | 动态洞穴待判定 | ✓ 边缘坠落 Y<-12 恢复（真实玩家） | 无设计通关条件 | ✓ 深度旅程 | ✓ 验收旅程（多浮岛+边缘坠落恢复+sky_prospecting_kit） | 不适用 | ✓ 持久化身份匹配 | ✓ 死亡→重生 | ✓ 勘探发现记录 | 无 | deep-journey-pass |
| abyss_world | 深渊世界 | 主菜单→创建新世界（真实鼠标✓） | 数据驱动安全扫描✓ | ✓ 熔岩（y==4 洞穴；BUG-LAVA-001 已登记） | 洞穴高差 | ✓ 1570 矿石块 | ✓ 洞穴接缝连续、熔岩深度坠落恢复 | 无设计通关条件 | ✓ 深度旅程 | ✓ 验收旅程（熔岩+矿路+abyss_skirmish 遭遇+abyss_prospecting_kit） | 不适用 | ✓ 持久化身份匹配 | ✓ 死亡→重生 | ✓ 勘探发现记录 | BUG-LAVA-001（P2，待 PM 设计决策，不阻塞） | deep-journey-pass |

## 内容覆盖清单

| 类别 | 唯一项目 | 已测试 | 结果 | 备注 |
|---|---|---|---|---|
| 游戏模式 | 单人沙盒生存；难度 relaxed/balanced/challenging | ✓ | pass | 无角色选择、无独立模式 |
| 进度/任务 | 8 个探索里程碑与奖励；6 步教程 | ✓ | pass | 教程/经验为持久化域（deep journey content matrix）；无传统 Quest/胜利条件 |
| 角色/NPC/敌人 | 单一玩家；鸡、牛、猪、僵尸、深渊蛮兽、深渊射手 | ✓ | pass | 3 套敌对遭遇（continent_night_patrol/abyss_skirmish/abyss_assault 经 director force_decision 验证） |
| 物品/武器/工具 | 107 物品、64 基础配方、9 熔炉、3 切石机 | ✓ | pass | stone_pickaxe/stone_sword/torch 入包；crafting 暴露 2 手配方；furnace/stonecutter 服务挂载（content matrix） |
| 建筑/建造能力 | 方块、玻璃、围栏、台阶、梯子、门/双门、箱子、工作台、熔炉、切石机、维修台、床、农业/灌溉 | ✓ | pass | live world place/mine 往返（star_continent 深度旅程）；结构/机器有专项套件 |
| 交互对象 | 采矿、放置/拆除、拾取/丢弃、合成、维修、休息、饲养、战斗、探索扫描 | ✓ | pass | 勘探扫描全 5 profile 专用 kit 验证；rest/bed 服务挂载 |
| 设置选项 | 灵敏度、渲染距离、全屏、UI 缩放等 | ✓ | pass | UI scale 1.0/1.25/1.5 生产信号应用；全屏标志往返（stability_extreme_input） |
| 存档槽/流程 | 多世界、`world.json`/`catalog.json`、`.tmp`/`.bak`、回收站、Schema v2 | ✓ | pass | save_load_matrix 35 checks：手动往返/覆盖代际/多世界/v1→v2 迁移 |
| 出生质量 | 数据驱动评分；有界预算；五 Profile | ✓ | pass | 5×6 seeds 全矩阵 279 checks；star/24681357 专项 18/18 |
| 极端输入/稳定性 | 键鼠突发、暂停/恢复、UI 缩放、快速进入/存档/返回 | ✓ | pass | stability_extreme_input 36 checks，节点零泄漏 |
| 长稳 | 跨 5 图巡游+存档+菜单返回 | ✓ | pass | long_soak_journey，30min 脚本化（见 session-state 5.5 说明） |
