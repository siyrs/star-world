# 方块与物品目录完整性合同

## 背景

审计发现两类跨目录断裂：

1. `glass_pane` 已存在于 `items.json` 和 `recipes.json`，但生产 `BlockRegistry` 没有对应方块；玩家可以制作，却无法放置。
2. 煤、铁、金、钻石矿石方块的采集掉落与放置物品共用 `item_id`；天然矿石需要掉落煤炭或粗矿，但这会让矿石方块物品无法解析为世界方块。

这类问题不能只靠分别校验 JSON，因为每个文件单独合法并不代表跨目录能闭环。

## 权威关系

```text
BlockRegistry.BLOCK_IDS
↔ BlockRegistry.DEFINITIONS
↔ ItemRegistry block item
↔ Crafting output
↔ Placement item
↔ Harvest drop
↔ Block visuals
```

Definition 现在明确区分：

```text
item_id       → 默认采集掉落
place_item_id → 背包物品解析为该世界方块
```

没有 `place_item_id` 时，默认回退到 `item_id`，保持旧方块兼容。

对于 `category=block` 的普通方块物品，必须满足：

1. `item.block_id` 在 `BlockRegistry.BLOCK_IDS` 中；
2. 对应 Definition 的 `place_item_id`（或兼容回退的 `item_id`）等于该物品 ID；
3. `BlockRegistry.get_block_for_item(item_id)` 返回该 canonical block；
4. Definition 的采集 `item_id` 必须引用已注册物品，但允许与放置物品不同；
5. 所有内部方向变体继续掉落 canonical item；
6. 视觉档案或 `visual_parent` 存在；
7. 可采集变体的掉落规则返回正确 item。

流体桶等 utility 能力不受普通 block item 的 round-trip 约束。

## 矿石放置与掉落

四种矿石保持既有采集收益，同时恢复方块物品放置：

| 方块 | `place_item_id` | 默认/规则掉落 |
|---|---|---|
| `coal_ore` | `coal_ore` | `coal` |
| `iron_ore` | `iron_ore` | `raw_iron` |
| `gold_ore` | `gold_ore` | `raw_gold` |
| `diamond_ore` | `diamond_ore` | `diamond` |

这样不会为了让矿石方块可放置而破坏原有采集成长规则。

## 玻璃板修复

新增两个内部世界变体，并只追加 numeric ID：

| 世界 ID | 轴向 | 背包物品 |
|---|---|---|
| `glass_pane` | 沿 X 延伸，Z 厚 1/8 格 | `glass_pane` |
| `glass_pane_ns` | 沿 Z 延伸，X 厚 1/8 格 | `glass_pane` |

玩家仍只有一个“玻璃板”物品。放置方向由玩家水平面向解析，预览、真实世界网格、碰撞、保存和掉落使用同一变体。

视觉通过 `visual_parent=glass` 复用原创玻璃像素纹理，不新增重复 tile。

## 自动门禁

`tests/developer_b/validate_catalog_integrity.ps1` 直接解析生产 `BlockRegistry`，验证：

- `BLOCK_IDS` 无重复；
- 每个注册 ID 有 Definition；
- Definition 不会游离在 `BLOCK_IDS` 外；
- `visual_parent` 和 `orientation_family` 指向已注册方块；
- `item_id` 与 `place_item_id` 均引用已注册物品；
- 每个普通 block item 都能通过 placement item 双向 round-trip；
- canonical block 与 item 声明一致；
- Harvest Rule 只引用已注册方块。

该门禁解决的是跨目录完整性，而不是替代各注册表自己的字段校验。

## 扩展规则

新增可制作方块时必须同时完成：

```text
Block ID（只追加）
→ Definition
→ placement item / harvest drop 分工
→ Item block_id round-trip
→ Visual profile 或 visual_parent
→ Shape / orientation（如需要）
→ Harvest rule
→ Placement preview
→ 生产 Chunk mesh/collision
→ 存档与真实桌面验收
```

禁止再次合入“能制作但不能放置”“能放置但无法回收”或“内部方向变体掉落多个背包物品”的半成品。
