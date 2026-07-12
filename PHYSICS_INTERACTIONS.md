# 物理交互模块

## 目标

物理层、碰撞掩码和“谁可以触发谁”不再依赖 Godot 节点默认值。所有运行时配置由 `PhysicsLayers` 与 `PhysicsInteractionPolicy` 统一定义，场景文件只保留与编辑器一致的初始值。

## 分层

| 层 | 常量 | 用途 |
|---|---|---|
| 1 | `WORLD` | 体素区块与静态世界 |
| 2 | `PLAYER` | 玩家角色体 |
| 3 | `ENTITIES` | 动物、僵尸等生物 |
| 4 | `PICKUPS` | 掉落物触发区 |

公开掩码：

- `PLAYER_BODY_MASK = WORLD | ENTITIES`
- `PLAYER_INTERACTION_MASK = WORLD | ENTITIES`
- `ENTITY_BODY_MASK = WORLD | PLAYER | ENTITIES`
- `PICKUP_BODY_MASK = PLAYER`

## 责任

- `PlayerPhysicsProfile` 在玩家场景进入树时应用玩家层、身体掩码、交互射线掩码和 `player` group。
- `CreatureFactory` 为所有生物统一应用实体层与碰撞掩码，并在死亡 signal 发出时立即释放碰撞。
- `ItemPickup` 只监听玩家层，并再次通过 `PhysicsInteractionPolicy.is_player_body` 验证触发者。地形、生物和其他物理体不能代替玩家拾取。
- `inventory_service` 仍通过构造注入，仅在通过玩家身份校验后用于写入物品；掉落物不再对任意碰撞体执行全局背包写入。

## 回归测试

```powershell
godot --headless --path . --script res://tests/qa/physics_interaction_regression.gd
```

测试覆盖玩家/实体/掉落物层配置、攻击射线、死亡碰撞释放、地形不得拾取，以及玩家成功拾取。
