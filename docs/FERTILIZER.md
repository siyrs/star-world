# 堆肥与肥料系统

## 产品目标

肥料系统把低价值有机资源转化为可理解的农业成长资源：

```text
树叶 + 腐肉 + 小麦种子
→ 工作台制作堆肥
→ 对未成熟作物施用
→ 推进一个生长阶段
→ 收获并继续生产
```

目标不是让玩家无成本跳过农业，而是提供一个清晰的资源回收选择：探索和战斗产生的边角资源可以换取更快的食物生产。

## 玩家合同

当前首个肥料为 `compost`：

- 在工作台制作；
- 每次成功施用消耗一份；
- 推进当前作物一个生长阶段；
- 小麦、胡萝卜和马铃薯均可使用；
- 成熟作物拒绝施用，并提示先收获；
- 无效目标不会消耗物品；
- 施肥不改变鼠标捕获、暂停或输入上下文。

肥料通过准星上下文提示暴露：

```text
小麦幼苗
[鼠标右键] 施用堆肥（推进 1 阶段）
```

## 运行时结构

```text
CharacterProgressionServiceHub
└─ FertilizableAgricultureService
   ├─ AgricultureService
   │  ├─ CropRegistry
   │  └─ SoilMoistureService
   ├─ FertilizerRegistry
   └─ FertilizerPolicy

BlockInteractionService
└─ AgricultureInteractionAdapter
```

### `FertilizerRegistry`

读取 `data/fertilizers.json`，只描述静态能力：

- 肥料 ID；
- 对应背包物品；
- 玩家显示名称；
- 单次推进阶段数；
- 可选的适用作物白名单。

注册表不访问世界、背包、UI 或存档。

### `FertilizerPolicy`

纯策略输入：

```text
fertilizer profile
crop definition
current stage
```

输出：

```text
handled / success
reason
current_stage
 target_stage
actual_advances
```

它负责判断：

- 是否为有效肥料；
- 是否适用于目标作物；
- 作物是否已经成熟；
- 本次应推进到哪个阶段。

### `FertilizableAgricultureService`

这是基础 `AgricultureService` 的具体运行时实现。农业状态仍然只有一个所有者；肥料模块没有单独复制作物状态。

事务顺序：

```text
解析当前手持物
→ 查询肥料能力
→ 校验作物和成熟度
→ 校验农业状态记录
→ 从当前槽位取出一份肥料
→ 写入目标阶段方块
→ 更新作物阶段与累计时间
→ 发布 crop_fertilized
```

若世界写入失败：

```text
恢复原肥料及 metadata
→ 保持原世界方块
→ 保持原作物阶段
→ 返回明确失败原因
```

## 数据合同

`data/fertilizers.json`：

```json
{
  "schema_version": 1,
  "fertilizers": [
    {
      "id": "compost",
      "item_id": "compost",
      "name": "堆肥",
      "stage_advances": 1,
      "allowed_crops": []
    }
  ]
}
```

空 `allowed_crops` 表示适用于所有已注册作物。未来特定肥料可提供作物白名单。

## 存档兼容

肥料本身不拥有持久运行状态：

- 堆肥作为普通背包物品由 Inventory 保存；
- 成功施肥后的阶段由 Agriculture 保存；
- 旧世界不需要新增顶层字段或破坏性迁移；
- 失败事务不会留下“已扣物品但阶段未更新”的半状态。

## 视觉与声音

当前肥料使用既有物品色卡和统一成功反馈：

- 堆肥采用低饱和棕色，与土壤和有机材料语义一致；
- 成功后作物立即切换到下一可见阶段；
- 组合根播放既有合成反馈音，不引入额外版权资源；
- 作物仍为无碰撞、共享材质、低面数交叉叶片。

## 扩展新肥料

新增肥料时：

1. 在 `items.json` 添加物品；
2. 在 `fertilizers.json` 添加能力；
3. 添加获取或制作配方；
4. 扩展数据校验；
5. 为特殊兼容性添加策略测试；
6. 通过真实桌面右键与 Windows Release 验收。

不要在 Player、GameUI、`BlockInteractionService` 或具体作物 ID 分支中实现肥料规则。

## 当前边界

第一阶段只提供堆肥和确定性的阶段推进。尚未加入：

- 随机施肥成功率；
- 土壤长期肥力；
- 过量施肥惩罚；
- 堆肥箱机器；
- 骨粉、复合肥和作物专用肥；
- 粒子特效或角色手部动画。

后续扩展应继续保持：静态注册表、纯策略、唯一农业状态、事务提交和体验反馈分离。

## 验收门禁

每次肥料变更必须通过：

1. `validate_fertilizers.ps1`；
2. `fertilizer_regression.gd`；
3. 既有农业、灌溉、背包、输入和生命周期回归；
4. `fertilizer_desktop_acceptance.gd` 的真实相机与右键流程；
5. 最终 Windows Release 导出、运行和日志扫描。
