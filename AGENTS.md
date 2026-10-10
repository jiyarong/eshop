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
- Turbo 侧边抽屉外壳：`app/views/shared/_overlay_drawer.html.erb`，配合 `modal_controller.js`。传 `frame_id`、`title_id`、`title`、`body`，按需传 `subtitle`、`eyebrow`、`header_actions`、`close_path`、`drawer_width`；业务内容保留在调用方 partial，不要复制抽屉遮罩、标题栏和关闭逻辑。

## AI Agent 工具选择

- GBrain 和网页搜索工具默认不加载；用户在 Agent 编辑页的工具列表中逐项勾选，选择保存在 `Agent#tools` 的 `gbrain__*` 或 `search__web_search` 名称中。未选择时不得请求对应工具的定义，也不得执行其工具。
- GBrain 和网页搜索工具必须同时满足 Agent 选择和 `config/mcp_servers.yml` 的服务端白名单；网页搜索还需配置 Tavily API Key。可选工具由 `ErpAI::ToolRegistry.optional_mcp_tools` 提供，不应加入内置 Agent 的默认工具集合。

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
  1. `Ec::SkuPlanningDataReadiness` 核对周一 18:00 后的源同步完成、日期覆盖、精确本地周汇率和利润报表可查询性；未就绪每 30 分钟重试，共 5 次；
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
