# WB 历史仓库名称映射方案

## 1. 背景与目标

WB 的 FBO/FBW 单笔订单接口 `GET /api/v1/supplier/orders` 只返回
`warehouseName`，不返回 `warehouseId` 或 `officeId`。Seller Analytics
库存分析接口则返回稳定的 `warehouseId/officeID + warehouseName + regionName`。

当前系统已通过 `RawWb::WarehouseRegion` 保存 Analytics 仓库字典，但历史订单中的
仓库名称会因重命名、缩写、国家后缀、虚拟仓和仓库下线而无法直接匹配当前名称。

本方案目标：

- 将历史 FBO 订单的 `warehouse_name` 稳定解析到 `RawWb::WarehouseRegion.warehouse_id`。
- 保留历史名称、映射依据、置信度、有效期和人工审核状态。
- 不污染平台同步得到的仓库主数据。
- 对无法确认的名称显式保留为未映射，不按地名猜测。
- 支持分仓报表按 `区域 -> 仓库 -> SKU` 汇总。

本方案不处理 FBS 卖家仓。`warehouse_type = Склад продавца` 应归入独立的
“卖家仓/Маркетплейс”分组，不映射到 WB FBO 仓库区域。

## 2. 当前数据基线

当前两个有效账号共有 3,332 条 Statistics 订单：

| 类型 | 订单数 | 说明 |
| --- | ---: | --- |
| `Склад WB` | 1,846 | FBO/FBW，适用本方案 |
| `Склад продавца` | 1,486 | FBS，不适用本方案 |

FBO 发货仓按订单数计算的覆盖率：

| 匹配方式 | 命中 | 覆盖率 |
| --- | ---: | ---: |
| 当前按账号直接匹配规范化名称 | 1,216 | 65.9% |
| 合并现有账号仓库字典后直接匹配 | 1,287 | 69.7% |
| 加入当前高置信历史别名 | 1,829 | 99.1% |
| 待确认 | 17 | 0.9% |

当前高置信别名：

| 历史订单名称 | 当前 Analytics 名称 |
| --- | --- |
| `Владимир` | `Владимир WB` |
| `Воронеж` | `Воронеж WB` |
| `Сарапул` | `Сарапул WB` |
| `Самара (Новосемейкино)` | `Новосемейкино` |
| `СПБ Шушары` | `Склад СПБ Шушары Московское` |
| `СК Великий Камень` | `СК Великий Камень (Беларусь)` |

剩余 17 条订单涉及约 13 个历史名称，包括 `Вёшки`、`Виртуальный Курск`、
`Орша`、`Минск Привольный`、`Тверь`、`Пенза`、`Алексин 4`、
`СК Ереван` 等。需要平台历史数据或人工证据确认。

## 3. 数据模型

### 3.1 保留 `RawWb::WarehouseRegion` 为当前仓库主数据

该表继续保存平台返回的事实：

- `account_id`
- `warehouse_id`
- `warehouse_name`
- `normalized_warehouse_name`
- `region_name`
- `source`
- `raw_json`
- `synced_at`

不能把历史名称直接覆盖到 `warehouse_name`，也不能为历史名称生成伪
`warehouse_id`。

### 3.2 新增 `raw_wb_warehouse_name_mappings`

建议字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `account_id` | bigint，可空 | 空表示全账号通用；非空表示账号特例 |
| `historical_name` | string | Statistics 订单中的原始仓库名 |
| `normalized_historical_name` | string | 统一规范化后的查找键 |
| `warehouse_id` | bigint | WB Analytics 的真实仓库 ID，不是本地行 ID |
| `canonical_name` | string | 审核时的目标仓库名快照 |
| `region_name` | string | 审核时的目标区域快照 |
| `valid_from` | date，可空 | 名称映射生效日期 |
| `valid_to` | date，可空 | 名称映射失效日期 |
| `mapping_source` | string | `analytics`、`platform_history`、`manual` 等 |
| `confidence` | decimal | `0..1`，用于审核和自动使用门槛 |
| `status` | string | `verified`、`candidate`、`rejected`、`retired` |
| `evidence` | jsonb | 响应样本、备注、相关名称等依据 |
| `verified_by_id` | bigint，可空 | 人工确认人 |
| `verified_at` | datetime，可空 | 人工确认时间 |

建议约束：

- 唯一索引：`account_id + normalized_historical_name + valid_from`。
- 查询索引：`normalized_historical_name + status`。
- 查询索引：`warehouse_id + status`。
- `confidence` 限制在 `0..1`。
- `valid_to >= valid_from`。
- 同一账号、同一历史名称的有效期不得重叠。

`warehouse_id` 建议保存平台真实 ID，并在应用层关联
`RawWb::WarehouseRegion`。不要外键关联 `raw_wb_warehouses.id`，因为该表当前混合了
FBS 卖家仓、FBO 名称仓和系统生成的伪外部 ID。

## 4. 名称解析规则

统一提供只读服务，例如：

```ruby
RawWb::WarehouseNameResolver.resolve(
  account_id: account.id,
  warehouse_name: stats_order.warehouse_name,
  on: stats_order.order_date.to_date
)
```

返回建议包含：

```ruby
{
  warehouse_id: 301981,
  warehouse_name: "Владимир WB",
  region_name: "Центральный",
  match_type: :verified_alias,
  confidence: 1.0
}
```

解析优先级：

1. 按账号、规范化名称、订单日期匹配 `verified` 别名。
2. 匹配全账号通用、规范化名称、订单日期的 `verified` 别名。
3. 按账号直接匹配 `WarehouseRegion.normalized_warehouse_name`。
4. 跨账号匹配唯一的 `warehouse_id + normalized_name` 平台事实。
5. 返回未映射；候选映射只用于后台审核，不参与正式报表。

禁止使用以下自动推断作为正式映射：

- 仅凭城市名映射最近仓库。
- 仅凭字符串相似度自动确认。
- 将买家 `region_name/oblast_okrug_name` 当作发货仓区域。
- 将 FBS 卖家仓映射到 WB FBO 区域。

## 5. 同步策略

### 5.1 当前仓库字典

`WarehouseRegionSync` 应继续同步两个来源：

- `/api/analytics/v1/stocks-report/wb-warehouses`
- `/api/v2/stocks-report/offices`

建议调整：

- 查询周期使用稳定回看窗口，例如最近 90 天，而不是只查当天。
- 不删除本次响应未返回的旧仓库；增加 `last_seen_at` 和 `is_active` 管理状态。
- 按 `warehouse_id` 更新当前名称时，记录名称变化候选。
- 同一 `warehouse_id` 出现新旧名称时，自动生成高置信候选别名，但仍保留审核记录。

### 5.2 历史名称发现

每日或同步完成后汇总 FBO Statistics 订单：

```text
account_id + warehouse_name + first_order_at + last_order_at + order_count
```

未被 Resolver 解析的名称进入候选列表。候选项应展示：

- 历史名称和订单量。
- 首次、最后出现时间。
- 涉及 SKU 数量。
- 相似的当前仓库名称。
- 当前仓库区域和硬 ID。
- 是否在其他账号的仓库字典中出现。

字符串相似度只用于排序候选，不能自动写入 `verified`。

## 6. 初始数据回填

### 第一批：高置信映射

将本方案第 2 节中的 6 条映射以 `verified`、`confidence = 1.0` 写入。
写入前必须再次通过 `warehouse_id` 校验目标仓库及区域。

### 第二批：历史仓库调查

对剩余名称依次使用：

1. 更长周期的 `/api/v2/stocks-report/offices` 查询。
2. 其他账号已有的 Analytics 仓库事实。
3. WB 历史导出或后台页面记录。
4. 人工确认。

无法确认的名称保持未映射，并在报表中显示“未知区域”，不能阻塞其他订单统计。

### 第三批：回填解析结果

不建议立即把解析结果写回每条 `RawWb::StatsOrder`。第一版在 Query 中通过 Resolver
解析，避免主数据调整后批量重写订单。

如果后续性能需要物化，可新增：

- `resolved_warehouse_id`
- `warehouse_mapping_id`
- `warehouse_resolved_at`

物化字段必须能按映射版本重新计算。

## 7. 报表口径

WB 分仓报表只使用：

```text
StatsOrder.srid
  -> SkuProduct 硬关联
  -> StatsOrder.warehouse_name
  -> WarehouseNameResolver
  -> WarehouseRegion.warehouse_id / region_name
```

订单分类：

- `Склад WB` 且已解析：进入对应 WB 区域和仓库。
- `Склад WB` 且未解析：进入“未知 WB 仓库”。
- `Склад продавца`：进入“卖家仓/Маркетплейс”，不调用 Resolver。

报表必须显示：

- 已映射订单数及覆盖率。
- 未映射订单数。
- 未映射仓库名称列表。
- 使用别名映射的订单数。

## 8. 管理与审核

建议增加简单的后台管理页：

- 查看未映射历史名称，按订单量降序。
- 选择目标 `WarehouseRegion`。
- 设置账号范围和有效期。
- 查看系统推荐候选及证据。
- 确认、拒绝或停用映射。
- 显示映射变更历史。

修改映射属于业务口径变更，应记录操作者、时间、旧值和新值。

## 9. 测试要求

模型测试：

- 规范化、唯一性、有效期和状态校验。
- 账号特例优先于全局映射。
- 有效期边界正确。

Resolver 测试：

- 直接名称匹配。
- 高置信别名匹配。
- 跨账号唯一事实匹配。
- 多目标冲突时返回未映射。
- FBS 不进入 FBO Resolver。
- 候选映射不影响正式结果。

同步测试：

- 仓库重命名生成候选，不覆盖历史事实。
- 暂时未返回的仓库不会被删除。
- 同一任务重复执行保持幂等。

报表测试：

- SKU 归属继续遵循 `ec_sku_products` 的店铺、平台和产品硬关联规则。
- 已映射、未映射和 FBS 数量之和等于输入订单数。
- 覆盖率计算准确。

## 10. 验收标准

第一阶段：

- FBO 发货仓加权覆盖率不低于 99%。
- 未映射订单全部进入显式未知分组。
- 不存在一个历史名称同时映射多个有效目标的情况。
- FBS 不混入 WB FBO 区域。

第二阶段：

- 剩余 17 条历史订单全部有平台证据或人工结论。
- 覆盖率达到 100%，或对无法确认的历史记录形成正式例外清单。
- 新出现未映射名称可在下一次同步后被发现并告警。

## 11. 推荐实施顺序

1. 使用 Rails generator 创建映射表 migration。
2. 实现模型、规范化规则和 Resolver。
3. 写入并验证 6 条高置信初始映射。
4. 修改 `WarehouseRegionSync`，保留历史仓库并记录 `last_seen_at`。
5. 增加未映射名称统计服务和后台审核页。
6. WB 分仓 Query 接入 Resolver，并展示覆盖率。
7. 调查剩余历史名称，完成第二批映射。

