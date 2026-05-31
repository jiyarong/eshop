# ERP SKU 管理和类别管理设计规格

## 背景

当前项目已经有 `Ec::Sku` 作为 SKU 主数据，并有 `/reports/skus` 只读报表。基础 ERP 第一版已经新增批次、采购、费用分摊和运营任务页面，但 SKU 本身仍不能在 Rails 页面手动录入和维护。

本规格新增 ERP 内的 SKU 管理和类别管理，不改变现有 `/reports/skus` 报表定位。

## 目标

- 支持三级 SKU 类别管理。
- 支持在 ERP 页面手动新建和编辑 SKU。
- SKU 可关联类别，并维护颜色、规格、尺寸、重量、体积、型号、品质、特点等基础属性。
- 保留现有 `Ec::Sku`、库存、成本、周利润报表兼容性。

## 非目标

- 不做批量导入。
- 不做图片、附件和富文本详情。
- 不做删除 SKU。
- 不做平台商品链接编辑。
- 不做权限审批。
- 不把 `/reports/skus` 改成录入页。

## 数据模型

### `Ec::SkuCategory`

字段：

- `code`：类别编码，全局唯一，自动转大写。
- `name`：类别名称。
- `parent_id`：父级类别，可为空。
- `position`：排序。
- `is_active`：是否启用。
- `memo`：备注。

规则：

- 类别最多 3 级。
- 类别不能选择自己或自己的子级作为父级。
- `code` 和 `name` 必填。

### `Ec::Sku`

新增字段：

- `sku_category_id`
- `color`
- `spec`
- `size`
- `weight_kg`
- `volume_l`
- `model`
- `quality_grade`
- `features`

保留已有字段：

- `sku_code`
- `product_name`
- `product_name_ru`
- `is_active`
- `owner_name`
- `memo`

## 页面

新增：

- `/erp/sku_categories`
- `/erp/sku_categories/new`
- `/erp/sku_categories/:id`
- `/erp/sku_categories/:id/edit`
- `/erp/skus`
- `/erp/skus/new`
- `/erp/skus/:id`
- `/erp/skus/:id/edit`

页面风格沿用现有 Rails ERB 后台表格和表单。写操作只使用 `POST` 和 `PATCH`，GET 页面保持只读。

## 测试

必测：

- 类别最多 3 级。
- 类别编码自动大写。
- SKU 可以关联类别并保存属性。
- 类别新建、编辑、详情页面。
- SKU 新建、编辑、详情页面。
- 现有 `/reports/skus` 仍可渲染。

