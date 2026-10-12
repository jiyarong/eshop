# 现有流程样板

这些流程是设计和排错参考，不是未经核对即可复制的模板。开始修改前仍需读取 Activepieces 当前画布。

## SKU 库存诊断与健康度

| 项目 | 当前信息 |
| --- | --- |
| Flow ID | `Qh7au61yzigFaAdkxK8SX` |
| 项目 | `D39taW24AEQ4mNoeEO8IE` |
| 入口 | Manual Trigger，固定 SKU `JJ005-6` |
| 状态 | 草稿、未发布、停用 |
| 副作用 | 六个 ERP GET 和分析输出；不写诊断事件、不触发同步、采购或消息 |
| 结构 | HTTP → Data Mapper → 统一校验 → Grade/Stage Router → 小型 CODE → 报告 |
| 本地规则测试 | `node --test script/activepieces/sku_inventory_health/health.test.mjs` |
| 主要输出 | `metrics`、`markdown`、`alerts`、`evidence` |

关键本地文件：

- [`README.md`](../../../script/activepieces/sku_inventory_health/README.md)：节点职责、业务规则、调整入口和验收记录。
- [`flow-definition.json`](../../../script/activepieces/sku_inventory_health/flow-definition.json)：实际节点设置和父子关系快照。
- [`health.test.mjs`](../../../script/activepieces/sku_inventory_health/health.test.mjs)：缺失值、日期/SKU 校验、库存校准、补货、渠道和清仓规则。

## Ozon Listing 文本诊断

| 项目 | 当前信息 |
| --- | --- |
| Flow ID | `yugdpW8OQC0LJiRJDAAvr` |
| 项目 | `D39taW24AEQ4mNoeEO8IE` |
| 入口 | Manual Trigger，SKU `JJ005-6`，Ozon Listing `sku_product_id=253` |
| 状态 | 草稿、未发布、停用 |
| 副作用 | V3 和只读 SQL 查询；不修改 Listing，不调用 Ozon 写接口 |
| 结构 | 28 个活动节点，包含两个原生结构化 AI 节点和多个小型 CODE 模块 |
| 本地规则测试 | `node --test script/activepieces/ozon_listing_diagnosis/diagnosis.test.mjs` |
| 主要输出 | `metrics`、`listings`、`markdown` |

关键本地文件：

- [`README.md`](../../../script/activepieces/ozon_listing_diagnosis/README.md)：数据来源、AI Provider、属性/文本门禁和已知限制。
- [`flow-definition.json`](../../../script/activepieces/ozon_listing_diagnosis/flow-definition.json)：活动节点、停用节点和设置快照。
- [`attributes.schema.json`](../../../script/activepieces/ozon_listing_diagnosis/attributes.schema.json) 与 [`text.schema.json`](../../../script/activepieces/ozon_listing_diagnosis/text.schema.json)：结构化 AI 输出合同。
- [`diagnosis.test.mjs`](../../../script/activepieces/ozon_listing_diagnosis/diagnosis.test.mjs)：证据、字典、KEEP 策略和不完整 AI 输出测试。

## 使用样板时的限制

- 快照中的步骤名称、节点版本和 Provider 设置可能已变化，必须先读取当前画布。
- README 中的样本运行结果是某次运行的证据，不代表当前流程自动仍然通过。
- Ozon 流程曾出现原生 AI Provider 鉴权失败；修改 Provider 或 AI 节点前必须重新读取当前 Provider 配置并执行端到端测试。
- Rails 旧测试中存在历史字段或旧标题断言；不要把这些失败直接归因于 Activepieces 流程，先区分 Rails 回归和流程回归。

