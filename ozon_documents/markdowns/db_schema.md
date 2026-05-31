# Ozon 原始数据表结构（raw_ozon_*）

所有表均为原始镜像层，忠实保存 Ozon API 返回数据，不做业务逻辑。

**命名规则**: `raw_ozon_<实体>`  
**Base URL**: `https://api-seller.ozon.ru`  
**认证**: Header `Client-Id` + `Api-Key`  
**限流**: 每分钟视接口而定（一般 1–10 req/s）

---

## 表总览

| 表名 | 来源 API | 说明 |
|------|---------|------|
| `raw_ozon_seller_accounts` | `/v1/seller/info` | 卖家账号（存 Client-Id / Api-Key） |
| `raw_ozon_products` | `/v3/product/info/list` | 商品基础信息 |
| `raw_ozon_product_attributes` | `/v4/product/attributes` | 商品属性（类目属性值） |
| `raw_ozon_product_prices` | `/v5/product/info/prices` | 商品价格与折扣 |
| `raw_ozon_product_stocks` | `/v4/product/info/stocks` | 各仓库库存 |
| `raw_ozon_categories` | `/v1/description-category/tree` | 商品类目树 |
| `raw_ozon_warehouses` | `/v1/warehouse/list` | 卖家仓库列表 |
| `raw_ozon_postings_fbs` | `/v3/posting/fbs/list` | FBS 发货单（卖家仓） |
| `raw_ozon_postings_fbo` | `/v2/posting/fbo/list` | FBO 发货单（Ozon 仓） |
| `raw_ozon_posting_items` | （从 posting 展开） | 发货单商品明细 |
| `raw_ozon_returns` | `/v1/returns/list` | 退货单（FBO+FBS，用 `return_schema` 区分） |
| `raw_ozon_finance_transactions` | `/v3/finance/transaction/list` | 财务流水明细 |
| `raw_ozon_finance_realization` | `/v2/finance/realization` | 月度对账报表 |
| `raw_ozon_analytics` | `/v1/analytics/data` | 销售分析数据 |
| `raw_ozon_analytics_stocks` | `/v2/analytics/stock_on_warehouses` | 仓库库存分析 |
| `raw_ozon_reviews` | `/v1/review/list` | 商品评价 |
| `raw_ozon_chats` | `/v1/chat/list` | 买家聊天会话 |
| `raw_ozon_chat_messages` | `/v1/chat/history` | 聊天消息 |
| `raw_ozon_promotions` | `/v1/actions` | 促销活动列表 |
| `raw_ozon_reports` | `/v1/report/list` | 报表任务 |

---

## 详细表结构

### raw_ozon_seller_accounts

所有其他 `raw_ozon_*` 表都通过 `account_id` 关联到此表。

```sql
CREATE TABLE raw_ozon_seller_accounts (
  id                BIGSERIAL PRIMARY KEY,

  -- 认证凭据
  client_id         VARCHAR(50)  NOT NULL UNIQUE,  -- Ozon 卖家账号 ID（数字字符串）
  api_key           VARCHAR(500) NOT NULL,          -- Api-Key（加密存储建议）

  -- 账号基础信息（来自 /v1/seller/info）
  company_name      VARCHAR(500),   -- 公司名称（company.name）
  legal_name        VARCHAR(500),   -- 法人名（company.legal_name）
  inn               VARCHAR(50),    -- 税号
  ownership_form    VARCHAR(50),    -- 主体类型（ООО / ИП / ...）

  -- 状态
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  memo              TEXT,           -- 备注（如"俄罗斯店铺1"）

  raw_json          JSONB,          -- /v1/seller/info 原始响应

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

> **安全提醒**：`api_key` 建议在应用层加密（Rails `attr_encrypted` 或 ActiveRecord Encryption），不明文存库。

---

### raw_ozon_products

```sql
CREATE TABLE raw_ozon_products (
  id                      BIGSERIAL PRIMARY KEY,

  -- 来自 /v3/product/info/list items[]
  ozon_product_id         BIGINT NOT NULL UNIQUE,   -- Ozon 商品 ID (field: id)
  offer_id                VARCHAR(255),              -- 卖家 SKU (seller's article)
  name                    VARCHAR(1000),
  description_category_id BIGINT,
  type_id                 BIGINT,
  currency_code           VARCHAR(10),

  -- 状态
  is_archived             BOOLEAN DEFAULT FALSE,
  is_autoarchived         BOOLEAN DEFAULT FALSE,
  has_discounted_fbo_item BOOLEAN DEFAULT FALSE,
  discounted_fbo_stocks   INTEGER DEFAULT 0,

  -- 尺寸 & 图片（JSON 冗余，方便查询）
  barcodes                TEXT[],
  images                  JSONB,
  images360               JSONB,
  color_image             TEXT[],

  -- 佣金信息
  commissions             JSONB,    -- array of {delivery_schema, percent, value, ...}

  -- 可销售性
  availabilities          JSONB,    -- [{delivery_schema, is_available, ...}]

  -- 原始完整响应
  raw_json                JSONB NOT NULL,

  created_at              TIMESTAMPTZ,  -- Ozon 商品创建时间
  synced_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_ozon_product UNIQUE (ozon_product_id)
);

CREATE INDEX idx_raw_ozon_products_offer_id ON raw_ozon_products (offer_id);
CREATE INDEX idx_raw_ozon_products_synced ON raw_ozon_products (synced_at);
```

---

### raw_ozon_product_prices

```sql
CREATE TABLE raw_ozon_product_prices (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v5/product/info/prices items[]
  ozon_product_id     BIGINT NOT NULL,
  offer_id            VARCHAR(255),

  price               NUMERIC(18,2),        -- 当前售价
  old_price           NUMERIC(18,2),        -- 划线价
  marketing_price     NUMERIC(18,2),        -- 营销价
  min_price           NUMERIC(18,2),        -- 最低价
  buybox_price        NUMERIC(18,2),        -- BuyBox 价格
  currency_code       VARCHAR(10),

  -- 佣金
  commissions         JSONB,

  -- 促销
  is_in_discount      BOOLEAN DEFAULT FALSE,
  discount_percent    NUMERIC(5,2),

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_ozon_price UNIQUE (ozon_product_id)
);

CREATE INDEX idx_raw_ozon_prices_product ON raw_ozon_product_prices (ozon_product_id);
```

---

### raw_ozon_product_stocks

```sql
CREATE TABLE raw_ozon_product_stocks (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v4/product/info/stocks items[]
  ozon_product_id     BIGINT NOT NULL,
  offer_id            VARCHAR(255),

  -- 汇总
  present_fbo         INTEGER DEFAULT 0,  -- FBO 在库
  reserved_fbo        INTEGER DEFAULT 0,  -- FBO 预留
  present_fbs         INTEGER DEFAULT 0,  -- FBS 在库
  reserved_fbs        INTEGER DEFAULT 0,  -- FBS 预留

  -- 按仓库明细
  stocks_by_warehouse JSONB,  -- [{warehouse_id, warehouse_name, present, reserved}]

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_ozon_stock UNIQUE (ozon_product_id)
);

CREATE INDEX idx_raw_ozon_stocks_product ON raw_ozon_product_stocks (ozon_product_id);
```

---

### raw_ozon_categories

```sql
CREATE TABLE raw_ozon_categories (
  id                        BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/description-category/tree
  category_id               BIGINT NOT NULL,
  parent_id                 BIGINT,
  title                     VARCHAR(500),
  disabled                  BOOLEAN DEFAULT FALSE,
  children                  JSONB,    -- 子类目（冗余存储完整树）

  raw_json                  JSONB NOT NULL,
  synced_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_ozon_category UNIQUE (category_id)
);
```

---

### raw_ozon_warehouses

```sql
CREATE TABLE raw_ozon_warehouses (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/warehouse/list
  warehouse_id        BIGINT NOT NULL,
  name                VARCHAR(500),
  is_rfbs             BOOLEAN DEFAULT FALSE,  -- rFBS（第三方物流）
  has_entrusted_acceptance BOOLEAN DEFAULT FALSE,
  status              VARCHAR(100),   -- working / not_working / ...

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_ozon_warehouse UNIQUE (warehouse_id)
);
```

---

### raw_ozon_postings_fbs

Ozon FBS 发货单（卖家仓发货）。1 条记录 = 1 个 posting（可含多件商品）。

```sql
CREATE TABLE raw_ozon_postings_fbs (
  id                        BIGSERIAL PRIMARY KEY,

  -- 来自 /v3/posting/fbs/list postings[]
  posting_number            VARCHAR(100) NOT NULL UNIQUE,  -- 发货单号
  order_id                  BIGINT,
  order_number              VARCHAR(100),
  parent_posting_number     VARCHAR(100),                  -- 拆单时父单号

  status                    VARCHAR(100),  -- awaiting_packaging / awaiting_deliver / ...
  substatus                 VARCHAR(100),

  -- 时间
  created_at                TIMESTAMPTZ,
  in_process_at             TIMESTAMPTZ,
  shipment_date             TIMESTAMPTZ,  -- 必须发货截止时间
  delivering_date           TIMESTAMPTZ,

  -- 配送
  delivery_method_id        BIGINT,
  delivery_method_name      VARCHAR(500),
  tpl_integration_type      VARCHAR(50),   -- ozon / 3pl / ...
  tracking_number           VARCHAR(255),
  is_express                BOOLEAN DEFAULT FALSE,
  is_multibox               BOOLEAN DEFAULT FALSE,
  multi_box_qty             INTEGER DEFAULT 1,

  -- 买家（脱敏存储）
  customer_id               BIGINT,
  addressee_name            VARCHAR(500),

  -- 财务快照
  financial_data            JSONB,  -- {products: [{...commission, price, payout}]}

  -- 分析数据
  analytics_data            JSONB,  -- {region, city, warehouse_name, ...}

  -- 完整原始响应
  raw_json                  JSONB NOT NULL,

  synced_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_postings_fbs_status ON raw_ozon_postings_fbs (status);
CREATE INDEX idx_raw_ozon_postings_fbs_created ON raw_ozon_postings_fbs (created_at);
CREATE INDEX idx_raw_ozon_postings_fbs_order ON raw_ozon_postings_fbs (order_id);
CREATE INDEX idx_raw_ozon_postings_fbs_synced ON raw_ozon_postings_fbs (synced_at);
```

**FBS 发货状态**:

| 状态 | 含义 |
|------|------|
| `awaiting_packaging` | 等待打包 |
| `awaiting_deliver` | 等待交付 |
| `arbitration` | 仲裁中 |
| `client_arbitration` | 买家仲裁 |
| `delivering` | 配送中 |
| `driver_pickup` | 司机取货 |
| `delivered` | 已送达 |
| `cancelled` | 已取消 |
| `not_accepted` | 未被收货 |

---

### raw_ozon_postings_fbo

Ozon FBO 发货单（Ozon 仓发货）。

```sql
CREATE TABLE raw_ozon_postings_fbo (
  id                    BIGSERIAL PRIMARY KEY,

  -- 来自 /v2/posting/fbo/list result[]
  posting_number        VARCHAR(100) NOT NULL UNIQUE,
  order_id              BIGINT,
  order_number          VARCHAR(100),

  status                VARCHAR(100),
  substatus             VARCHAR(100),
  cancel_reason_id      INTEGER,

  created_at            TIMESTAMPTZ,
  in_process_at         TIMESTAMPTZ,
  fact_delivery_date    TIMESTAMPTZ,

  -- 财务
  financial_data        JSONB,  -- {products: [...], cluster_to, cluster_from}
  analytics_data        JSONB,

  raw_json              JSONB NOT NULL,
  synced_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_postings_fbo_status ON raw_ozon_postings_fbo (status);
CREATE INDEX idx_raw_ozon_postings_fbo_created ON raw_ozon_postings_fbo (created_at);
```

---

### raw_ozon_posting_items

从 FBS/FBO posting 展开的商品明细行（ETL 时写入，方便按商品统计）。

```sql
CREATE TABLE raw_ozon_posting_items (
  id                  BIGSERIAL PRIMARY KEY,

  posting_number      VARCHAR(100) NOT NULL,
  posting_type        VARCHAR(10) NOT NULL,  -- 'fbs' | 'fbo'

  -- 来自 products[]
  ozon_sku            BIGINT,             -- Ozon SKU ID
  offer_id            VARCHAR(255),       -- 卖家 SKU
  name                VARCHAR(1000),
  quantity            INTEGER NOT NULL DEFAULT 1,

  -- 价格（单件）
  price               NUMERIC(18,2),
  old_price           NUMERIC(18,2),
  currency_code       VARCHAR(10),
  payout              NUMERIC(18,2),       -- 实际到账
  commission_amount   NUMERIC(18,2),
  commission_percent  NUMERIC(5,2),

  raw_json            JSONB NOT NULL,      -- 原始 product 对象

  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_posting_items_posting ON raw_ozon_posting_items (posting_number);
CREATE INDEX idx_raw_ozon_posting_items_sku ON raw_ozon_posting_items (ozon_sku);
CREATE INDEX idx_raw_ozon_posting_items_offer ON raw_ozon_posting_items (offer_id);
```

---

### raw_ozon_returns

FBO 和 FBS 退货统一存一张表，用 `return_schema` 区分。来源接口：`/v1/returns/list`。

```sql
CREATE TABLE raw_ozon_returns (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/returns/list returns[]
  return_id           BIGINT NOT NULL UNIQUE,       -- field: id
  return_schema       VARCHAR(10) NOT NULL,          -- 'FBS' | 'FBO'
  return_type         VARCHAR(50),                   -- 'Cancellation' | 'Return'
  return_reason_name  VARCHAR(500),

  posting_number      VARCHAR(100),
  order_id            BIGINT,
  order_number        VARCHAR(100),

  -- 商品信息（来自 product 子对象）
  ozon_sku            BIGINT,
  offer_id            VARCHAR(255),
  product_name        VARCHAR(1000),
  quantity            INTEGER DEFAULT 1,
  price               NUMERIC(18,2),

  -- 当前位置 & 目标位置
  place               JSONB,   -- {warehouse_id, warehouse_name}
  target_place        JSONB,

  -- 仓储状态
  storage             JSONB,   -- {status, last_free_day, ...}
  visual_status       VARCHAR(100),  -- 来自 visual.status（买家可见状态）

  -- 赔偿状态
  compensation_status JSONB,

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_returns_schema  ON raw_ozon_returns (return_schema);
CREATE INDEX idx_raw_ozon_returns_posting ON raw_ozon_returns (posting_number);
CREATE INDEX idx_raw_ozon_returns_status  ON raw_ozon_returns (visual_status);
```

---

### raw_ozon_finance_transactions

```sql
CREATE TABLE raw_ozon_finance_transactions (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v3/finance/transaction/list operations[]
  operation_id        BIGINT NOT NULL UNIQUE,
  operation_type      VARCHAR(100),      -- ClientReturnAgentOperation / MarketplaceRedeem / ...
  operation_type_name VARCHAR(500),
  operation_date      TIMESTAMPTZ,

  posting_number      VARCHAR(100),
  order_date          TIMESTAMPTZ,
  order_number        VARCHAR(100),

  -- 金额
  amount              NUMERIC(18,2),     -- 正值=收入，负值=扣款
  currency_code       VARCHAR(10) DEFAULT 'RUB',

  -- 明细
  accruals_for_sale   NUMERIC(18,2),
  sale_commission     NUMERIC(18,2),
  delivery_charge     NUMERIC(18,2),
  return_delivery_charge NUMERIC(18,2),

  -- 商品
  items               JSONB,             -- [{sku, name, offer_id, quantity, ...}]
  services            JSONB,             -- [{name, price}]

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_finance_tx_date ON raw_ozon_finance_transactions (operation_date);
CREATE INDEX idx_raw_ozon_finance_tx_type ON raw_ozon_finance_transactions (operation_type);
CREATE INDEX idx_raw_ozon_finance_tx_posting ON raw_ozon_finance_transactions (posting_number);
```

---

### raw_ozon_finance_realization

月度对账结算报表（按 `month` 唯一）。

```sql
CREATE TABLE raw_ozon_finance_realization (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v2/finance/realization
  report_date         DATE NOT NULL UNIQUE,  -- 报表月份（YYYY-MM-01）
  doc_number          VARCHAR(100),
  doc_date            DATE,

  -- 汇总金额
  accruals_for_sale       NUMERIC(18,2),
  compensation_amount     NUMERIC(18,2),
  money_transfer          NUMERIC(18,2),
  total_amount            NUMERIC(18,2),

  -- 明细行（postings 级别太多，保留 JSON）
  rows                    JSONB,   -- array of posting-level rows
  start_balance           NUMERIC(18,2),
  close_balance           NUMERIC(18,2),

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### raw_ozon_analytics

```sql
CREATE TABLE raw_ozon_analytics (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/analytics/data result.data[]
  date_from           DATE NOT NULL,
  date_to             DATE NOT NULL,
  dimension_keys      TEXT[],            -- 聚合维度（sku / spu / day / ...）
  dimension_values    JSONB,             -- 维度值对应关系

  -- 指标（metrics 字段按需展开）
  ordered_units       INTEGER,
  revenue             NUMERIC(18,2),
  returns_count       INTEGER,
  cancellations       INTEGER,
  hits_view_pdp       INTEGER,
  hits_tocart         INTEGER,
  session_view        INTEGER,
  adv_view_all        INTEGER,

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_analytics_dates ON raw_ozon_analytics (date_from, date_to);
```

---

### raw_ozon_reviews

```sql
CREATE TABLE raw_ozon_reviews (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/review/list reviews[]
  review_id           VARCHAR(100) NOT NULL UNIQUE,
  ozon_sku            BIGINT,
  offer_id            VARCHAR(255),
  product_name        VARCHAR(1000),

  reviewer_name       VARCHAR(255),
  rating              INTEGER,           -- 1–5
  title               VARCHAR(500),
  comment             TEXT,

  -- 卖家回复
  response            TEXT,
  response_at         TIMESTAMPTZ,
  response_status     VARCHAR(50),       -- empty / answered / ...

  -- 状态
  status              VARCHAR(50),       -- published / moderation / archived
  created_at          TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ,

  -- 图片
  media               JSONB,

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_reviews_sku ON raw_ozon_reviews (ozon_sku);
CREATE INDEX idx_raw_ozon_reviews_rating ON raw_ozon_reviews (rating);
CREATE INDEX idx_raw_ozon_reviews_status ON raw_ozon_reviews (status);
```

---

### raw_ozon_chats

```sql
CREATE TABLE raw_ozon_chats (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/chat/list chats[]
  chat_id             VARCHAR(100) NOT NULL UNIQUE,
  chat_type           VARCHAR(50),    -- Buyer_Seller / ...
  first_message_id    VARCHAR(100),
  last_message        JSONB,          -- {text, created_at, ...}
  unread_count        INTEGER DEFAULT 0,
  status              VARCHAR(50),    -- opened / closed

  -- 关联
  order_number        VARCHAR(100),

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### raw_ozon_chat_messages

```sql
CREATE TABLE raw_ozon_chat_messages (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/chat/history messages[]
  message_id          VARCHAR(100) NOT NULL UNIQUE,
  chat_id             VARCHAR(100) NOT NULL,

  direction           VARCHAR(10),    -- in / out
  data                JSONB,          -- {text} | {image_url} | {attachment}
  created_at          TIMESTAMPTZ,

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_chat_messages_chat ON raw_ozon_chat_messages (chat_id);
CREATE INDEX idx_raw_ozon_chat_messages_created ON raw_ozon_chat_messages (created_at);
```

---

### raw_ozon_promotions

```sql
CREATE TABLE raw_ozon_promotions (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/actions items[]
  action_id           BIGINT NOT NULL UNIQUE,
  title               VARCHAR(1000),
  action_type         VARCHAR(100),   -- promotion / coupon / ...
  description         TEXT,

  date_start          TIMESTAMPTZ,
  date_end            TIMESTAMPTZ,
  freeze_date         TIMESTAMPTZ,

  is_participating    BOOLEAN DEFAULT FALSE,
  participating_products_count INTEGER DEFAULT 0,
  products_count      INTEGER DEFAULT 0,

  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

### raw_ozon_reports

```sql
CREATE TABLE raw_ozon_reports (
  id                  BIGSERIAL PRIMARY KEY,

  -- 来自 /v1/report/list reports[]
  report_code         VARCHAR(100) NOT NULL UNIQUE,  -- 报表唯一码
  report_type         VARCHAR(100),   -- seller / finance / ...
  status              VARCHAR(50),    -- success / failed / processing
  error               TEXT,
  file_url            TEXT,           -- 下载链接

  params              JSONB,          -- 生成报表时的参数

  created_at          TIMESTAMPTZ,
  raw_json            JSONB NOT NULL,
  synced_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_raw_ozon_reports_type ON raw_ozon_reports (report_type);
CREATE INDEX idx_raw_ozon_reports_status ON raw_ozon_reports (status);
```

---

## 与 ec_* 层的 ETL 映射

```
raw_ozon_products                → ec_products   (platform='ozon', external_id=ozon_product_id)
raw_ozon_products                → ec_skus        (offer_id 对应 SKU)
raw_ozon_postings_fbs            → ec_orders      (platform='ozon', external_id=posting_number)
raw_ozon_postings_fbo            → ec_orders      (platform='ozon', external_id=posting_number)
raw_ozon_posting_items           → ec_order_items
raw_ozon_product_prices          → ec_product_prices
raw_ozon_product_stocks          → ec_stocks
raw_ozon_warehouses              → ec_warehouses
raw_ozon_finance_transactions    → ec_financial_transactions (规划中)
raw_ozon_reviews                 → ec_reviews (规划中)
```

**注意**:  
- Ozon 的 `posting_number` 对应 WB 的 `order_uid`，是唯一订单键  
- Ozon 每个 posting 含多件商品（与 WB 不同，WB 1行=1件）  
- FBS/FBO 是不同发货模式，共享 `ec_orders` 通过 `delivery_schema` 字段区分
