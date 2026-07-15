# 方块像素视觉与程序化纹理合同

## 目标

《星的世界》的方块视觉不再依赖单一纯色，而采用原创、确定性生成的低分辨率像素纹理：

```text
方块静态视觉配置
→ 16×16 像素 tile
→ 共享纹理图集
→ 区块面 UV
→ 最近邻过滤
→ 顶 / 侧 / 底方向明暗
```

视觉语言借鉴经典体素沙盒的“低分辨率、强轮廓、可远距离识别”原则，但不复制 Minecraft 或任何第三方纹理、调色板和资产。

## 玩家合同

玩家应能仅凭方块表面判断主要材质：

- 草方块：顶部草皮、侧面草根和泥土、底部泥土；
- 原木：顶部年轮、侧面树皮；
- 木板：板材拼缝、颜色变化和木结；
- 石砖与圆石：不同的砌块边界；
- 矿石：石质基底中嵌入不同颜色矿物；
- 工作台、熔炉、箱子和修理台：拥有独立的功能性表面；
- 玻璃、树叶、梯子、栅栏、火把和作物：拥有像素 cutout；
- 干燥与湿润耕地：通过明度和沟槽区别；
- 作物阶段：高度与像素形态同步变化。

关键差异不能只靠 UI 名称补偿，世界本身必须可读。

## 模块边界

```text
data/block_visuals.json
        │
        ▼
BlockVisualRegistry
        │
        ▼
BlockTextureAtlas
        │
        ▼
VoxelChunk
  ├─ atlas UV
  ├─ nearest filtering
  ├─ alpha scissor
  └─ directional shading
```

### `BlockVisualRegistry`

职责：

- 加载 `data/block_visuals.json`；
- 规范化 tile、调色板和方块分面映射；
- 验证所有 `BlockRegistry.BLOCK_IDS` 均有视觉配置；
- 验证 tile 引用、图集列数和 16×16 合同；
- 根据面索引解析 `top`、`side`、`bottom` 或 `all`。

它不生成 Image，不访问场景树，也不创建材质。

### `BlockTextureAtlas`

职责：

- 根据注册表一次性生成共享图集；
- 使用确定性哈希生成像素噪声、砖缝、木纹、矿物嵌点等；
- 返回方块各面的图集矩形和 UV；
- 缓存 `Image` 与 `ImageTexture`；
- 为测试提供显式缓存重建入口。

当前图集包含 53 个可复用 tile。多个方块可以共享 tile，例如石台阶复用石砖、木楼梯复用木板。

### `VoxelChunk`

职责保持为体素网格生成：

- 每个可见面读取唯一 tile UV；
- 顶面保持原始亮度；
- 侧面乘以 0.86；
- 底面乘以 0.68；
- 所有区块继续共享一个 `StandardMaterial3D`；
- 使用 `TEXTURE_FILTER_NEAREST` 保持像素边缘；
- 使用 Alpha Scissor 处理树叶、玻璃和作物 cutout；
- 碰撞网格仍由原始体素面生成，不受纹理透明像素影响。

纹理系统不会为每个方块创建材质、节点或独立纹理，因此不会破坏既有区块合批与流式加载预算。

## 数据合同

`data/block_visuals.json` 顶层：

```json
{
  "schema_version": 1,
  "tile_size": 16,
  "atlas_columns": 8,
  "tile_order": [],
  "tiles": {},
  "blocks": {}
}
```

### Tile 定义

```json
{
  "stone": {
    "pattern": "noise",
    "palette": ["#6B7075", "#777C82", "#868B90", "#5C6267"],
    "density": 0.36
  }
}
```

支持的模式包括：

```text
noise           石、泥土、沙、雪、基岩
cobble          圆石块边界
boards          木板拼缝和木结
bricks          砖缝
bark / rings    树皮和年轮
ore             石质基底与矿物簇
grass_side      草根与泥土分层
leaves          叶片 cutout
water / lava    流体像素波纹
crop            作物阶段
furrows         耕地沟槽
glass           透明中心与高光边框
crafting_*      工作台
furnace         熔炉
chest           箱子
door / fence / ladder / torch
weave / ice
bed_* / repair_*
```

### 方块分面映射

```json
{
  "grass": {
    "top": "grass_top",
    "side": "grass_side",
    "bottom": "dirt"
  },
  "stone": {
    "all": "stone"
  }
}
```

面索引合同：

```text
2  top
3  bottom
其他  side
```

## 性能合同

- 图集只在首次使用时生成一次；
- 单个 atlas 使用一个共享 `ImageTexture`；
- 纹理尺寸由 16×16 tile 与固定列数计算；
- 不为方块创建独立 Material；
- 不为 tile 创建场景节点；
- 不引入每帧纹理生成；
- 区块仍以一个可视 SurfaceTool 和一个碰撞 SurfaceTool 构建；
- 最近邻过滤不生成模糊采样；
- 程序化生成结果在缓存重建后必须具有相同校验值。

## 扩展步骤

新增方块视觉时：

1. 在 `tile_order` 追加 tile id；
2. 在 `tiles` 中选择已有 pattern 和原创调色板；
3. 在 `blocks` 中配置 `all` 或顶/侧/底映射；
4. 运行 `validate_block_visuals.ps1`；
5. 运行 `block_texture_regression.gd`；
6. 在真实纹理画廊中检查近景和中景可读性；
7. 重新执行完整桌面矩阵与 Windows Release smoke。

禁止：

- 直接拷贝第三方游戏纹理；
- 为每个方块创建独立材质；
- 在 `VoxelChunk` 中加入大量方块 ID 特判；
- 使用线性过滤模糊像素；
- 只更新数据而不添加测试；
- 仅检查图集文件、不检查生产区块材质和真实世界截图。

## 当前质量门禁

### 静态数据验证

`tests/developer_b/validate_block_visuals.ps1`：

- 从 `BlockRegistry.BLOCK_IDS` 解析真实方块列表；
- 验证所有方块均有映射；
- 验证 tile 顺序唯一；
- 验证 pattern 和颜色格式；
- 验证草、原木和矿石的关键差异。

### 单元与领域回归

`tests/qa/block_texture_regression.gd`：

- 注册表加载与完整性；
- 图集尺寸；
- 像素颜色变化；
- 顶/侧差异；
- 矿石差异；
- 透明 cutout；
- UV 边界；
- 确定性重建；
- 真实 `VoxelChunk` 材质、UV 和方向明暗。

### 真实桌面验收

`tests/qa/block_texture_desktop_acceptance.gd`：

- 启动生产 `GameScene`；
- 创建真实世界；
- 使用真实生产区块构建纹理画廊；
- 渲染常用自然、建筑、矿物、机器、农业和流体方块；
- 检查生产材质绑定、最近邻过滤和纹理颜色桶；
- 保存世界画廊截图与完整图集截图；
- 确认鼠标和 WASD 未被视觉层影响。

## 后续演进

后续可以在不破坏当前合同的前提下增加：

- 生物群系色调与季节色；
- 独立半透明水/玻璃 Surface；
- 发光贴图或材质通道；
- 门、台阶、楼梯和床的形状专用 UV；
- 方块朝向；
- 纹理动画；
- 玩家可选原创资源包。

这些扩展必须继续复用 `BlockVisualRegistry → BlockTextureAtlas → VoxelChunk` 的边界，而不是回到方块脚本或 UI 中硬编码材质。
