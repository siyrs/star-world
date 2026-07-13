# 星的世界 · Product & Architecture Roadmap

## 产品定位

《星的世界》不是简单的体素 Demo，而是长期可扩展的单人沙盒游戏基础。

核心原则：

- 玩家体验优先；
- 系统模块化；
- 数据驱动扩展；
- 每个玩法拥有独立领域边界；
- 所有重要功能必须可测试、可保存、可恢复。

## 当前架构方向

```
Game Runtime
├── World Domain
│   ├── Chunk Streaming
│   ├── Terrain Generation
│   └── Block State
│
├── Player Domain
│   ├── Movement
│   ├── Survival
│   ├── Inventory
│   └── Equipment
│
├── Interaction Domain
│   ├── Block Interaction
│   ├── Container
│   └── Machine
│
├── Crafting Domain
│   ├── Recipes
│   └── Stations
│
├── Persistence Domain
│   ├── Save Transaction
│   ├── Migration
│   └── Recovery
│
└── Experience Layer
    ├── UI
    ├── Feedback
    ├── Audio
    └── Guidance
```

## 下一阶段重点

### 1. 工具与资源系统

目标：建立 Minecraft 风格采集闭环。

包括：

- 工具等级；
- 方块硬度；
- 采集速度计算；
- 工具耐久；
- 掉落规则；
- 数据驱动工具定义。

架构要求：

`ToolService` 不直接依赖 Player UI，只提供领域能力。

### 2. 装备系统

新增：

- 武器；
- 防具；
- 属性修正；
- 装备栏；
- 耐久管理。

### 3. 农业与生态

方向：

- 种植；
- 生长阶段；
- 动物繁殖；
- 食物生产链。

### 4. 自动化机器基础

在 FurnaceService 基础上扩展：

- Machine Base Contract；
- 输入/输出接口；
- 能源接口；
- 自动化管线预留。

## 工程质量标准

所有新增系统必须满足：

1. 独立领域服务；
2. 数据注册表驱动；
3. 存档兼容；
4. 单元测试；
5. 桌面真实交互测试；
6. Windows Release 验收。

## 设计规范

UI:

- 使用统一 Design Token；
- 明确视觉层级；
- 支持最低 1024×576；
- 错误状态必须可理解。

代码:

- 避免 God Object；
- 服务职责单一；
- 通过事件通信降低耦合；
- 优先组合而非继承。

## 长期目标

逐步形成：

- 世界系统；
- 生存系统；
- 建造系统；
- 自动化系统；
- 探索系统；

共同组成完整的《星的世界》沙盒生态。