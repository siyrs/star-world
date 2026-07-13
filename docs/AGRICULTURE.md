# 农业、耕地与作物系统

## 产品目标

农业系统为《星的世界》提供第一个可持续、可保存的食物生产闭环：

```text
筛选种子
→ 制作锄
→ 开垦耕地
→ 播种
→ 等待分阶段生长
→ 收获并自动补种
→ 使用小麦制作面包
```

它不是放在 Player 中的一组特殊判断，也不是 UI 计时器。作物状态由独立领域服务持有，并与世界状态一起原子保存。

## 运行时结构

```text
CharacterProgressionServiceHub
├─ ToolService
├─ BlockInteractionService
│  └─ interaction extensions[]
└─ AgricultureService
   └─ CropRegistry

VoxelWorld
└─ VoxelChunk
   └─ crop cross-plane rendering
```

### `CropRegistry`

读取 `data/crops.json`，只描述静态作物能力：

- 作物 ID 与显示名称；
- 种子物品；
- 产物物品；
- 阶段方块；
- 每阶段持续时间；
- 收获数量。

### `AgricultureService`

农业状态的唯一所有者，负责：

- 位置型作物记录；
- 开垦、播种、生长、收获和自动补种；
- 背包容量预演；
- 写入失败回滚；
- 最多六小时的有界离线生长；
- 世界挂载和解除；
- 耕地或作物被拆除后的状态清理；
- 序列化与恢复。

### `BlockInteractionService` 扩展端口

基础交互服务提供：

```gdscript
register_extension(extension)
unregister_extension(extension)
```

扩展可选择实现：

```text
try_interact(world, inventory, block_position, block_id)
get_interaction_hint(block_id, selected_item_id)
on_block_removed(world, block_position, block_id)
can_break_block(world, block_position, block_id)
```

农业通过该端口参与右键交互和拆除清理。Player 仍只负责 RayCast 与输入意图。

为了兼容既有模块和测试探针，交互提示保留单参数合同：

```gdscript
get_interaction_hint(block_id)
```

需要手持物上下文的新模块使用：

```gdscript
get_interaction_hint_for_item(block_id, selected_item_id)
```

## 当前小麦数据

```json
{
  "id": "wheat",
  "seed_item": "wheat_seeds",
  "produce_item": "wheat",
  "stage_blocks": [
    "wheat_stage_0",
    "wheat_stage_1",
    "wheat_stage_2",
    "wheat_stage_3"
  ],
  "stage_seconds": [25, 35, 45],
  "harvest": {
    "produce_count": 1,
    "seed_count": 2
  }
}
```

右键收获成熟小麦后，成熟方块会回到第一阶段，形成自动补种；玩家获得一份小麦和两份种子。

## 工具合同

新增四档铲和锄：

```text
木制 power 1
石制 power 2
铁制 power 3
钻石 power 4
```

铲负责提高草、泥土、沙子、雪和耕地的采集效率。

锄负责把草方块或泥土转换为耕地。成功开垦消耗一点当前锄的耐久；上方空间被占用时不消耗耐久，也不修改世界。

## 世界表示与渲染

耕地是普通实体体素，作物阶段是非实体、透明方块。

作物不会使用满方块占位，而由 `VoxelChunk` 生成两张交叉叶片：

- 不生成碰撞；
- 使用共享体素材质；
- 每株只增加少量三角形；
- 阶段高度从幼苗逐步增长；
- 颜色从绿色过渡为成熟金色。

方块 ID 只追加在注册表尾部，保持旧存档中已有数值 ID 的顺序稳定。

## 存档合同

世界存档增加：

```text
agriculture {
  version,
  saved_at_unix,
  crops {
    "crop@x,y,z": {
      crop_id,
      position,
      stage,
      elapsed_seconds
    }
  }
}
```

旧存档缺少 `agriculture` 时自动迁移为空状态。

加载顺序：

```text
反序列化农业状态
→ 创建并启动世界
→ 挂载 AgricultureService
→ 校验耕地支撑
→ 同步阶段方块
→ 推进有界离线时间
```

## 数据安全

### 播种

```text
校验耕地与上方空间
→ 从当前槽位取出一粒种子
→ 写入第一阶段方块
→ 写入失败则退回原 metadata 的种子
```

### 收获

```text
模拟所有产物进入背包
→ 空间不足则保持成熟状态
→ 把作物切回第一阶段
→ 写入所有产物
→ 中途发生容量竞争则移除已写产物并恢复成熟方块
```

### 拆除

- 直接拆除作物会删除对应农业记录；
- 拆除耕地会清理上方作物记录和失去支撑的作物方块；
- 重新加载时，无有效耕地支撑的记录会被丢弃。

## 扩展新作物

新增作物时：

1. 在 `BlockRegistry` 末尾添加阶段方块；
2. 在 `data/crops.json` 添加定义；
3. 在 `items.json` 添加种子和产物；
4. 添加获取种子与使用产物的配方；
5. 扩展数据校验；
6. 添加领域回归和真实桌面验收。

不要把新作物 ID 判断写入 Player、GameUI 或 VoxelWorld。

## 当前范围

当前农业是第一阶段基础：

- 一种作物：小麦；
- 简化时间生长；
- 不计算水源、光照或天气；
- 收获后自动补种；
- 没有耕地湿润度、动物踩踏或肥料。

后续可以在现有状态合同上增加水源、光照、肥料和更多作物，但应保持注册表、领域状态、世界表示和体验层分离。

## 验收门禁

每次农业变更必须通过：

1. 数据注册表校验；
2. `agriculture_regression.gd`；
3. 既有输入、采集、装备、机器和生命周期回归；
4. `agriculture_desktop_acceptance.gd` 的真实右键流程；
5. 最终 Windows Release 导出和日志扫描。
