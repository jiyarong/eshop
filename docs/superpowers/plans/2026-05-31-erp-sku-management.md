# ERP SKU 管理和类别管理实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 为基础 ERP 增加三级类别管理和 SKU 手动录入/编辑能力。

**架构：** 复用现有 `Ec::Sku`，新增 `Ec::SkuCategory`。录入页面使用 Rails Controller + ERB 表单，现有 `/reports/skus` 继续作为只读报表。

**技术栈：** Rails 8、Active Record、ERB、Minitest、PostgreSQL。

---

## 文件结构

- 创建：`db/migrate/20260531000007_create_ec_sku_categories.rb`
- 创建：`db/migrate/20260531000008_add_management_fields_to_ec_skus.rb`
- 创建：`app/models/ec/sku_category.rb`
- 修改：`app/models/ec/sku.rb`
- 创建：`app/controllers/erp/sku_categories_controller.rb`
- 创建：`app/controllers/erp/skus_controller.rb`
- 修改：`config/routes.rb`
- 修改：`app/views/layouts/application.html.erb`
- 创建：`app/views/erp/sku_categories/index.html.erb`
- 创建：`app/views/erp/sku_categories/show.html.erb`
- 创建：`app/views/erp/sku_categories/new.html.erb`
- 创建：`app/views/erp/sku_categories/edit.html.erb`
- 创建：`app/views/erp/sku_categories/_form.html.erb`
- 创建：`app/views/erp/skus/index.html.erb`
- 创建：`app/views/erp/skus/show.html.erb`
- 创建：`app/views/erp/skus/new.html.erb`
- 创建：`app/views/erp/skus/edit.html.erb`
- 创建：`app/views/erp/skus/_form.html.erb`
- 创建：`test/models/ec/sku_category_test.rb`
- 创建：`test/controllers/erp/sku_categories_controller_test.rb`
- 创建：`test/controllers/erp/skus_controller_test.rb`

## 任务 1：类别模型

- [ ] 编写 `test/models/ec/sku_category_test.rb`，覆盖编码大写、父子级、最多 3 级。
- [ ] 运行测试，预期 `Ec::SkuCategory` 未定义。
- [ ] 新增类别迁移和模型。
- [ ] 运行类别模型测试通过。
- [ ] Commit：`feat: add ERP SKU categories`

## 任务 2：扩展 SKU 模型

- [ ] 编写 SKU 模型测试，覆盖 SKU 关联类别和属性字段保存。
- [ ] 运行测试，预期字段不存在。
- [ ] 新增 SKU 管理字段迁移，修改 `Ec::Sku` 关联。
- [ ] 运行 SKU 模型测试和现有 SKU 报表测试通过。
- [ ] Commit：`feat: add ERP SKU management fields`

## 任务 3：类别手动录入页面

- [ ] 编写类别 Controller 测试，覆盖 index/show/new/create/edit/update。
- [ ] 运行测试，预期路由不存在。
- [ ] 新增路由、Controller、ERB 页面和表单。
- [ ] 运行类别页面测试通过。
- [ ] Commit：`feat: add ERP SKU category pages`

## 任务 4：SKU 手动录入页面

- [ ] 编写 SKU Controller 测试，覆盖 index/show/new/create/edit/update。
- [ ] 运行测试，预期路由不存在。
- [ ] 新增路由、Controller、ERB 页面和表单。
- [ ] 更新导航入口。
- [ ] 运行 SKU 页面测试和现有报表测试通过。
- [ ] Commit：`feat: add ERP SKU management pages`

## 任务 5：整体验证

- [ ] 运行：

```bash
rbenv exec ruby bin/rails test test/models/ec/sku_category_test.rb test/models/ec/sku_test.rb test/controllers/erp/sku_categories_controller_test.rb test/controllers/erp/skus_controller_test.rb test/controllers/reports_controller_test.rb
```

- [ ] 运行：

```bash
rbenv exec ruby bin/rails routes | rg "erp_skus|erp_sku_categories|reports_skus"
```

- [ ] 如有修复，单独提交。

