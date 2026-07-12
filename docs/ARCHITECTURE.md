# 架构索引

完整架构说明位于根目录 [ARCHITECTURE.md](../ARCHITECTURE.md)。

核心依赖方向为：

```text
Core / GameplayServiceHub
├─ World -> Generator + Chunk -> BlockRegistry
├─ Player -> World + Inventory + Survival
├─ UI -> Inventory + Crafting + Save + Survival + DayNight
├─ Entity -> Player + Inventory + DayNight
└─ AudioBridge -> World + Player + Entity + Crafting
```

地形由 Seed 重建，存档仅记录稀疏方块覆盖；模块间使用小型公开方法和 signal，避免 UI、存档或生物直接依赖 Chunk 网格实现。
