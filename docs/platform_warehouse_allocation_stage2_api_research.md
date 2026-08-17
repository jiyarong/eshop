# 环节二平台 API 调研：WB 与 Ozon

调研日期：2026-08-03

本文只讨论“平台候选准入与落仓选择”：商品能否进入某仓、允许的包装、候选日期、接货费用及中转关系。包装优化、货位、标签属于环节三，但为说明接口边界会列出衔接接口。

## 一、结论对比

| 能力 | WB FBW | Ozon FBO |
|---|---|---|
| 查询平台仓库 | 公开 API | 公开 API |
| 按商品和数量查询候选仓 | 公开 API | 通过供货草稿计算 |
| 查询允许包装类型 | 公开 API 直接返回布尔能力 | 结合草稿、供货类型及后续货位规则 |
| 查询接货日期及系数 | 公开 API | 公开 API |
| 查询中转路线 | 公开 API | 在 Cross-dock 草稿中指定 Drop Off/Pick Up |
| 创建供货草稿 | 无公开稳定写接口 | 公开 API |
| 创建正式供货申请 | 无公开稳定写接口 | 公开 API |
| 创建箱/托盘货位及标签 | 只能读取已有供货包装；公开写入能力未确认 | 公开 API |
| 自动化程度 | 环节二可自动推荐，建单和预约仍主要依赖 Seller 后台 | 可覆盖候选准入、建单、预约和后续货位链路 |

核心差异：WB 的公开 API 主要是“查询型”；Ozon 的公开 API 是“异步草稿计算 + 正式创建”的工作流型 API。

## 二、WB FBW

### 2.1 官方文档

- [FBW Supplies](https://dev.wildberries.ru/en/docs/openapi/orders-fbw)
- [FBW Supplies Swagger](https://dev.wildberries.ru/en/swagger/orders-fbw)
- [Tariffs](https://dev.wildberries.ru/en/docs/openapi/tariffs)

基础地址：

```text
https://supplies-api.wildberries.ru
https://common-api.wildberries.ru
```

鉴权使用 WB API Token；接口要求的 token category 以各官方 operation 为准。

### 2.2 环节二可用接口

| 接口 | 作用 | 环节二用途 |
|---|---|---|
| `POST /api/v1/acceptance/options` | 按 `barcode + quantity` 查询仓库和包装准入 | 核心候选准入 |
| `GET /api/v1/warehouses` | 获取 WB 仓库目录 | 解释 `warehouseID`、地址和中转状态 |
| `GET /api/v1/transit-tariffs` | 获取中转仓到目的仓的有效路线及费用 | 生成中转候选 |
| `GET /api/tariffs/v1/acceptance/coefficients` | 查询日期、仓库、包装类型对应的接货状态和系数 | 日期及成本候选 |

### 2.3 `POST /api/v1/acceptance/options`

请求最多包含 5000 个商品行；商品标识是 WB 商品条码 `barcode`，不是内部 SKU、`vendorCode`、`nmID` 或 `chrtID`。

```json
[
  {
    "barcode": "2052183571202",
    "quantity": 50
  },
  {
    "barcode": "2052203734440",
    "quantity": 32
  }
]
```

可选 query 参数：

```text
warehouseID=507
```

不传时查询所有候选仓；一次最多指定一个仓库 ID。

关键响应结构：

```json
{
  "result": [
    {
      "barcode": "2052183571202",
      "warehouses": [
        {
          "warehouseID": 507,
          "canBox": true,
          "canMonopallet": true,
          "canSupersafe": false,
          "isBoxOnPallet": false
        }
      ],
      "isError": false
    }
  ],
  "requestId": "request-id"
}
```

失败可能是逐商品失败，不应只根据 HTTP 200 判断整批成功：

```json
{
  "barcode": "bad-barcode",
  "warehouses": null,
  "error": {
    "title": "barcode validation error",
    "detail": "barcode is not found"
  },
  "isError": true
}
```

这个接口回答的是“每个商品分别可以去哪些仓”。多 SKU 拼托前，应对候选仓取交集；形成完整波次后还应再次调用，防止数量或平台容量变化。

### 2.4 `GET /api/v1/warehouses`

关键响应结构：

```json
[
  {
    "ID": 300461,
    "name": "Гомель 2",
    "address": "...",
    "workTime": "24/7",
    "isActive": false,
    "isTransitActive": true
  }
]
```

注意：这是 WB FBW 供货仓目录，不是卖家自己的 FBS 仓库接口 `GET /api/v3/warehouses`。

### 2.5 `GET /api/v1/transit-tariffs`

关键响应结构：

```json
[
  {
    "transitWarehouseName": "Обухово",
    "destinationWarehouseName": "Краснодар",
    "activeFrom": "2025-04-08T21:00:48.019Z",
    "boxTariff": [
      { "from": 0, "to": 1500, "value": 5.3 }
    ],
    "palletTariff": 6500
  }
]
```

该接口主要以仓库名称表达路线。系统应映射到 WB 仓库目录，并保存原始名称和查询时间，不能只靠长期不变的名称字符串关联。

### 2.6 `GET /api/tariffs/v1/acceptance/coefficients`

可按仓库 ID 过滤：

```text
warehouseIDs=507,117501
```

关键响应结构：

```json
[
  {
    "date": "2026-08-10T00:00:00Z",
    "coefficient": 1,
    "warehouseID": 507,
    "warehouseName": "Коледино",
    "allowUnload": true,
    "boxTypeID": 2,
    "storageCoef": 100,
    "deliveryCoef": 100
  }
]
```

`date + warehouseID + boxTypeID` 才构成一个可比较的日期候选。不能只看仓库开放，也不能把某种包装的系数套用到另一种包装。

### 2.7 WB 公开 API 的边界

FBW Supplies 还公开以下只读接口：

```text
POST /api/v1/supplies
GET  /api/v1/supplies/{ID}
GET  /api/v1/supplies/{ID}/goods
GET  /api/v1/supplies/{ID}/package
```

它们用于读取既有供货单、商品和包装，例如包装结果：

```json
[
  {
    "packageCode": "WB_689",
    "quantity": 1,
    "barcodes": [
      { "barcode": "2052183571202", "quantity": 50 },
      { "barcode": "2052203734440", "quantity": 32 }
    ]
  }
]
```

截至本次调研，官方 FBW Swagger 没有公开创建草稿、提交商品组合、选择预约时段或写入包装结构的方法。因此：

- 环节二可以自动形成并复核 WB 候选方案；
- 正式建单和预约仍需要 Seller 后台或人工导入；
- Seller 后台内部接口不等于公开稳定 API，不应直接作为生产集成契约。

## 三、Ozon FBO

### 3.1 官方文档

- [Ozon Seller API](https://docs.ozon.ru/api/seller/)
- [2026 FBO 供货申请流程](https://dev.ozon.ru/start/453-Protsess-sozdaniia-zaiavok-na-postavku-tovarov-FBO/)
- [2026 接口版本迁移公告](https://dev.ozon.ru/news/653-Obnovlenie-metodov-sozdaniia-zaiavok-na-postavku-FBO/)
- [FBO 货位与标签流程](https://dev.ozon.ru/start/369-Metody-dlia-peredachi-gruzomest-k-zaiavkam-na-postavku-FBO-v-Seller-API)

基础地址与鉴权：

```text
POST https://api-seller.ozon.ru/{method}
Client-Id: <seller client id>
Api-Key: <seller api key>
Content-Type: application/json
```

### 3.2 2026 年必须使用的版本

以下旧接口已于 2026-03-16 停用：

```text
/v1/draft/create
/v1/draft/create/info
/v1/draft/timeslot/info
/v1/draft/supply/create
/v1/draft/supply/create/status
```

当前链路：

```text
查询集群和交货点
  -> 按供货模式创建草稿
  -> 查询异步计算结果
  -> 查询可用时段
  -> 从草稿创建供货申请
  -> 查询创建状态和 order_id
```

当前方法：

| 步骤 | 接口 |
|---|---|
| 查询集群 | `POST /v1/cluster/list` 或平台当前推荐版本 |
| 查询 Cross-dock Drop Off 点 | `POST /v1/warehouse/fbo/list` |
| 查询 Pick Up 卖家仓 | `POST /v1/warehouse/fbo/seller/list` |
| 创建直送草稿 | `POST /v1/draft/direct/create` |
| 创建 Cross-dock 草稿 | `POST /v1/draft/crossdock/create` |
| 创建多集群草稿 | `POST /v1/draft/multi-cluster/create` |
| 查询草稿状态和计算结果 | `POST /v2/draft/create/info` |
| 查询候选时段 | `POST /v2/draft/timeslot/info` |
| 创建供货申请 | `POST /v2/draft/supply/create` |
| 查询创建状态 | `POST /v2/draft/supply/create/status` |
| 查询正式供货单 | `POST /v3/supply-order/get` |

### 3.3 三种草稿结构

以下是官方流程中关键字段的结构骨架，完整 enum 和嵌套字段以 Seller API operation schema 为准。

直送：

```json
{
  "items": [
    { "sku": 123456789, "quantity": 50 }
  ],
  "macrolocal_cluster_id": 100000001
}
```

Cross-dock：

```json
{
  "items": [
    { "sku": 123456789, "quantity": 50 }
  ],
  "macrolocal_cluster_id": 100000001,
  "delivery_type": "DROP_OFF",
  "drop_off_point": {
    "warehouse_id": 200000001,
    "warehouse_type": "WAREHOUSE_TYPE_SC"
  }
}
```

如果选择 Pick Up，传卖家仓 ID，而不是 Drop Off 点。多集群模式则按每个集群分别传商品组成，平台由一个草稿产生多个 FBO 供货。

创建草稿后得到 `draft_id`，之后的接口均围绕它异步推进。草稿有有效期，不能长期缓存后复用。

### 3.4 `POST /v2/draft/create/info`

请求骨架：

```json
{
  "draft_id": 987654321
}
```

响应核心不是简单的 `true/false`，而是：

```text
草稿状态
+ 错误列表
+ 每个供货类型/集群的计算结果
+ 可接受整批商品的候选最终仓
+ storage_warehouse_id
+ macrolocal_cluster_id
+ supply_type
```

这些返回字段是查询时段和创建正式供货申请的依据。Agent 不能自己根据仓库目录猜 `storage_warehouse_id`。

### 3.5 `POST /v2/draft/timeslot/info`

直送时使用草稿计算返回的最终存储仓：

```json
{
  "draft_id": 987654321,
  "supply_type": "SUPPLY_TYPE_DIRECT",
  "storage_warehouse_id": 300000001,
  "date_from": "2026-08-05T00:00:00Z",
  "date_to": "2026-08-20T00:00:00Z"
}
```

Cross-dock 或多集群需要传对应 `supply_type` 和草稿计算返回的集群信息。响应返回候选时段，而不是永久预约。

### 3.6 `POST /v2/draft/supply/create`

关键请求骨架：

```json
{
  "draft_id": 987654321,
  "supply_type": "SUPPLY_TYPE_DIRECT",
  "warehouse_id": 300000001,
  "timeslot": {
    "from": "2026-08-10T08:00:00Z",
    "to": "2026-08-10T09:00:00Z"
  }
}
```

接口返回异步 `operation_id`。随后调用：

```json
POST /v2/draft/supply/create/status
{
  "operation_id": "operation-id"
}
```

成功后取得 `order_id`，再通过 `POST /v3/supply-order/get` 获取正式供货申请和其中的 `supply_id`。

### 3.7 与环节三衔接的 Ozon 接口

以下不属于候选准入本身，但会验证环节三优化后的箱/托方案：

```text
POST /v1/cargoes/create
POST /v1/cargoes/create/info
POST /v1/cargoes/rules/get
POST /v1/cargoes-label/create
POST /v1/cargoes-label/get
GET  /v1/cargoes-label/file/{file_guid}
```

`/v1/cargoes/create` 的逻辑结构是：

```json
{
  "supply_id": 123456789,
  "delete_current_version": false,
  "cargoes": [
    {
      "type": "CARGO_TYPE_PALLET",
      "items": [
        { "sku": 123456789, "quantity": 50 },
        { "sku": 987654321, "quantity": 32 }
      ]
    }
  ]
}
```

每个箱或托盘都有独立商品组成。创建后通过 `operation_id` 查询状态，再调用 `cargoes/rules/get` 检查货位是否符合平台规则。因此 Ozon 能实现：环节二先给候选约束，环节三优化货位，再由平台规则接口复核。

## 四、建议的统一内部结构

两个平台不适合共用同一套原始字段，但可以统一成候选模型：

```yaml
platform: wb_or_ozon
store_id: local-store-id
candidate_id: local-uuid
candidate_type: direct_or_crossdock
destination_warehouse:
  platform_id: platform-warehouse-id
  name: warehouse-name
transit_or_dropoff:
  platform_id: nullable
  name: nullable
allowed_package_types:
  - box
  - pallet
available_timeslots: []
costs: {}
sku_lines:
  - platform_sku: barcode-or-ozon-sku
    quantity: 50
validation:
  status: candidate
  checked_at: timestamp
  expires_at: timestamp-or-null
  raw_reference: raw-response-id
```

平台适配差异：

- WB 的 `platform_sku` 是 `barcode`，候选仓来自 `acceptance/options` 的逐商品结果交集。
- Ozon 的 `platform_sku` 是数值 `sku`，候选仓来自整个草稿的异步计算结果。
- WB 的候选方案目前不能通过公开 API 直接锁定。
- Ozon 的候选方案可通过 `/v2/draft/supply/create` 和状态查询转成正式 `order_id`。

## 五、对 Agent 流程的影响

### WB

```text
商品条码和数量
  -> 查询逐商品仓库/包装准入
  -> 取多 SKU 共同候选仓
  -> 叠加日期系数和中转费用
  -> 生成候选波次
  -> 环节三优化
  -> 再次查询准入
  -> 人工在 Seller 后台建单和预约
```

### Ozon

```text
SKU、数量、集群和配送模式
  -> 创建模式化草稿
  -> 查询草稿计算结果
  -> 选择候选仓和时段
  -> 环节三形成包装优化计划
  -> 创建并锁定供货申请
  -> 创建货位并调用规则检查
  -> 获取标签
```

Ozon 的最终接口顺序还应在真实店铺测试环境中验证权限、枚举值、限流和具体响应字段；本文的 JSON 是关键字段骨架，不替代官方完整 OpenAPI schema。
