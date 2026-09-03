# AGENTS.md

本文件记录本项目当前业务上下文和实现约束，供后续 Agent 进入仓库时快速对齐。通用行为规范仍以会话系统指令和用户最新要求为准。

## 项目定位

这是一个电商经营数据管理项目，后端使用 Rails 8。项目会从 WB、Ozon 等平台同步原始数据，经过 `Ec::*` 
## 后端开发
- 不要直接创建migration文件，而是使用rails generate migration命令生成migration文件，确保文件名和类名一致。
- 本项目本地 Web 默认端口为 `4010`, 开发完成后不需要打开网页帮我验证，直接运行 Rails 测试即可。

## 前端方向
- 实现功能后不需要帮我运行yarn build或vite build等前端构建命令，除非用户明确要求。
- 新报表页面使用 Rails 自带页面体系：Controller + ERB + Turbo/Hotwire 风格交互。
- 当前 Rails 项目是 `api_only` 配置，但已经通过 `ApplicationController` 支持明确的 HTML 请求。
- JSON API 仍要保留 `.json` 路径能力，避免破坏已有接口测试和后续集成。
- 页面上展示给用户看的文本都应通过 Rails I18n 管理，不要在 ERB、helper、controller 或前端脚本中新增硬编码展示文案。
- 现有页面布局在 `app/views/layouts/application.html.erb`

## 通用页面组件

- 开发新 Rails 页面或筛选表单前，先检查 `app/views/shared/` 和对应 Stimulus controller；下列场景必须优先复用现有组件，不要在业务页面重复实现下拉框、弹层、搜索或日期选择逻辑。
- 实现组件时，如存在明确的跨页面或跨业务复用场景，应在不增加无必要抽象的前提下设计通用接口，避免组件依赖单一业务页面的实例变量、路由或数据结构。
- 新增或扩展出可复用组件后，必须在本节记录其适用场景、组件路径、调用方式和关键约束；后续实现相关功能时应自动优先检查并使用该通用组件，仅在现有组件无法满足明确需求时新增实现。
- 组件展示文案继续使用 `shared.*` 下已有 I18n；新增通用文案时补齐项目支持的 locale，不要把业务文案写进 shared partial 或 Stimulus controller。
- 同一页面多次渲染同一种组件时，必须传入页面内唯一的 `dom_id_prefix` 或 `id`，避免 trigger、popover 和表单控件 ID 冲突。

### 开发人员、运营人员选择器

- 列表筛选统一使用 `app/views/shared/_responsible_user_filters.html.erb`，交互由 `app/javascript/controllers/responsible_user_filter_controller.js` 提供；参考 `/erp/skus`。
- Controller 应 `include ResponsibleUserFilterable`，调用 `load_responsible_user_filters` 准备 `@developer_id`、`@operator_id` 和选项，再按数据类型调用：
  - `apply_responsible_user_filters_to_skus(scope)`：过滤 `Ec::Sku`。
  - `apply_responsible_user_filters_to_master_skus(scope)`：过滤 `Ec::MasterSku`。
  - `apply_responsible_user_filters_to_sku_records(scope)`：过滤含 `sku_code` 的其他记录。
- partial 默认同时输出 `developer_id`、`operator_id` 两个单选筛选项；只需要一种角色时传 `filter_keys: %w[developer]` 或 `filter_keys: %w[operator]`。同时传页面唯一的 `dom_id_prefix`；`field_class` 可用于适配所在表单布局。
- 编辑表单里的单个负责人选择统一使用 `app/views/shared/_responsible_user_single_select.html.erb`，不要拿筛选 partial 代替。必须传 `component_id`、`param_name`、`label`、`placeholder`、`selected_id`、`options`，需要区分清空按钮文案时传 `clear_label`。`/erp/skus` 的开发人员、运营人员编辑弹窗是参考实现。
- 负责人业务归属保持现有模型语义：开发人员来自 `Ec::SkuDeveloperAssignment`；运营人员来自平台商品的 `Ec::SkuProductOperator` operator 角色。不要仅凭页面参数自行发明另一套关联规则。

### SKU、SPU 选择器

- SKU/SPU 筛选或表单选择统一使用 `app/views/shared/_spu_sku_filter.html.erb`，交互由 `app/javascript/controllers/spu_sku_filter_controller.js` 提供；参考 `/erp/skus` 和 `/weekly_profit_reports`。
- 筛选页面的 Controller 应 `include SpuSkuFilterable`，调用 `load_spu_sku_filter` 准备 SPU、SKU 和已选值，再使用 `apply_spu_sku_filter_to_skus(scope)` 或 `apply_spu_sku_filter_to_sku_records(scope)` 应用筛选。
- 默认多选参数为 `master_sku_ids[]` 和 `sku_codes[]`，选择 SPU 与直接选择 SKU 按并集过滤；未归属 SPU 的 SKU 也由组件统一展示。不要另写只覆盖已归属 SKU 的选择器。
- 常用 locals：`dom_id_prefix`、`field_class`、`label`、`placeholder`、`aria_label`。默认 `selection_mode: :multiple`；表单只允许选择单个 SKU 时传 `selection_mode: :single`，并可用 `sku_input_name` 自定义字段名。只有调用方已经自行准备数据时，才直接传 `master_skus`、`orphan_skus`、`selected_master_sku_ids`、`selected_sku_codes`。

### 日期范围选择器

- 日期范围统一使用 `app/views/shared/_time_range_selector.html.erb`，交互由 `app/javascript/controllers/time_range_selector_controller.js` 提供；`/weekly_profit_reports` 是报表筛选的参考实现。
- 必须传页面内唯一的 `id`、`from_date`、`to_date`。组件默认提交 `from_date`、`to_date`；其他查询参数名通过 `from_name`、`to_name` 指定。
- 需要用户点击“应用”后立即提交所在表单时传 `submit_on_apply: true`，否则保持默认 `false`。组件已经提供日期区间、自然周快捷项、前后周期切换和本月快捷项，不要在业务页面重复实现。
- 组件用 `user_today` 计算当前日期，遵循用户时区。Controller 仍需负责默认日期、参数解析和业务有效性校验；不要依赖前端组件替代服务端校验。

### 附件列表与上传

- 附件列表、上传弹窗、批量拖拽、待提交文件列表、文件类型图标和预览弹窗统一使用 `app/views/shared/_attachments.html.erb`；交互由 `attachment_upload_controller.js` 和 `attachment_preview_controller.js` 提供，文件类型与行内编辑 locals 由 `AttachmentsHelper` 组装。`/reports/skus/:sku_code` 基础配置中的附件区域是参考实现。
- 仅需在附件列表外触发同款预览弹窗时，复用 `app/views/shared/_attachment_preview_dialog.html.erb`，传入页面内唯一的 `id`；触发元素与外层容器仍须遵循 `attachment_preview_controller.js` 的 `data-controller`、`data-action` 和预览数据属性协议。
- partial 必须传 `attachments`、页面内唯一的 `dom_id_prefix`、`can_manage`、`attach_type_options`、`upload_path`，以及 `download_path_for`、`preview_path_for`、`edit_path_for`、`delete_path_for` 四个接收 attachment 的 lambda。组件不应读取业务页面实例变量，也不要在 shared partial 中拼接某种模型的路由。
- 上传表单统一提交 `ec_attachment[attach_type]` 和多文件参数 `ec_attachment[files][]`。Controller 必须逐个校验允许的附件类型，批量创建 `Ec::Attachment` 和 `Ec::AttachmentLink`，失败时清理本次已创建的 blob，避免遗留孤立文件。
- 业务模型通过 `Ec::AttachmentLink` 的 polymorphic `attachable` 关联附件；接入模型应声明 `has_many :attachment_links, as: :attachable` 和通过关联得到的 `attachments`。页面组件支持任意已接入模型，但服务端路由和权限仍由各业务 Controller 提供；不要建立接收任意 `class_name + id` 并 `constantize` 的通用接口。
- 查找、编辑、预览、下载和删除附件时，必须从当前业务对象的 `attachments` 关联中查询，不能直接用 `Ec::Attachment.find(params[:attachment_id])`，防止跨模型访问。每个动作继续使用该业务对象原有的查看或管理权限。
- 附件类型编辑复用 `app/views/shared/_inline_edit_cell.html.erb`、`InlineEditableResponse` 和 Turbo Stream 回写模式，只允许白名单字段 `attach_type`。`Ec::Attachment` 已接入 `Ec::Auditable`，新增可编辑字段时同时评估并更新 `Ec::AuditConfig`，不得绕过操作日志。
- 文件预览按能力降级：图片、PDF、文本及浏览器支持的音视频使用内联预览；Office 文件仅在对象存储能提供外部可访问 URL 时使用 `view.officeapps.live.com`；压缩包或其他不支持格式在弹窗中展示对应文件图标和不可预览提示。不要信任上传者声明的 MIME 作为内联响应类型，应按服务端允许的扩展名映射安全 MIME。

### 其他已复用组件

- 表格滚动视口：业务表格使用 `ApplicationHelper#table_viewport` 包裹，调用形式为 `<%= table_viewport do %>...<% end %>`；字段过多时在组件内部横向滚动。需要明确限制高度时传 `max_height:`，需要附加样式类时传 `class_name:`，其他 HTML 属性可直接传入。菜单入口中的主列表使用 `.table-list-card` 包裹顶部分页和 `table_viewport(class_name: "table-list-viewport")`，分页必须位于表格视口上方；主列表只建立横向滚动边界，纵向滚动始终交给页面，避免鼠标位于表格上时形成滚动陷阱。需要在页面纵向滚动时固定表头的主列表传 `sticky_header: true`，交互由 `app/javascript/controllers/sticky_table_header_controller.js` 提供；该实现参考 floatThead 的 responsive window scrolling 架构，通过独立浮动表头同步列宽和横向位置，不要再给主列表增加内部纵向滚动。只有抽屉或明确使用 `.table-scroll--contained` 的局部表格可以建立内部纵向滚动。旧 `.table-scroll` 保留兼容行为，新页面不要自行重复实现 `overflow` 或 sticky 表头；展开行中的嵌套表格仅在自身确实需要独立滚动时再单独包裹。
- 可排序表头：Controller `include TableSortable`，调用 `load_table_sort(allowed_keys: ...)` 对 `sort`、`direction` 做白名单解析；内存指标排序可使用 `sort_table_records(records) { |record| ... }`，空值会统一排在末尾。ERB 使用 `app/views/shared/_sortable_table_header.html.erb`，传 `label`、`sort_key`，按需传 `class_name`、`style`、`title`。组件会保留现有查询参数，按未排序、降序、升序三态切换并清除分页参数；业务 Controller 仍须显式定义字段到安全 SQL 或指标取值的映射，排序必须在分页前完成。
- 任意枚举或简单选项的可搜索多选筛选：`app/views/shared/_popover_multiselect_filter.html.erb` + `popover_multiselect_filter_controller.js`。传 `dom_id_prefix`、`param_name`、`label`、`all_label`、`selected_values`、`options`；提交参数自动使用 `param_name[]`。
- SPU 类目多选筛选：`app/views/shared/_master_sku_category_filter.html.erb` + `MasterSkuCategoryFilterable`。它按 Master SKU 的类目过滤，区别于编辑表单中选择单个类目的 `app/views/shared/_category_selector.html.erb`，两者不要混用。
- 表格行内编辑：`app/views/shared/_inline_edit_cell.html.erb` + `inline_cell_controller.js` + `InlineEditableResponse`。新字段接入时沿用现有 helper 组装 locals、Turbo Frame 编辑和 Turbo Stream 回写模式；Controller 必须对允许编辑的字段使用白名单。
- 可搜索关联记录选择：`app/views/shared/_association_picker.html.erb` + `association_picker_controller.js`。搜索接口返回 `[{ id:, label: }]` JSON；如支持弹窗新建，页面还需提供 `association_create_modal` Turbo Frame，并按现有 `association-picker:selected` 事件协议回填。
- Turbo 侧边抽屉外壳：`app/views/shared/_overlay_drawer.html.erb`，配合 `modal_controller.js`。传 `frame_id`、`title_id`、`title`、`body`，按需传 `subtitle`、`eyebrow`、`header_actions`、`close_path`、`drawer_width`；业务内容保留在调用方 partial，不要复制抽屉遮罩、标题栏和关闭逻辑。

## 当前报表现状

- 报表导航当前包含：
  - `/weekly_profit_reports`
  - `/reports/inventory`
  - `/reports/skus`
  - `/reports/costs`
- 新报表优先继续走 Rails 页面，不要新开 React/Vite 报表承载层。

### 库存报表

- 入口：`GET /reports/inventory`
- 详情入口：`GET /reports/inventory/:sku_code`
- 当前页面读取链路：
  - 列表页：`ReportsController#inventory` + `Ec::InventoryPageRowQuery`
  - 详情页：`ReportsController#inventory_detail` + `Ec::InventoryPageDetailQuery`
  - SKU 汇总：`Ec::SkuInventoryOverview`
- 当前库存基础表：
  - `ec_sku_inventory_levels` / `Ec::SkuInventoryLevel`
  - `ec_sku_batches` / `Ec::SkuBatch`
  - `ec_order_items`、`ec_orders`
  - `raw_wb_goods_returns`、`raw_ozon_returns`
  - `raw_wb_supply_items`、`raw_ozon_supply_orders`
- 平台库存快照刷新：
  - 定时任务：`config/recurring.yml` 中的 `Ec::SkuInventorySnapshotSync.run`
  - 频率：生产每小时一次
  - 写入方式：抓平台当前库存后写入 `Ec::SkuInventoryLevel`，并维护 `is_latest`
- 页面查询约束：
  - `/reports/inventory` 和详情页 GET 请求保持只读
  - 不要在页面请求里直接调平台 API
  - 不要在页面请求里触发同步、写库或补数据
- 旧机制状态：
  - `Ec::InventorySnapshot`
  - `Ec::InventoryTotal`
  - `Ec::InventorySnapshotSync`
  - `GoogleSheets::InventorySnapshotWriteService`
  - `GoogleSheets::InventorySnapshotImportService`
  - `Ec::OperationTaskGenerator`
  - 以上整套旧库存快照/汇总机制已从项目移除，不应再作为当前实现参考

## 通用日快照机制

- 通用快照表为 `ec_snapshots`，模型为 `Ec::Snapshot`。
- 表的业务字段只有：
  - `snapshot_date`：快照日期。
  - `snapshot_type`：快照类型。不要改用 Rails STI 保留字段 `type`。
  - `sku_id`：可空外键，关联 `Ec::Sku`；SKU 维度快照应填写，全局快照留空。
  - `content`：`jsonb` 快照内容，默认 `{}`。
- 唯一约束分为两类：全局快照按 `snapshot_type + snapshot_date` 唯一，SKU 快照按 `snapshot_type + snapshot_date + sku_id` 唯一。
- 重复执行通过 `upsert_all` 覆盖同一快照内容，必须保持幂等。
- 通用执行入口为 `Ec::SnapshotRunner.run`：
  - 每个快照模块必须实现 `.snapshot_type`。
  - 每个快照模块必须实现 `.capture(snapshot_date:)` 并返回快照行数组。
  - 每行格式为 `{ sku_id: sku.id, content: {...} }`；全局快照的 `sku_id` 可省略或传 `nil`。
  - 新模块加入 `Ec::SnapshotRunner::SNAPSHOT_MODULES` 后，由统一任务执行。
  - 未显式传入日期时，使用 `Asia/Shanghai` 的当天日期；补跑可显式传入 `snapshot_date:`。
- 生产定时任务位于 `config/recurring.yml` 的 `daily_snapshot`，每天 `03:00 Asia/Shanghai` 执行。
- Ruby 读取 SKU 单日内容使用 `Ec::Snapshot.fetch(snapshot_type, on: date, sku: sku)`；不传 `sku:` 时读取全局快照。
- 返回内容支持字符串键和符号键混用，例如 `.dig(:summary, :quantity)`。
- 历史查询优先组合 `Ec::Snapshot.of_type(...)` 与 `Ec::Snapshot.between(from_date, to_date)`。
- 通用快照与每小时执行的 `Ec::SkuInventorySnapshotSync` 是两套不同机制，不要互相替代或混用。
- 页面 GET 请求不得触发快照采集或写入；快照应由定时任务或明确的后台补跑执行。

## 生产部署

- 生产部署使用 Kamal：`kamal deploy -c config/deploy.yml`。
- Kamal 配置文件是 `config/deploy.yml`，镜像构建使用根目录 `Dockerfile`。
- 不要把 `config/deploy.rb`（Mina）当作当前生产部署入口；排查 production 部署、镜像、assets 问题时优先看 Kamal 配置和 Dockerfile。
- production 缺少 Rails assets（例如 Propshaft 报 `application.js` missing）时，应检查 Docker image 构建阶段是否安装 Node 依赖并执行 `assets:precompile`，以及最终镜像内是否包含 `public/assets/.manifest.json` 和对应 digest 资源。

除非用户明确要求，Agent 不需要也不应主动启动 Web server，不主动运行 `npm run build`、`npm run build:css`、`vite build` 等前端构建命令；这些由用户自行运行。需要验证时，优先运行相关 Rails 测试，或在最终说明中明确列出未运行的前端构建。

## 数据与测试注意事项

- `test/test_helper.rb` 中 `use_transactional_tests = false`，测试必须清理自己创建的数据。
- 新测试数据尽量使用唯一 SKU 或唯一 token，避免中断后残留数据导致唯一索引冲突。
- 工作区经常存在无关脏改动，例如 `.idea/`、`config/database.yml`、根目录 `node_modules/`、`docs/` 临时文件、`yarn.lock`。不要回滚或提交这些无关改动。
- 提交时只 `git add` 本次任务相关路径。

## 订单与 SKU 关联策略

- 订单报表、库存销量、SKU 销量等统计逻辑不要用 `ec_order_items.sku_code` 作为 SKU 归属依据。
- SKU 与订单商品的归属应从 `ec_sku_products` 硬关联：
  - 先通过 `ec_sku_products.sku_code` 确定内部 SKU。
  - 必须同时限定 `ec_sku_products.store_id = ec_order_items.store_id` 和 `ec_sku_products.platform = ec_order_items.platform`。
  - Ozon 使用 `ec_sku_products.platform_sku_id = ec_order_items.platform_sku_id`。
  - WB 使用 `ec_sku_products.product_id = ec_order_items.platform_sku_id`。
- `ec_order_items.sku_code` 可能由导入流程写入，但只能作为冗余展示/排查线索；报表统计不能用它兜底匹配，避免未绑定或误绑定商品被算入 SKU。
- `offer_id` 不参与订单到 SKU 的报表统计归属匹配，除非后续业务明确重新定义绑定规则。

## 时间展示策略

- 用户资料使用 `users.time_zone` 保存时间展示时区，默认值是 `Asia/Shanghai`。
- Rails 页面展示业务时间时优先使用 `display_time(...)` helper，不要在 ERB 中直接 `strftime`。
- `display_time(...)` 按当前用户所选时区渲染，空值统一展示为 `-`，默认格式为 `%Y-%m-%d %H:%M`。
- 与日期筛选边界相关的页面逻辑，应使用同一用户时区计算当天起止时间，避免筛选日期与表格展示日期不一致。
