# AGENTS.md

本文件记录本项目当前业务上下文和实现约束，供后续 Agent 进入仓库时快速对齐。通用行为规范仍以会话系统指令和用户最新要求为准。

## 项目定位

这是一个电商经营数据管理项目，后端使用 Rails 8。项目会从 WB、Ozon 等平台同步原始数据，经过 `Ec::*` 
## 后端开发
- 不要直接创建migration文件，而是使用rails generate migration命令生成migration文件，确保文件名和类名一致。
- 本项目本地 Web 默认端口为 `4010`, 开发完成后不需要打开网页帮我验证，直接运行 Rails 测试即可。

## 查询性能约束

2026-10-13 的 `/reports/skus/QJD001-3?tab=inventory` 查询暴露了超长订单号 `IN`、全量财务记录加载、重复库存计算和循环查询问题。后续开发 Controller、报表 Query、Context 和归因服务时，必须遵守以下约束：

- 数据库记录之间的关联查询不得先用 `pluck` / `map` 提取订单 ID、订单号或 `posting_number` 数组，再拼成字面量 `IN` 条件。使用 `joins`、关联 `EXISTS` 或保持为 Relation 的子查询，例如 `where(order_id: scope.select(:order_id))`；不要对该子查询调用 `to_a` / `pluck`。订单数量增长不应导致 SQL 文本同步膨胀。
- 在加载记录前，先把 SKU、相关店铺/账号、日期和状态条件下推到 SQL。单 SKU 查询不得默认遍历所有账号或加载账号全部财务历史后再用 Ruby 筛选；只选择后续计算需要的字段。
- 数量、金额、状态分布等确定性汇总优先使用 SQL `SUM`、`COUNT`、`GROUP BY` 和条件聚合。不要实例化全部订单、财务行或供货单仅用于 Ruby 求和；只有退货逐单分配等确实需要明细的业务才加载已过滤的记录。
- 多 SKU、多店铺、多周期的指标优先批量查询并按业务键分组；关联展示使用 `preload` / `includes`。不要在逐记录、逐店铺、逐周期循环中重复执行可合并的查询，新增列表查询必须检查 N+1。
- 同一请求或 Query 实例内复用已计算的库存概览、SKU 映射和汇总结果，避免多次调用同一重型服务。复用结果必须限定于相同 SKU、日期、时区和筛选条件；不要为掩盖重复计算而给模型添加可能过期的跨请求缓存。
- 页面按当前 tab 加载所需数据；详情头部和当前库存只查询最新快照，不要预加载全部库存历史或其他 tab 的销售、趋势数据。
- 聚合和过滤优化必须保持业务口径：账号级广告分摊分母、条码间接归属、退货分配上限及 posting 范围、状态优先级、日期边界和时区不得改变。检查一对多 JOIN 是否导致数量或金额重复累计；只需判断关联存在时优先使用 `EXISTS`，需要连接时先按正确业务键聚合或去重。
- 新增或修改查询后，必须运行相关 Rails 测试，并验证有代表性数据的输出和性能。优化现有查询时对比完整结果；回归检查应覆盖未命中缓存的 SQL 次数、最大 SQL 长度和实例化记录数，批量场景检查查询次数是否随记录数线性增长。不能仅凭 Rails query cache 命中或一次运行耗时判断已解决性能问题；仍有慢 SQL 时检查执行计划和关联/筛选索引。
- 本地真实数据性能对比保持只读，不触发平台 API、同步或补数据；报告测量范围，服务级统计不能冒充整页请求统计。

现有实现参考：`Ec::OzonProfitAttribution` 的关联 `EXISTS` 与分组聚合、`Ec::Inventory::BookLedger` 的汇总与退货明细分离、`Ec::InventoryPageDetailQuery` 的概览复用、`Ec::WeeklySummarySupport` 的相关账号子查询。

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
- 负责人业务归属保持现有模型语义：开发人员来自 `Ec::SkuDeveloperAssignment`；运营人员来自 SKU 级 `Ec::SkuOperatorAssignment`，每个 SKU 最多一人，无需上架平台商品。旧 `Ec::SkuProductOperator` 保留历史数据供未来 Listing 级需求使用，当前筛选、权限与报表不得读取它。

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

- SKU Planner 计划标签：`app/views/shared/_sku_operation_plan_tags.html.erb`，用于 SKU 详情与 SKU 工作台的 AI 建议区；工作台 AI 建议筛选与表格标签只使用 latest 计划，不包含旧诊断 `scope: advise` 事件。传 `plans`（当前 SKU 的 latest 计划）及页面唯一的 `dom_id_prefix`。标签包含状态颜色、剩余时间和弹窗 trigger；调用方须在表格滚动视口外渲染 `reports/_sku_operation_plan_dialog.html.erb`（传 `plan`、`sku`、相同的 `dom_id_prefix`、`referer_dom_id_prefix`、该 SKU 的 `events_by_id`）及 `reports/_sku_operation_plan_referer_dialogs.html.erb`（使用相同的 `referer_dom_id_prefix`），确保 ID 对应且不跨 SKU 读取事件。
- 表格滚动视口：业务表格使用 `ApplicationHelper#table_viewport` 包裹，调用形式为 `<%= table_viewport do %>...<% end %>`；字段过多时在组件内部横向滚动。需要明确限制高度时传 `max_height:`，需要附加样式类时传 `class_name:`，其他 HTML 属性可直接传入。菜单入口中的主列表使用 `.table-list-card` 包裹顶部分页和 `table_viewport(class_name: "table-list-viewport")`，分页必须位于表格视口上方；主列表只建立横向滚动边界，纵向滚动始终交给页面，避免鼠标位于表格上时形成滚动陷阱。需要在页面纵向滚动时固定表头的主列表传 `sticky_header: true`，交互由 `app/javascript/controllers/sticky_table_header_controller.js` 提供；该实现参考 floatThead 的 responsive window scrolling 架构，通过独立浮动表头同步列宽和横向位置，不要再给主列表增加内部纵向滚动。只有抽屉或明确使用 `.table-scroll--contained` 的局部表格可以建立内部纵向滚动。旧 `.table-scroll` 保留兼容行为，新页面不要自行重复实现 `overflow` 或 sticky 表头；展开行中的嵌套表格仅在自身确实需要独立滚动时再单独包裹。
- 可排序表头：Controller `include TableSortable`，调用 `load_table_sort(allowed_keys: ...)` 对 `sort`、`direction` 做白名单解析；内存指标排序可使用 `sort_table_records(records) { |record| ... }`，空值会统一排在末尾。ERB 使用 `app/views/shared/_sortable_table_header.html.erb`，传 `label`、`sort_key`，按需传 `class_name`、`style`、`title`。组件会保留现有查询参数，按未排序、降序、升序三态切换并清除分页参数；业务 Controller 仍须显式定义字段到安全 SQL 或指标取值的映射，排序必须在分页前完成。
- 任意枚举或简单选项的可搜索多选筛选：`app/views/shared/_popover_multiselect_filter.html.erb` + `popover_multiselect_filter_controller.js`。传 `dom_id_prefix`、`param_name`、`label`、`all_label`、`selected_values`、`options`；提交参数自动使用 `param_name[]`。
- SPU 类目多选筛选：`app/views/shared/_master_sku_category_filter.html.erb` + `MasterSkuCategoryFilterable`。它按 Master SKU 的类目过滤，区别于编辑表单中选择单个类目的 `app/views/shared/_category_selector.html.erb`，两者不要混用。
- 表格行内编辑：`app/views/shared/_inline_edit_cell.html.erb` + `inline_cell_controller.js` + `InlineEditableResponse`。新字段接入时沿用现有 helper 组装 locals、Turbo Frame 编辑和 Turbo Stream 回写模式；Controller 必须对允许编辑的字段使用白名单。
- 可搜索关联记录选择：`app/views/shared/_association_picker.html.erb` + `association_picker_controller.js`。搜索接口返回 `[{ id:, label: }]` JSON；如支持弹窗新建，页面还需提供 `association_create_modal` Turbo Frame，并按现有 `association-picker:selected` 事件协议回填。
- 关联选择器只搜索已有记录时省略 `create_url`，组件会隐藏新建按钮；非 `id/name` 模型可传 `selected_value`、`selected_label` 作为当前值，`selected_record` 仍兼容原调用。`dom_id` 必须在页面内唯一；业务搜索接口负责权限及数据范围，提交后继续在服务端校验所选记录。
- Turbo 侧边抽屉外壳：`app/views/shared/_overlay_drawer.html.erb`，配合 `modal_controller.js`。传 `frame_id`、`title_id`、`title`、`body`，按需传 `subtitle`、`eyebrow`、`header_actions`、`close_path`、`drawer_width`；业务内容保留在调用方 partial，不要复制抽屉遮罩、标题栏和关闭逻辑。

## AI Agent 工具选择

- GBrain 和网页搜索工具默认不加载；用户在 Agent 编辑页的工具列表中逐项勾选，选择保存在 `Agent#tools` 的 `gbrain__*` 或 `search__web_search` 名称中。未选择时不得请求对应工具的定义，也不得执行其工具。
- GBrain 和网页搜索工具必须同时满足 Agent 选择和 `config/mcp_servers.yml` 的服务端白名单；网页搜索还需配置 Tavily API Key。可选工具由 `ErpAI::ToolRegistry.optional_mcp_tools` 提供，不应加入内置 Agent 的默认工具集合。

## Activepieces 工作流使用技巧

### 工具与编辑方式

- 当前通过 `mcp__eshop_flow__ap_*` 工具管理工作流，控制台地址为 `https://flow.eshop.evexport.cn`。先用 `ap_list_flows` 查找目标，再用 `ap_flow_structure` 获取真实步骤名、父子关系和分支位置；不要猜测 `step_N` 编号。
- 配置组件前先用 `ap_research_pieces` 查动作或触发器，再用 `ap_get_piece_props` 读取字段结构。动态下拉选项通过 `ap_resolve_property_options` / `ap_resolve_property_chain` 获取，使用返回的 `value`，不要使用显示标签。
- 新流程可用 `ap_build_flow` 一次创建触发器与顺序步骤；该工具不能完整配置 Router，条件分支需随后通过 `ap_add_step`、`ap_add_branch`、`ap_update_branch` 逐步添加。已有流程使用 `ap_update_step` / `ap_update_trigger` 修改，避免删除重建而丢失样本数据。
- 修改前用 `ap_read_step_settings` 读取完整配置；CODE 源码可用 `ap_read_step_code`。`ap_flow_structure` 的配置文本可能被截断，不适合作为完整备份。
- 工作流优先使用内置 HTTP、Data Mapper、Router、Loop 组件；简单转换使用支持的公式，复杂业务判断再拆成职责单一的小 CODE 模块。CODE 必须导出 `code` 函数，参数从 `inputs` 获取。
- 参数、数据提取、业务规则和最终输出分开：SKU、地址与阈值放独立参数节点；每个 API 后放独立 Data Mapper；Grade/Stage 使用可见的 Router 分支；最终输出保留指标、诊断标签及来源/计算证据。使用画布 notes 标明修改入口和关键限制。

### 变量、引用与 ERP API

- 步骤输出引用格式为 `{{step_1['output'].field}}`，HTTP JSON 通常为 `{{step_1['output'].body.data.field}}`；触发器同样使用 `{{trigger['output'].field}}`，不要写 `{{trigger.field}}`。开启失败后继续执行的步骤，其错误使用 `{{step_1['error'].message}}`。
- ERP 地址为 `https://eshop.evexport.cn`，Bearer token 已保存在 Activepieces 项目变量 `YUANLONG_TOKEN`。HTTP 节点使用 `authType: "BEARER_TOKEN"` 和 `authFields: { token: "{{variables['YUANLONG_TOKEN']}}" }`，不要把密钥写入代码、日志或本地快照。
- 项目变量与应用 Connections 是两种不同配置；`ap_list_connections` 返回空列表不代表项目变量不存在。使用应用连接时，通过该工具获取 `externalId`，传给步骤的 `auth` 参数。
- SKU 上下文优先读取 `ErpAI::V3::SkusController` 的分段 JSON API：`/ai/v3/sku/{base,inventory,lifecycle,profit,sales_funnel,warehouse_recommendation}_context.json`，查询参数为 `sku_code`。字段提取以实际返回值为准，并核对仓库中 Controller/Context 的实现。
- V3 数据位于 `body.data`，时间锚点为 `data.period.as_of`，时区为 `data.period.time_zone`；不同 API 的 SKU、日期与时区应一致。周数据为带 `period_key` 和 `values` 的数组，按 P0/P-1 等键查找，不能假定数组顺序。默认利润 P0 为上个完整自然周，漏斗 P0 为本周，须保留各自周期。
- 现成指标优先直接引用；空值、板块缺失和明确不在 `available_metrics` 中的字段不得补为0。本周末库存为空时不能据此判定断货；采用其他有效来源时保留来源说明。

### 测试、发布与源码维护

- 先做 `ap_validate_flow`，再做完整 `ap_test_flow`，最后通过 `ap_get_run` 检查关键步骤的实际输出和错误。测试可能执行真实 API、写入或消息动作，应按当前任务授权范围选择测试内容。
- 单步 `ap_test_step` 的成功状态不能代替完整验收；本次发现它的前置步骤可能显示成功但输出为空。验收需确认最终关键字段非空、分支正确、数值有依据。传入 `triggerTestData` 的测试应明确标为样本测试，不能宣称已验证真实触发器。
- 当前 MCP `ap_validate_flow` 会把 `{{variables[...]}}` 中的 `variables` 当成步骤名并报引用错误。本次 `YUANLONG_TOKEN` 的六个 GET 请求在完整测试中均鉴权成功；遇到相同报错时核查实际运行，保留正确变量引用，不要为消除报错而硬编码密钥，也不要忽略其他校验错误。
- 草稿可在编辑器用 Test Flow 测试；正式 Run Flow 或自动触发需发布启用。`ap_lock_and_publish` 会同时发布并启用，`ap_change_flow_status` 可停用；按用户要求决定是否发布，单 SKU 验证可先保留草稿。
- 当前模块化参考位于 `script/activepieces/sku_inventory_health/`，详见其 `README.md`。本地 `.mjs` 不会自动同步到 Activepieces；修改后用 `ap_update_step` 更新对应 `sourceCode`，运行相关规则回归与完整流程测试，再更新配置快照和样本结果。
- 该目录的 `flow-definition.json` 是节点设置与父子关系快照，不是 Activepieces UI 原生导入包。快照仅保留变量引用；本地规则回归命令为 `node --test script/activepieces/sku_inventory_health/health.test.mjs`。

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

## Ozon 打托盘工作台

### 入口与职责

- 工作台入口为 `GET /reports/pallet_workbench`，计算预览为 `POST /reports/pallet_workbench/preview`，批量选品为 `POST /reports/pallet_workbench/auto_select`；计划列表、详情和编辑位于 `/reports/pallet_plans`。Controller 分别为 `Reports::PalletWorkbenchesController`、`Reports::PalletPlansController`，保留 HTML / `.json` 两种响应。
- 当前链路：`Ec::PalletPlans::WorkbenchQuery` 组装需求与库存，`Build` 校验店铺、集群、日期、SKU 权限、Listing、包装及库存并调用 `Packing`，`Save` 保存计划、清单、托盘和托盘明细；状态变更由 `Workflow` 负责。
- 页面位于 `app/views/reports/pallet_workbenches/`，交互为 `app/javascript/controllers/pallet_workbench_controller.js`。包装几何、平台限制和费用继续复用 `PalletPacking::Calculator`、`Rules`、`Fees`，不要在页面或 Stimulus 中另写排托算法。
- 工作台 GET、自动选品和计算预览不创建计划、不占库存、不触发平台 API。保存草稿后，由用户在计划详情明确确认库存占用。Ozon 供货绑定、状态回读使用 `OzonReconciler` 与 `Ec::PalletPlanSyncJob`；定时回读在 `config/recurring.yml` 中每 15 分钟运行，不要并入页面 GET。
- 计划详情的供货关联从送仓记录页 `/reports/supply_orders?store_ref=ozon:<账号ID>` 同源查询中搜索选择。`SupplyOrderReports::ReportQuery#ozon_order_options` 限定账号、集群和相关平台 SKU，排除其他有效计划已绑定的父供货；`#ozon_reconciliation_rows` 按账号和父供货 ID 读取完整明细，不应用页面分页或 SKU/状态筛选，防止隐藏额外商品。提交继续校验整单数量、目的仓及集群，不以搜索结果替代校验。

### 单托、多托与数量规则

- 新方案默认 `packing_mode: single`，每托最多 5 个 SKU；同时保留 `multiple` 多托计划。使用 `ozon_fbo` 规则，自有/FBS 侧出库不代表采用 `ozon_fbs` 收货限制。
- 需求限定当前店铺与目标集群；包装完整且 Listing 唯一时，建议箱数为 `min(ceil(剩余缺口 / 每箱件数), floor(max(可分配库存, 0) / 每箱件数))`，即整箱向上补足缺口、库存上限向下取整。同一店铺 SKU 对应多个 Listing 时不能自动选取供货商品。
- “一键推荐一托”使用**全部筛选结果**，不受当前页或表格排序影响：筛选包装完整且建议箱数大于 0 的 SKU，按缺口降序、日均销量降序、SKU 编码升序取前 5 个候选，再请求 `recommend_one: true`。这是启发式推荐，候选可能无法全部装入，不保证全局最优装载率。
- “清单适配一托”使用当前清单的选品与箱数上限请求单托推荐；两种推荐均可减少箱数或移除本托未装入的 SKU，应用前保留一次撤销。不要把它们改成未经提示的整份多托补货。
- `Packing#retain_packed_items!` 必须同步裁减结果清单、更新实际箱数并重排 zone 的 `item_index`；`Build` 同步裁减待保存明细并保留 `sku_product_id`，确保清单、几何结果、箱数和件数一致，不能只隐藏剩余托盘。
- 普通改量只验算当前输入，不自动减量；单托超容量报 `single_pallet_capacity`，超过 5 个 SKU 报 `single_pallet_limit`，不能静默拆托。多托手工分配必须逐托验算，所有托盘按 SKU 汇总的箱数必须与清单相等；总托数沿用计算器上限。
- 外箱尺寸为 cm、外箱重量为 kg，箱数与每箱件数必须为正整数。单品体积可缺省，SKU 尺寸推导出的非正单品体积按缺失处理，不要传 0 给计算器代替缺失值。
- Ozon FBO 尺寸类别按带最终销售包装的单件商品计算，使用 `Ec::SkuDimension` 的 `inner_*_cm` 和 `inner_box_weight_kg`，统一调用 `calculated_ozon_size_category`；缺失时标为待补齐，不得回退到整箱数据。外箱尺寸、整箱重量和每箱件数仅用于装托几何、货重和数量计算；计划构建从服务端 SKU 数据取得类别，装托服务沿用该类别，不按外箱重新分类。

### 库存、权限与编辑上下文

- 可分配量统一从 `Availability` / `BaseStockQuery` 读取，计划额外占用按 `max(units - platform_covered_units, 0)` 计算，占用状态来自 `Ec::PalletPlan::COMMITTED_STATUSES`。当前实现会把 `store_id` 下传到基础库存与占用查询；修改库存归属口径时同时核对这两个服务及工作台缺口计算，不在前端另算一套库存。
- `Build` 在保存前重新检查实际可分配库存与几何约束；前端显示的建议、库存上限和已通过验算不能替代服务端校验。包装与 SKU 关联使用批量预加载，不能逐行查询尺寸。
- SKU 可见范围统一使用 `WeeklyProfitReports::AccessScope`，基于 SKU 级开发/运营负责人归属。计划只要包含不可见 SKU，就不能通过计划 ID 查看或编辑整单；工作台批量选品和计划写入继续检查 `manage_skus` 权限。
- 编辑时预览及批量选品必须携带 `plan_id`，先检查整单 SKU 可见范围与 `editable?`，再向 `Build` / `WorkbenchQuery` 传入当前计划上下文，以排除自身占用。不得只接受一个未经权限校验的 `excluding_plan_id`。
- 现有计划编辑不能改变店铺或集群。可编辑状态为 `draft/reserved/packing/packed`，且尚未绑定 `ozon_order_id`；其余状态沿用模型和工作流约束。

### 页面交互与回归

- 需求表与当前清单并排，窄屏优先显示清单；表格每页 15 条，默认只显示决策所需字段，销量/库存明细、人员/SKU 筛选、包装与收货参数按需展开。继续复用通用筛选、排序及表格视口组件，文案补齐 `pallet_workbench` 的 zh/en/ru。
- 修改清单或参数后先使旧结果失效，等待 650ms 自动验算；请求期间禁止重复提交，使用递增 `revision` 丢弃旧请求结果。仅最新方案验算通过后启用保存，单托高度使用含托高度，重量容量使用货重，二者分别对应 FBO 规则限制。
- `sessionStorage` 按计划（或 `new`）、店铺、集群隔离，保存清单、模式、分配、参数及 `lockVersion`；跨页/刷新恢复后仍重新验算。服务器版本与本地版本不同时丢弃旧本地清单，保存成功后清理本标签页草稿。该机制不是跨设备的服务器草稿。
- 显示库存明细时，须同时更新原表与通用浮动表头的 `table.pallet-workbench__stock-table`；浮动表头由 `sticky_table_header_controller.js` 克隆到 `document.body`，不能仅靠工作台祖先 CSS 控制隐藏列。
- 关键回归包括：单托超量拒绝而非拆托、推荐裁减与索引/保存数量一致、多托数量守恒、库存上限、编辑排除自身占用、权限、三种 locale、跨页与刷新恢复、撤销及异步旧结果失效。
- 相关 Rails 测试为 `test/services/ec/pallet_plans/`、`test/controllers/reports/pallet_workbenches_controller_test.rb`、`test/controllers/reports/pallet_calculators_controller_test.rb`。先初始化 rbenv，再运行 `bin/rails test` 加上述路径；Stimulus 使用 `node --check app/javascript/controllers/pallet_workbench_controller.js` 检查语法。沿用默认无需启动浏览器或前端构建的约定，用户明确要求交互验收时再操作浏览器。
- 详细实现说明与本地只读测量见 `docs/ozon_pallet_workbench_implementation_plan.md`，样本装托结果及单次耗时不作为固定业务规则或性能承诺。

## SKU Diagnosis -> Plan -> Action -> Evaluation 闭环

SKU 经营闭环以 `Asia/Shanghai` 的自然周为边界，周一至周日是一个计划周期。日期计算、事件归属、动作匹配和评估观察窗口必须使用同一时区；不要用服务器本地时区或 `plan_date` 代替执行周期。

### Diagnosis

- 诊断入口是 `ErpAI::SkuDiagnosisRunner`（任务：`AITasks::SkuDiagnosisJob`）。它按启用且适用于当前 SKU 的 `Ec::SkuDiagnosisRule` 运行，并通过 `save_sku_event` 保存每条规则的最新诊断事件。
- 诊断事件的 `severity` 只能使用 `info`、`warning`、`critical`。`info` 事件是信息记录，不得作为 Planner 的计划依据；Planner 只读取当前 SKU 最新的非 `info` 通用诊断事件。
- 建议动作事件使用 `scope: advise`，属于诊断输出，不要把它当作已执行的运营动作，也不要让 Planner 通过旧建议事件推断动作已完成。
- 事件必须绑定当前 SKU、规则 `sub_agent_id` 和生成会话；保存或更新事件时保持“同一 SKU、同一规则的最新事件”语义。
- 新诊断的 `simple_context` 必须包含非空的最小证据；数据不足时记录缺失事实和判断限制。字段校验失败须明确返回字段错误，诊断未成功保存时必须返回失败并触发诊断任务重试，不得仅记录日志后进入 Planner。
- 旧事件的 `simple_context` 可为空，Planner 和 Evaluation 通过 `Ec::AIDiagnosisEvent#effective_simple_context` 使用原有 `message/details` 作为证据，不回写或补造历史数据。完整性检查、Planner 输入与 Plan 引用校验统一复用 `.for_planning(sku_ids:, as_of_date:)`，按上海时区本周期的子规则 latest 事件查询，不依赖父诊断的 `is_latest`；旧 `sub_agent_id=nil` 联合诊断保留历史展示，不作为新计划依据。

### Plan

- 计划入口是 `ErpAI::SkuPlannerRunner`，计划通过 `save_sku_plan` 创建到 `Ec::SkuOperationPlan`。
- `SkuPlannerRunner` 在构建历史 Context 前自动评估已过执行截止日、尚未完成完整观察窗口评估的历史计划，页面人工 Planner 与直接调用均适用。没有待评估历史时跳过；存在待评估历史时先检查数据就绪，评估失败或数据未就绪不得生成新 revision。人工 Planner Job 对这两类失败有限重试；周度流水线已完成的评估通过同一幂等查询跳过，不重复调用 Evaluation Agent。
- Plan 的 `referer` 必须引用当前 SKU 最新的非 `info` Diagnosis event ID；不得引用其他 SKU、旧版本或没有诊断依据的事件。`scope` 只能是 `SKU` 或 `LISTING`，`LISTING` 的 `scope_id` 必须属于当前 SKU。
- 计划周期使用 `planning_period_start`、`planning_period_end` 和 `execution_deadline`：周期从周一开始，到周日结束，新计划默认执行截止日为周日后 1 天（周一结束），供周二凌晨评估。历史或明确指定的截止日保持原值，尚未结束的计划延后评估。`plan_date` 仅表示生成日期，`retain_until` 只用于兼容动作匹配的保留时间。
- Plan 的状态分开表达不同含义：
  - `lifecycle_status`: `active`、`cancelled`、`expired`；
  - `execution_status`: `not_started`、`partial`、`executed`、`not_applicable`；
  - `evaluation_status`: `pending`、`insufficient_data`、`evaluated`、`failed`。
  旧 `status=done/ignored` 只作为兼容字段同步到执行或生命周期状态，不要用一个状态字段推断整个计划生命周期。
- `is_latest` 只是当前页面展示指针，不能用来决定历史计划是否仍能接收动作、是否需要评估或是否已经结束。
- Planner 的历史 Context 默认读取最近 4 个已结束周期，最多保留 24 条计划；最近 12 个周期中效果为 `negative`/`inconclusive`、未执行/部分执行、没有动作或重复方向的异常计划需要额外保留。历史结果用于调整判断，不得机械复制上一周期计划。

### Planning Cycle 与流水线

- `Ec::SkuPlanningCycle` 表示一个 SKU 在一个自然周的计划集合，状态为 `pending -> generating -> active -> closed -> evaluated`，失败时为 `failed`。同一 SKU、同一周期通过 `revision` 和 `is_current` 管理重跑历史。
- 任务重试或从某个阶段恢复时复用当前周期 revision；只有明确的人工 Planner 重跑才创建新 revision。不要删除旧 revision 或覆盖其 Plan / Evaluation 历史。
- 周度编排任务是 `AITasks::SkuPlanningPipelineJob`，唯一自动闭环入口在 `config/recurring.yml` 的每周二 03:30（Asia/Shanghai）：
  1. `Ec::SkuPlanningDataReadiness` 仅核对相关启用店铺的上一完整自然周利润报表可查询性；不再单独检查源同步任务、广告同步、结算发布或周一 18:00 时间门槛。汇率等报表必需依赖由报表查询自身校验，零活动空报表可正常通过；查询失败每 30 分钟重试，共 5 次；
  2. 使用 `sku_plan_evaluation` Agent 评估上一完整自然周及更早尚待完成观察窗口的 Plan；
  3. 运行当前周期当天适用的 daily 和 weekly Diagnosis；
  4. 确认每个适用且启用的诊断规则都已生成当前最新事件；
  5. 运行当前周期 Planner。
  阶段失败应按现有有限重试机制恢复，不得在 Planner 诊断未完成时生成计划。

### Action

- 运营动作通过 `Ec::OperationAction` 的 `plan_id` 归属 Plan。创建或记录 Listing、广告、价格、补货等动作时，统一调用 `Ec::OperationActionPlanMatcher` 自动匹配。
- 匹配条件包括 SKU、目标/操作类型、`SKU` 或 `LISTING` 范围、动作发生时间、计划创建时间、`lifecycle_status=active`，以及 `planning_period_start <= action_date <= execution_deadline`。历史周期 Plan 在截止日（含宽限期）内仍可匹配；不要只查询 `latest`、`retained` 或当前周期计划。
- 匹配成功后将 `operation_actions.plan_id` 写回，并把计划执行状态更新为 `executed`；取消的 Plan 不得继续接收动作。

### Evaluation

- 评估入口是 `Ec::SkuOperationPlanEvaluationRunner`，异步任务为 `AITasks::SkuOperationPlanEvaluationJob`。自动评估上一自然周及更早未完成完整窗口评估、且 `execution_deadline < as_of_date` 的计划，不通过 `is_latest` 选择；单个计划可传 `plan_id` 重评，`sku_code` 可限定批次。成功的完整窗口评估不会重复调用 AI，人工 Job 使用 `force: true`。
- 评估观察窗口覆盖计划周期起点至 `execution_deadline`，动作证据来自该窗口内已绑定的 `OperationAction`；指标查询默认从计划周期前 4 周开始，直到观察结束日。
- 人工提前评估只观察到上海时区的上一完整日，动作和指标采用同一截止日；尚无完整观察日时页面不入队。提前评估不会阻止截止日后自动补齐完整窗口。宽限期包含日库存、漏斗及整个观察范围的利润查询；WB 利润以已发布结算报表为准，当前未结算周的利润仍属暂定数据，不能解释为完整日利润。
- 评估先记录执行证据和确定性指标，再按配置使用 Evaluation Agent；没有可用 AI 结果时可复用已有运营动作效果诊断或确定性指标结果。效果值只能是 `positive`、`negative`、`mixed`、`inconclusive`，置信度只能是 `high`、`medium`、`low`。
- 没有动作时执行状态为 `not_started`（取消计划为 `not_applicable`），效果必须为 `inconclusive`，不得把未执行误判为 `negative`。指标不可用或证据不足时，Plan 使用 `evaluation_status=insufficient_data`。
- `Ec::SkuOperationPlanEvaluation` 按 `plan_id + observation_to` 幂等写入，保留原始 `metrics`、动作证据、`action_ids`、会话 ID、评估版本和 `evaluated_at`。评估过程状态使用 `pending`、`running`、`succeeded`、`failed`；失败允许重试并保留失败记录。

### 页面与入口

- SKU 工作台和详情页的 AI 诊断/Planner 区域位于 `/reports/skus`、`/reports/skus/:sku_code`；计划详情位于 `/reports/skus/:sku_code/plans/:plan_id`。
- 计划详情页的“重新评估”入口为 `POST /reports/skus/:sku_code/plans/:plan_id/evaluate`，操作使用异步 Evaluation Job；计划详情同时展示评估历史和同周期 revision 历史。
- 所有新增页面、按钮、状态和错误文案必须通过 Rails I18n 管理；Controller、ERB、helper 和 Stimulus 中不要新增硬编码展示文本。

### 本地闭环调试

线上数据导入本地后，调试只连接本地 `development` 数据库；不要从本地配置读取生产写入凭据，也不要在调试过程中触发生产 Job、平台同步或真实运营动作。默认先做只读审计，再对一个 SKU 做分阶段回归。需要写库的步骤只允许在本地执行，并为本地数据库保留可恢复的备份或快照。

调试前先确认日期和依赖：

```sh
eval "$(/opt/homebrew/bin/rbenv init - zsh)"
RAILS_ENV=development bin/rails db:version
RAILS_ENV=development bin/rails runner 'puts Time.current.in_time_zone("Asia/Shanghai").to_date'
RAILS_ENV=development bin/rails console
```

在 console 中检查 Agent、诊断规则和数据覆盖。`sku_code` 应替换为已导入且有完整 Listing 的本地 SKU：

```ruby
sku = Ec::Sku.includes(:current_marketing_state, :sku_products).find_by!(sku_code: "SKU_CODE")
sku.current_marketing_state&.slice(:grade, :stage)
sku.sku_products.pluck(:id, :platform, :store_id, :product_id)
Agent.where(code: %w[sku_diagnosis sku_planner sku_plan_evaluation]).pluck(:code, :enabled)
rule_check_date = Time.current.in_time_zone("Asia/Shanghai").to_date
Ec::SkuDiagnosisRule.enabled_for(rule_check_date).pluck(:id, :name, :context_keys)
```

规则调度按上海时区日期执行：`daily` 每天可用，`weekly` 只在周二进入 `enabled_for`。因此在周五检查得到 0 条 weekly 规则是预期结果；读取已导入的历史周度事件时使用对应周二的 `as_of_date`，而在今天重新生成诊断时使用当前日期并显式传入 weekly `rule_ids`。

用只读查询建立基线，先看该 SKU 的诊断、计划、动作、评估和周期历史，再决定是否重跑：

```ruby
date = Time.current.in_time_zone("Asia/Shanghai").to_date
events = Ec::AIDiagnosisEvent.for_planning(sku_ids: sku.id, as_of_date: date).includes(:ai_diagnosis, :sub_agent)
events.map { |e| [e.id, e.sub_agent_id, e.severity, e.scope, e.effective_simple_context] }
sku.sku_operation_plans.order(planning_period_start: :desc, id: :desc).limit(20)
  .pluck(:id, :planning_cycle_id, :planning_period_start, :execution_deadline, :target, :operation,
    :scope, :scope_id, :referer, :fingerprint, :lifecycle_status, :execution_status, :evaluation_status)
sku.operation_actions.order(operated_at: :desc).limit(20)
  .pluck(:id, :operated_at, :operation_type, :plan_id, :record_by_system)
Ec::SkuPlanningCycle.where(sku: sku).order(period_start: :desc, revision: :desc).limit(12)
  .pluck(:id, :period_start, :revision, :status, :is_current, :error_message)
```

推荐按一个 SKU 串行验收四个阶段。每一步完成后检查数据库结果，再进入下一步：

1. Diagnosis：先选定 `as_of_date` 和 `rule_ids`，只跑一个 SKU。运行后确认每个适用规则都有当前周 active、非 `info`、非 `advise` 的 latest 事件，且新事件的 `simple_context` 非空。

   ```ruby
   as_of = Time.current.in_time_zone("Asia/Shanghai").to_date
   rule_ids = Ec::SkuDiagnosisRule.where(enabled: true, frequency: "weekly").pluck(:id)
   ErpAI::SkuDiagnosisRunner.run(as_of_date: as_of, sku_code: sku.sku_code, rule_ids: rule_ids)
   events = Ec::AIDiagnosisEvent.for_planning(sku_ids: sku.id, as_of_date: as_of)
   events.pluck(:sub_agent_id, :severity, :scope).inspect
   ```

   首次调试建议注入 stubbed AI client，或只运行已有事件的后续阶段；不要为了验证控制流反复调用真实模型。重新生成的事件使用实际执行时间写入 `created_at`，所以不要用过去的 `as_of_date` 直接生成后再期待 Planner 读取它；历史周回放应读取已导入事件，或在隔离副本中使用受控时钟。

2. Plan：确认 Planner 输入只来自 `Ec::AIDiagnosisEvent.for_planning(...)`，Plan 的 `referer` 指向当前 SKU 当前周期最新非 `info` 事件，`scope`、`scope_id` 与 target 合法，且同一动作的 fingerprint 重跑不产生重复计划。

   ```ruby
   ErpAI::SkuPlannerRunner.run(sku_code: sku.sku_code, as_of_date: as_of, rerun: false)
   cycle = Ec::SkuPlanningCycle.current_for(sku: sku, period_start: Ec::SkuOperationPlan.period_for(as_of))
   cycle&.operation_plans&.pluck(:id, :referer, :target, :operation, :scope, :scope_id, :fingerprint)
   ```

   Planner 会先处理已过执行截止日但尚未完成观察窗口的历史计划；因此历史数据调试时，先检查 `Ec::SkuPlanningDataReadiness.check!(as_of_date: as_of, sku_code: sku.sku_code)`，再解释 Planner 是否生成新 revision。数据未就绪或历史评估失败时，不应把“没有新计划”当成 Planner 逻辑失败。

3. Action：通过现有 recorder 记录本地动作，让 `Ec::OperationActionPlanMatcher` 自动匹配；不要直接手写 `plan_id` 来伪造成功。检查动作日期、目标、操作方向、scope 和 Listing 归属，确认匹配后 Plan 的 `execution_status` 更新为 `executed`。晚到动作应使覆盖该动作观察窗口的成功评估重新进入 pending。

4. Evaluation：优先指定一个 `plan_id`，使用与计划一致的观察截止日运行；检查评估记录的 `metrics`、`evidence`、`action_ids`、`observation_from/to`、`evaluator_version` 和 `evaluation_status`。

   ```ruby
   Ec::SkuOperationPlanEvaluationRunner.run(
     plan_id: plan.id, as_of_date: as_of, force: true,
     agent: Agent.ensure_fixed!("sku_plan_evaluation")
   )
   plan.reload
   plan.evaluations.order(observation_to: :desc, id: :desc)
     .pluck(:id, :status, :execution_status, :effectiveness, :confidence,
       :observation_from, :observation_to, :metrics, :action_ids, :evaluator_version)
   ```

   没有动作时执行状态必须是 `not_started`，效果必须是 `inconclusive`；数据不足时计划应为 `insufficient_data`。不要把“没有动作”或“指标缺失”解释成负面效果。

调试 Job 时使用 `perform_now` 串行执行并保留参数，避免直接启动整批队列：

```ruby
AITasks::SkuDiagnosisJob.perform_now(as_of_date: as_of, sku_code: sku.sku_code, pipeline: false)
AITasks::SkuPlannerJob.perform_now(as_of_date: as_of, sku_code: sku.sku_code, pipeline: false)
AITasks::SkuOperationPlanEvaluationJob.perform_now(plan_id: plan.id, as_of_date: as_of, force: true)
```

完整链路回放才使用 `AITasks::SkuPlanningPipelineJob.perform_now(as_of_date: as_of, sku_code: sku.sku_code)`；它会按 Evaluation → Diagnosis → Planner 顺序运行，并受 data-readiness gate 及有限重试约束。Pipeline 的 batch 入口不要在本地首次调试时直接执行，以免一次性改写全部导入数据。

S/A/B/C 不需要四套架构。应从每个 grade 选取若干有 Listing、诊断和历史计划的 SKU，在同一 `as_of_date`、同一规则集和同一数据窗口下运行同一条 pipeline，然后按 grade 汇总比较：Diagnosis 完整率、Plan referer/scope 合法率、同 fingerprint 重试产生的重复计划数、Action 自动绑定率、Evaluation `metrics` 非空率、无动作是否为 `inconclusive`、`insufficient_data` 比例，以及 planning cycle 是否卡在 `failed`/`generating`。可先生成只读审计表：

```ruby
skus = Ec::Sku.joins(:current_marketing_state).where(ec_sku_marketing_states: { grade: %w[S A B C] })
skus.group_by { |item| item.current_marketing_state.grade }.transform_values { |items| items.first(5).map(&:sku_code) }
```

线上导入数据可能包含历史重复计划、逾期 active/pending 计划或过去生成的空 `metrics`。不要直接批量删除、补 `plan_id` 或重写历史评估；先保存只读审计结果，再针对明确的计划 ID 运行幂等评估或单独补偿任务。关键断点位于 `ErpAI::SkuDiagnosisRunner`、`ErpAI::SkuPlannerRunner`、`Ec::SkuPlanningDataReadiness`、`Ec::OperationActionPlanMatcher`、`Ec::SkuOperationPlanEvaluationRunner` 和 `AITasks::SkuPlanningPipelineJob`。

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

## Ozon 上架手动操作

- Ozon 上架手动操作页面仍由 SKU 详情页承载，但当前不在详情页页签导航中展示；需要人工操作时通过 `tab=ozon_listing` 直接进入。页面只负责选择可见的 Ozon 店铺、生成本地草稿、查看校验结果、确认草稿、提交异步导入，以及在导入回读完成后提交价格和库存。
- 草稿由 `Ec::OzonListingDraftBuilder` 生成，校验由 `Ec::OzonListingValidator` 执行，发布过程由 `Ec::OzonListingPublication` 记录。页面请求不得直接调用 Ozon API，也不得在 Controller、ERB 或 Stimulus 中保存平台凭证。
- 所有外部写操作必须通过 `RawOzon::ListingClient` 和后台 Job 完成。只有 `confirmed` 状态的发布记录才能入队；导入任务完成并通过 `/v3/product/info/list` 回读后，才允许创建或更新 `Ec::SkuProduct`。
- Ozon 绑定字段保持固定口径：`Ec::SkuProduct.product_id` 保存 Ozon product id，`platform_sku_id` 保存 Ozon SKU，`offer_id` 保存卖家 offer id。图片必须是公开 HTTPS URL；价格和库存只能在导入回读成功后写入。
- 页面状态至少覆盖 `draft`、`confirmed`、`queued`、`pending`、`failed`、`ready_for_price_stock` 和 `completed`，并展示任务 ID、结构化校验错误、平台错误和回读后的商品 ID。
- 不注册 Ozon 上架 MCP tool。Agent 只读取本节和 `docs/platform_apis/ozon/18-商品上架自动化接口矩阵.md` 中的约束；上架动作必须由 SKU 详情页的人工确认触发。

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
