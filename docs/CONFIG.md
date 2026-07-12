# 配置说明

玩家设置保存在 `user://settings.json`，由设置页修改并立即应用。

| 字段 | 默认值 | 范围 / 含义 |
|---|---:|---|
| `mouse_sensitivity` | `0.18` | UI 值，运行时除以 100 写入玩家控制器 |
| `render_distance` | `4` | `1..5` Chunk；卸载半径自动设为视距 + 1 |
| `master_volume` | `0.8` | `0..1` 主音量 |
| `fullscreen` | `false` | 窗口 / 全屏 |
| `cycle_minutes` | `10` | 昼夜一轮的分钟数 |

地图、物品、配方和生物分别配置在 `data/map_profiles.json`、`data/items.json`、`data/recipes.json` 和 `data/creatures.json`。技术 ID 是存档合同的一部分，发布后不要随意改名。
