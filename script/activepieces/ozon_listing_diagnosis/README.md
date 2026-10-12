# 单 SKU Ozon Listing 文本诊断

[打开 Activepieces 工作流](https://flow.eshop.evexport.cn/projects/D39taW24AEQ4mNoeEO8IE/flows/yugdpW8OQC0LJiRJDAAvr)

固定 SKU 为 `JJ005-6`，Ozon Listing 为 NEVASTAL / `sku_product_id=253`。使用 Manual Trigger，保留为未发布、停用的草稿。在编辑器点击 **Test Flow**，结束后查看 `step_30` 的 `metrics`、`listings`、`markdown`。

ERP 地址为 `https://eshop.evexport.cn`。SKU 经营上下文来自 `ErpAI::V3::SkusController`。当前 V3 没有 Listing 文本和官方属性目录接口，额外通过已有 `/ai/sql_queries.json` 读取这两类数据及搜索词明细。查询限定当前 SKU、Ozon、active Listing，并分别返回绑定 ID、店铺和商品 ID。SQL 接口使用只读事务；流程不保存诊断事件，不修改 Listing，不调用 Ozon 写接口。

ERP凭证引用已有项目变量 `{{variables['YUANLONG_TOKEN']}}`，本目录不保存密钥。LLM通过 **AI → Extract Structured Data** 调用平台级 Custom / OpenAI Compatible Provider，模型为 `gpt-6-sol`。两个AI节点分别诊断属性与文本；文本节点的 Files 字段附当前 Listing 主图，仅作事实一致性核查。AI直接返回结构化对象，不再通过HTTP节点调用模型或解析Chat Completions响应。

Provider在 **Settings → AI Providers** 配置：Base URL为 `https://sub.foresight-soft.com/v1`，API Style使用Chat Completions；Header Name为 `Authorization`，API Key字段填 `Bearer ` 加现有 `SUB2_API_KEY` 的实际值。Custom Provider原样发送Header值，不自动添加Bearer，也不解析流程变量表达式。手动添加Text模型 `gpt-6-sol`。密钥仅保存在平台的Provider配置中，不放入Prompt或本地快照。

AI输出字段受两个JSON Schema约束，后续证据门禁继续检查SKU、Listing归属、字典合法性和KEEP策略。模型/鉴权/证据失败时停止，不输出伪成功。AI组件不暴露原始token用量，因此最终`llm`只标明provider、model和action。

## 节点与修改入口

当前共33个节点，其中28个参与执行：手动触发、7个ERP HTTP节点、11个Data Mapper、2个原生AI节点、7个小代码模块。最长代码模块63行。旧HTTP模型检查、两处LLM HTTP调用、两处JSON解析共5个节点已停用，仅保留之前验收的样本数据。

| 调整内容 | 节点 | 本地来源 |
| --- | --- | --- |
| SKU、ERP host、输出token上限、漏斗敏感度参数 | step_1 | flow-definition.json |
| LLM host、鉴权、可用模型 | Settings → AI Providers | 平台Provider配置 |
| V3基础状态字段 | step_2 / step_3 | HTTP / Data Mapper |
| V3店铺Listing漏斗字段 | step_4 / step_5 | HTTP / Data Mapper |
| V3搜索词周汇总 | step_6 / step_7 | HTTP / Data Mapper |
| V3库存证据 | step_8 / step_9 | HTTP / Data Mapper |
| SKU事实、标题、描述、富文本及原始属性 | step_10 / step_11 | 只读SQL / Data Mapper |
| 官方属性定义、max_count、完整字典候选池 | step_12 / step_13 | 只读SQL / Data Mapper |
| 整合六个来源 | step_14 | Data Mapper |
| 原生AI的Provider、模型、结构化输出字段 | step_31 / step_32 | attributes.schema.json / text.schema.json |
| 实际搜索词明细 | step_16 / step_17 | 只读SQL / Data Mapper |
| PostgreSQL JSON解析、字段规范化、来源完整性、搜索词去重 | step_18 | normalize.mjs |
| Grade/Stage敏感度与完整周漏斗下降 | step_19 | sensitivity.mjs |
| 原始生产V2.2规则、属性/文本输出契约 | step_20 | Data Mapper的三个Prompt字段 |
| 属性Prompt与证据输入、AI调用、字典/证据门禁 | step_21 → step_31 → step_24 | attribute_request.mjs / validate_attributes.mjs |
| 文本Prompt与主图输入、AI调用、KEEP/SEO/归因门禁 | step_25 → step_32 → step_28 | text_request.mjs / validate_text.mjs |
| P0/P1状态、属性动作表、最小操作清单、报告 | step_29 | report.mjs |
| 最终输出字段 | step_30 | Data Mapper |

`flow-definition.json` 保存实际节点设置与源码，是恢复和调整用的配置快照，不是 Activepieces UI 原生导入包。修改本地文件后，需要用 `ap_update_step` 更新对应节点，再复验流程。

## 规则与数据口径

- 单店铺、单Listing内核对事实，禁止跨店比较。每个LLM结果必须覆盖全部输入Listing且不重复。
- 数据日期/时区使用API返回的 `period.as_of/time_zone`，本样本为 `Europe/Moscow`。不同V3接口必须一致，不使用JavaScript服务器当前日期。
- 原始描述从平台description或属性4191读取；富文本从11254独立读取。未配置富文本输出 `not_configured + KEEP`，不新增制作任务。
- `max_value_count > 0`使用官方值；单值属性没有明确上限时按1；collection的0表示未提供明确上限，输出null，不能机械判为零名额。
- 字典建议必须同时匹配官方候选池的ID和原文；超过明确上限、字典外值、免检模型字段问题、缺少当前Listing证据的结果会失败。未缓存品牌/国家等字典仅标注限制，不能猜测候选值。
- 当前属性与完整类目目录一起提供，可检查未填的相关属性；Type由类目隐式确定的情况不能因属性数组未出现而机械判错。
- 漏斗以最近两个已结束自然周比较，默认至少100次商品卡浏览，CTR/加购率/访问转化率相对下降30%才提高敏感度。此阈值是试运行的可调整策略，并非Ozon官方基准；异常不等于Listing有问题。当前不完整周仅保留为暂定证据。
- B/C/CLR的及格文本默认KEEP。没有高置信度经营价值的问题不能形成改稿任务。不及格重写必须给完整俄文及中文对照。
- 搜索词按照Listing+自然周+query去重，多个排行榜重复出现不叠加人数；有不同同步时间时取最新记录，并保留source_rankings。unique_search_users不等于商品曝光，跨周用户记录也不是跨周去重人数。
- 单项数值与内部资料不同尚不能证明录入错误；先排除数值包装、测量口径和资料版本差异。合理承重包装遵循原规则放行；整架承重可小于各层上限之和。
- 任意P0强制 `status=has_error`；零P0但有P1为 `needs_optimization`；无实质问题为 `healthy`。关键证据不足时无问题不能输出healthy，使用 `status=null` 和 `audit_status=insufficient_data`。缓存字典/来源拆分等限制保留为 `audit_status=partial`。
- 所有SQL结果检查 `has_more`；截断时流程停止，必须缩小日期或接入分页，不静默诊断不完整集合。

## 验证

测试使用Manual Trigger，全部SKU数据通过真实ERP API获取。`sample-result.json`与`sample-report.md`目前仍是之前HTTP方式的成功样本，不能当作原生AI版本已通过的证据。

2026-10-10原生AI运行 `4XUMJLIRPcSDj74u55oUE`：取数、规范化、敏感度计算与属性Prompt组装全部成功，原生属性AI节点 `step_31` 返回 `Failed to extract structured data: Unauthorized`。当前Provider已经有 `gpt-6-sol` 模型，但鉴权仍失败；需修正Provider中的实际API Header值并重跑，尚未完成原生AI端到端验收。

之前HTTP版本验收运行 `FgZQO9rHgJmSOs1FaNLOx` 在Activepieces TESTING环境成功，耗时100.2秒。输出：B/GRW、`has_error`、P0=1、P1=1、属性修改项=1、三个文本模块均KEEP。P0为4层标签与6层实际规格冲突；P1为“гараж сборный”跨品类查询的来源排查。品牌/国家官方字典未缓存、词级曝光及广告来源拆分不足等限制使 `audit_status=partial`。

```sh
node --test script/activepieces/ozon_listing_diagnosis/diagnosis.test.mjs
```

12项规则测试通过，覆盖真实样本、SKU/日期/时区校验、缺失数据、搜索词去重、Grade/Stage策略、字典值与上限、免检字段、跨Listing证据、B/C KEEP、不完整原生AI输出、SEO格式及来源检查、P0状态和数据不足。

Rails相关控制器测试已运行：25项中23项通过，1项失败、1项错误。两处既有V3测试分别读取已移除的顶层`metrics`，以及断言旧Markdown标题`# SKU context`。本次未修改Rails实现和现有测试。

MCP结构校验确认28个活动节点配置有效、5个旧节点停用；仍把项目级`variables`误识别为流程步骤。真实执行已验证ERP变量能正确解析和鉴权。
