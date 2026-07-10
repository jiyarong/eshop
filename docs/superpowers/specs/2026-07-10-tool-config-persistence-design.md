# 工具配置持久化与内嵌工具页设计

## 背景

当前团队已有一个本地 HTML 工具 `WB Pallet Optimizer`，其核心用途是做 WB 分仓测算。该工具目前把正式配置和临时状态都存放在浏览器 `localStorage` 中，存在几个问题：

- 配置只能留在单个浏览器环境里，无法在系统内共享。
- 无法在现有 Rails 系统中做配置列表、统一入口和版本管理。
- 后续会接入更多类似 HTML 工具，如果继续各自持久化到浏览器，本项目无法形成统一的工具中心。
- 新需求要求“新增时根据工具类型和版本打开对应测算工具，并默认打开某类型最新版本”，这已经超出单文件 HTML 能力边界。

因此需要把工具的正式配置持久化接管到系统数据库中，并把工具页面纳入 Rails 页面体系。

## 目标

本次实现的目标如下：

- 在数据库中持久化工具版本定义和工具配置实例。
- 为工具配置提供系统内列表页，支持查看、新增、编辑和另存为。
- 将 `WB Pallet Optimizer` 作为首个内嵌工具接入 Rails 页面。
- 新增配置时，能够按所选工具类型和版本打开对应测算工具。
- 当只指定工具类型时，默认打开该类型最新可用版本。
- 所有人都可以查看工具配置。
- 只有创建人可以覆盖编辑自己的配置。
- 非创建人打开他人配置时，只能基于当前内容“另存为”自己的配置。

## 非目标

- 本次不做工具配置物理删除。
- 本次不做复杂的工具发布后台或版本审批流。
- 本次不把工具 HTML 源码直接存进数据库。
- 本次不重写 `WB Pallet Optimizer` 的核心计算公式。
- 本次不接入 React/Vite 作为新工具承载层。
- 本次不对工具内部中俄双语文案做全面 I18n 重构。

## 设计约束

- 新页面继续使用 Rails 自带页面体系：Controller + ERB + Turbo/Hotwire 风格交互。
- 页面显示文案走 Rails I18n；工具内部已有字典的中俄文案暂可保留在工具脚本内。
- 页面请求保持只读，不在打开页面时写库。
- JSON 能力需保留，避免后续工具异步保存时再返工。
- 表名使用 `ec_` 前缀。
- 共享可见，不做按创建人隔离列表。
- 编辑权限不额外绑定角色；本次以“是否为创建人”作为覆盖保存的唯一条件。

## 数据模型

本次拆分为两张表，而不是把工具版本和工具配置混在一张表里。

### `ec_tool_definitions`

用途：定义系统里可打开的工具版本。

字段：

- `tool_type`，字符串，例如 `wb_pallet_optimizer`
- `version`，整数，例如 `1`
- `name`，字符串，用户可读名称
- `slug`，字符串，用于稳定标识
- `renderer_key`，字符串，决定渲染哪个内嵌工具页面
- `schema_json`，`jsonb`，默认 `{}`，用于后续存默认配置结构或元信息
- `active`，布尔，默认 `true`
- `created_by_id`，外键，指向 `users`
- timestamps

约束：

- `[tool_type, version]` 唯一
- `tool_type`、`version`、`name`、`slug`、`renderer_key`、`created_by_id` 必填
- `schema_json` 非空，默认 `{}` 

语义：

- `active` 表示该工具版本是否还可作为默认/可选版本使用。
- 某个 `tool_type` 可以同时存在多个版本。

### `ec_tool_configurations`

用途：保存一条具体的测算配置实例。

字段：

- `tool_definition_id`，外键，指向 `ec_tool_definitions`
- `name`，字符串，配置名称
- `config_json`，`jsonb`，默认 `{}`，保存工具表单数据
- `active`，布尔，默认 `true`
- `created_by_id`，外键，指向 `users`
- timestamps

约束：

- `tool_definition_id`、`name`、`config_json`、`created_by_id` 必填
- `config_json` 非空，默认 `{}`

语义：

- `active` 仅表示该配置记录是否启用。
- 本次不做“同一工具类型下只能有一个 active 版本”的规则。

## 默认版本选择规则

当用户只指定 `tool_type` 而不指定版本时：

1. 优先选择该 `tool_type` 下 `active: true` 的最高 `version`
2. 若该类型没有任何 `active: true` 版本，则退回该类型下整体最高 `version`

`version` 本次使用整数，避免字符串版本号导致 `10 < 2` 的排序问题。

## 页面与流转

### 列表页

新增工具配置列表页：

- `GET /reports/tools`

职责：

- 展示所有 `ec_tool_configurations`
- 支持按工具类型、版本、名称、`active` 过滤
- 支持打开、编辑、另存为入口

列表展示字段建议至少包含：

- 配置名称
- 工具类型
- 版本
- 工具名称
- 创建人
- 启用状态
- 更新时间

### 新增入口

- `GET /reports/tools/new`

职责：

- 选择 `tool_type` 和 `version`
- 进入对应工具页的新建模式

如果用户只选择了 `tool_type`，则按“默认版本选择规则”打开对应版本。

### 工具页

建议采用以下入口：

- `GET /reports/tools/:tool_type`
- `GET /reports/tools/:tool_type/versions/:version`
- `GET /reports/tool_configurations/:id`
- `GET /reports/tool_configurations/:id/edit`

模式说明：

- 新建模式：打开某个工具版本的空白配置
- 打开模式：加载某条已保存配置
- 编辑模式：仅创建人进入覆盖保存语义
- 另存为模式：加载已有配置内容，但保存时创建新记录

对于非创建人访问 `edit`：

- 不允许以覆盖原记录的方式编辑
- 可以重定向到“打开模式”，并在页面上提供“另存为”

## 权限语义

本次不新增角色权限判断，采用以下最小规则：

- 所有登录用户都可以查看列表和打开任意配置
- 只有配置创建人可以覆盖更新该配置
- 非创建人不能修改原记录
- 非创建人可以基于当前配置内容另存为自己的新记录

实现上可通过 `created_by_id == current_user.id` 判断当前用户是否 owner。

## 工具内嵌承载方案

`WB Pallet Optimizer` 作为首个工具，不再依赖本地下载目录中的 HTML 文件路径，而是接入 Rails 内部页面。

不建议把原始整页 HTML 原封不动存数据库或直接以静态文件引用。推荐做法是：

- Rails 页面壳负责系统导航、标题、动作按钮和 bootstrap 数据注入
- 工具主体拆成一个专属 partial
- 工具脚本作为独立前端资源加载
- `renderer_key` 决定当前 definition 使用哪个 partial 和脚本

首版接入原则：

- 不重写 `WB Pallet Optimizer` 的核心计算逻辑
- 不先改造成 React、Stimulus 组件化或其他模块化前端体系
- 优先保留原有 DOM 结构、元素 `id`、全局函数入口和交互行为
- 首版只替换页面壳层与持久化适配层，确保计算结果和现有 HTML 工具保持一致

例如：

- `renderer_key = "wb_pallet_optimizer_v1"`

对应渲染：

- 工具页面 partial
- 工具专属脚本入口

这样后续接入第二个、第三个 HTML 工具时，只需新增 definition 和 renderer 映射，不需要重构现有入口模型。

## 持久化接管策略

### 正式配置

原工具的正式存档目前依赖：

- `localStorage.wb_records`

本次改为数据库持久化：

- 左侧“档案库”读取当前工具版本下的 `ec_tool_configurations`
- `覆盖` 对应 `PATCH /reports/tool_configurations/:id`
- `新档` 对应 `POST /reports/tool_configurations`

配置 JSON 直接保存原工具收集出的表单状态对象，不做本次额外结构拆分。

### 临时草稿

原工具还有：

- `localStorage.wb_current_session`

本次建议保留它作为浏览器临时草稿能力，只用于防止用户刷新页面丢失未保存输入，不作为正式配置来源。

这样可以：

- 最小化对工具现有输入联动逻辑的改动
- 避免每次输入都写数据库
- 明确区分“正式配置”和“当前未保存草稿”

### 导入导出

原工具支持导出/导入历史记录 JSON。本次调整为：

- 导出：导出当前配置的 JSON 包，包含 `tool_type`、`version`、`name`、`config_json`
- 导入：只回填到当前表单，不直接写数据库
- 用户导入后仍需点击“覆盖”或“另存为”才落库

这样可避免导入行为绕过“非 owner 不能覆盖原配置”的规则。

## 页面行为规则

### owner 打开自己的配置

- 显示“覆盖保存”
- 显示“另存为”
- 可以修改名称和配置内容

### 非 owner 打开他人配置

- 可以查看并修改页面上的临时输入，以便做试算
- 不显示或禁用“覆盖保存”
- 显示“另存为”
- 保存时创建一条新的 `ec_tool_configuration`

### 新建配置

- 用户从工具列表页进入新建
- 系统依据 `tool_type + version` 打开对应工具
- 工具页初始化为空白配置或 `schema_json` 派生默认值

## 路由与接口

### 页面路由

- `GET /reports/tools`
- `GET /reports/tools/new`
- `GET /reports/tools/:tool_type`
- `GET /reports/tools/:tool_type/versions/:version`
- `GET /reports/tool_configurations/:id`
- `GET /reports/tool_configurations/:id/edit`

### 写接口

- `POST /reports/tool_configurations`
- `PATCH /reports/tool_configurations/:id`

规则：

- owner 可 `PATCH`
- 非 owner `PATCH` 返回 `403`

### JSON 接口

- `GET /reports/tool_configurations/:id.json`
- `GET /reports/tools/library.json`

用途：

- 工具页初始化和局部刷新
- 后续如果改为 Turbo 局部更新或异步保存，可直接复用

## Controller 结构建议

建议拆成独立 controller，而不是继续堆到 `ReportsController` 中：

- `Reports::ToolsController`
- `Reports::ToolConfigurationsController`

原因：

- 这套功能已经形成独立子域，不适合继续挤在现有库存/SKU 报表 controller 中
- 工具定义、工具配置、renderer 分发、owner 校验都需要独立职责边界

同时新增一个轻量 renderer 分发层，例如：

- `Reports::ToolRendererResolver`

职责：

- 根据 `renderer_key` 找到对应 partial、脚本入口和 bootstrap 结构
- 未知 `renderer_key` 时返回明确错误，而不是页面白屏

## 测试方案

至少覆盖以下测试：

### Model

- `Ec::ToolDefinition` 的必填校验
- `Ec::ToolDefinition` 的 `[tool_type, version]` 唯一性
- `Ec::ToolConfiguration` 的必填校验
- `Ec::ToolConfiguration` 与 `created_by`、`tool_definition` 的关联

### Controller / Request

- 登录用户可访问 `/reports/tools`
- `POST /reports/tool_configurations` 可创建配置
- owner 可更新自己的配置
- 非 owner 更新返回 `403`
- `/reports/tools/:tool_type` 默认打开最新 active 版本
- 当某类型没有 active 版本时，会退回整体最新版本
- 打开已保存配置时，页面能注入正确 bootstrap JSON

### View / 页面行为

- owner 页面显示“覆盖保存”和“另存为”
- 非 owner 页面不显示“覆盖保存”，但显示“另存为”
- 列表页展示工具类型、版本、创建人、更新时间等核心字段

### Renderer

- `wb_pallet_optimizer_v1` 能解析到正确 renderer
- 未知 `renderer_key` 会返回明确异常或错误页

## 风险与取舍

### 保留工具脚本内部字典

工具内部已经有中俄双语字典。完全迁移到 Rails I18n 会显著放大本次改造范围，因此本次只要求：

- Rails 外层页面文案走 I18n
- 工具内部现有双语逻辑暂保留

这是为了先完成持久化接管和统一入口，再决定是否做工具内部文案统一化。

### 保留临时 `localStorage`

正式存档改走数据库，但临时草稿保留在浏览器中。这不是混乱，而是刻意的职责分离：

- 数据库负责共享、可追踪、正式配置
- 浏览器负责当前页面的短期抗刷新草稿

### 本次不做删除

共享配置场景里，物理删除容易误伤。先用 `active` 表达可用状态，等真实使用后再决定是否需要“仅创建人可删除”或软删除策略。

## 实施结果预期

完成后，系统将具备以下能力：

- 以数据库接管工具正式配置持久化
- 在 Rails 内统一展示工具配置列表
- 支持基于工具类型和版本打开对应测算工具
- 对同类型工具默认打开最新可用版本
- 首个接入 `WB Pallet Optimizer`
- 支持共享查看、owner 覆盖、非 owner 另存为
- 为后续更多 HTML 工具接入提供统一骨架
