# WildBerries API 数据库结构设计

> 本设计目标：用一套统一的数据库结构，承接 WB API 返回的所有关键数据，同时满足通用电商管理平台的业务需求。

---

## 总体架构分层

```
平台层（Marketplace）
    │
    ├── 商品层（Product Catalog）
    │       ├── 分类/属性字典
    │       ├── 商品卡片
    │       └── 价格/库存
    │
    ├── 订单层（Orders）
    │       ├── FBS / DBS / FBW / Click-Collect
    │       └── 供货单
    │
    ├── 营销层（Marketing）
    │       ├── 广告活动
    │       └── 促销日历
    │
    ├── 分析层（Analytics）
    │       ├── 销售漏斗
    │       └── 搜索词
    │
    ├── 沟通层（Communication）
    │       ├── 评价
    │       └── 聊天
    │
    └── 财务层（Finance）
            ├── 对账单
            └── 余额
```

---

## 一、平台与卖家

```sql
-- 支持多平台扩展（WB / Ozon / AliExpress 等）
CREATE TABLE platforms (
    id           SERIAL PRIMARY KEY,
    code         VARCHAR(50) UNIQUE NOT NULL,  -- 'wildberries', 'ozon'
    name         VARCHAR(200) NOT NULL,
    base_api_url VARCHAR(500),
    created_at   TIMESTAMP DEFAULT NOW()
);

-- 卖家账号（一个商家可以有多个平台账号）
CREATE TABLE seller_accounts (
    id            SERIAL PRIMARY KEY,
    platform_id   INT REFERENCES platforms(id),
    name          VARCHAR(200) NOT NULL,
    api_token     TEXT,                        -- 加密存储
    token_type    VARCHAR(50),                 -- personal/service/basic
    token_expires_at TIMESTAMP,
    is_active     BOOLEAN DEFAULT TRUE,
    created_at    TIMESTAMP DEFAULT NOW()
);
```

---

## 二、商品分类与属性字典

```sql
-- 父级分类（Родительские категории）
CREATE TABLE wb_categories (
    id          INT PRIMARY KEY,               -- WB 的 ID
    name        VARCHAR(500) NOT NULL,
    name_en     VARCHAR(500),
    name_zh     VARCHAR(500),
    synced_at   TIMESTAMP
);

-- 子分类/预设（Предметы）
CREATE TABLE wb_subjects (
    id              INT PRIMARY KEY,           -- subjectId
    parent_id       INT REFERENCES wb_categories(id),
    name            VARCHAR(500) NOT NULL,
    name_en         VARCHAR(500),
    synced_at       TIMESTAMP
);

-- 属性定义（Характеристики）
CREATE TABLE wb_characteristics (
    id              INT PRIMARY KEY,           -- charcID
    subject_id      INT REFERENCES wb_subjects(id),
    name            VARCHAR(500) NOT NULL,
    data_type       VARCHAR(50),               -- Целое число/Строка/etc
    unit_name       VARCHAR(100),
    max_count       INT DEFAULT 1,             -- 可选多少个值
    is_required     BOOLEAN DEFAULT FALSE,
    is_popular      BOOLEAN DEFAULT FALSE,
    synced_at       TIMESTAMP
);

-- 属性字典值（颜色/性别/产地/季节/税率）
CREATE TABLE wb_attribute_dict (
    id          SERIAL PRIMARY KEY,
    dict_type   VARCHAR(50) NOT NULL,          -- color/kind/country/season/vat/tnved
    wb_id       VARCHAR(200),
    name        VARCHAR(500) NOT NULL,
    name_en     VARCHAR(500)
);
```

---

## 三、商品（核心）

```sql
-- 商品卡片（nmID 是 WB 唯一标识，一张卡片可含多个 SKU/尺码）
CREATE TABLE products (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    nm_id           BIGINT UNIQUE,             -- WB 商品编号（nmID）
    imt_id          BIGINT,                    -- 商品组 ID（同款不同色共用）
    vendor_code     VARCHAR(500) NOT NULL,     -- 卖家自定义 SKU
    brand           VARCHAR(500),
    title           VARCHAR(1000),
    description     TEXT,
    subject_id      INT REFERENCES wb_subjects(id),
    subject_name    VARCHAR(500),
    wb_category     VARCHAR(500),
    is_in_trash     BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP DEFAULT NOW(),
    updated_at      TIMESTAMP DEFAULT NOW(),
    synced_at       TIMESTAMP
);

-- 商品属性值（存储每个 nmID 的属性）
CREATE TABLE product_characteristics (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT REFERENCES products(id),
    charc_id    INT,
    charc_name  VARCHAR(500),
    value       JSONB                          -- 可以是字符串数组
);

-- SKU / 规格（每个尺码一条记录）
CREATE TABLE product_skus (
    id              BIGSERIAL PRIMARY KEY,
    product_id      BIGINT REFERENCES products(id),
    chrt_id         BIGINT UNIQUE,             -- 规格 ID（chrtID）
    tech_size       VARCHAR(100),              -- 卖家尺码（"XL"）
    wb_size         VARCHAR(100),              -- WB 换算尺码（"52"）
    barcode         VARCHAR(200),              -- EAN/条码
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 商品媒体
CREATE TABLE product_media (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT REFERENCES products(id),
    type        VARCHAR(20),                   -- photo/video
    url         TEXT,
    position    INT,
    created_at  TIMESTAMP DEFAULT NOW()
);

-- 商品标签（Ярлыки）
CREATE TABLE product_tags (
    id          SERIAL PRIMARY KEY,
    account_id  INT REFERENCES seller_accounts(id),
    wb_tag_id   INT,                           -- WB 的 tag ID
    name        VARCHAR(500),
    color       VARCHAR(50)
);

CREATE TABLE product_tag_links (
    product_id  BIGINT REFERENCES products(id),
    tag_id      INT REFERENCES product_tags(id),
    PRIMARY KEY (product_id, tag_id)
);
```

---

## 四、价格与库存

```sql
-- 当前价格（每个 nmID 一条最新记录）
CREATE TABLE product_prices (
    id              BIGSERIAL PRIMARY KEY,
    product_id      BIGINT REFERENCES products(id),
    account_id      INT REFERENCES seller_accounts(id),
    price           DECIMAL(15,2),             -- 门市价（RUB）
    discount        INT,                       -- 折扣 %（0-95）
    club_discount   INT,                       -- WB Club 专属折扣 %
    final_price     DECIMAL(15,2),             -- 实际销售价
    is_in_quarantine BOOLEAN DEFAULT FALSE,    -- 是否被隔离（价格异常）
    updated_at      TIMESTAMP DEFAULT NOW()
);

-- 历史价格变更日志
CREATE TABLE product_price_history (
    id              BIGSERIAL PRIMARY KEY,
    product_id      BIGINT REFERENCES products(id),
    price           DECIMAL(15,2),
    discount        INT,
    club_discount   INT,
    changed_at      TIMESTAMP DEFAULT NOW()
);

-- 卖家仓库
CREATE TABLE warehouses (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_warehouse_id BIGINT UNIQUE,             -- WB 仓库 ID
    name            VARCHAR(500) NOT NULL,
    address         TEXT,
    work_time       VARCHAR(500),
    city            VARCHAR(200),
    longitude       DECIMAL(10,7),
    latitude        DECIMAL(10,7),
    type            VARCHAR(50),               -- fbs/dbs/fbw/click-collect
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT NOW()
);

-- 库存（按仓库+SKU）
CREATE TABLE stock (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    warehouse_id    BIGINT REFERENCES warehouses(id),
    sku_id          BIGINT REFERENCES product_skus(id),
    barcode         VARCHAR(200),
    quantity        INT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMP DEFAULT NOW(),
    UNIQUE (warehouse_id, barcode)
);

-- 库存历史快照
CREATE TABLE stock_history (
    id              BIGSERIAL PRIMARY KEY,
    warehouse_id    BIGINT REFERENCES warehouses(id),
    barcode         VARCHAR(200),
    quantity        INT,
    snapshot_at     TIMESTAMP DEFAULT NOW()
);
```

---

## 五、订单（统一订单表 + 模式区分）

```sql
-- 统一订单表（FBS / DBS / Click-Collect）
CREATE TABLE orders (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_order_id     BIGINT UNIQUE,             -- WB 的 sborochnoye zadaniye ID
    order_uid       VARCHAR(200),              -- 订单 UUID
    srid            VARCHAR(500),              -- 推荐唯一识别字段
    delivery_type   VARCHAR(20) NOT NULL,      -- fbs/dbs/click-collect
    
    -- 商品信息
    nm_id           BIGINT,
    chrt_id         BIGINT,
    article         VARCHAR(500),              -- 卖家 SKU
    barcode         VARCHAR(200),
    
    -- 状态
    supplier_status VARCHAR(50),               -- new/confirm/complete/cancel
    wb_status       VARCHAR(50),               -- waiting/sorted/delivered/...
    
    -- 价格
    price           DECIMAL(15,2),
    converted_price DECIMAL(15,2),
    currency_code   INT DEFAULT 643,           -- 643=RUB
    
    -- 地址/仓库
    warehouse_id    BIGINT REFERENCES warehouses(id),
    wb_office       VARCHAR(500),              -- 目标 WB 仓库名称
    
    -- 元数据标识（强制标识类商品）
    required_meta   JSONB,                     -- ["sgtin", "uin"]
    optional_meta   JSONB,
    
    -- 买家（部分信息需单独调用接口获取）
    buyer_info      JSONB,
    
    is_zero_order   BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL,
    updated_at      TIMESTAMP DEFAULT NOW(),
    synced_at       TIMESTAMP
);

-- 订单元数据（强制标识追踪码）
CREATE TABLE order_meta (
    id          BIGSERIAL PRIMARY KEY,
    order_id    BIGINT REFERENCES orders(id),
    meta_type   VARCHAR(50),                   -- sgtin/uin/imei/gtin/expiration/gtd
    value       VARCHAR(500),
    created_at  TIMESTAMP DEFAULT NOW()
);

-- 订单状态变更历史
CREATE TABLE order_status_history (
    id              BIGSERIAL PRIMARY KEY,
    order_id        BIGINT REFERENCES orders(id),
    supplier_status VARCHAR(50),
    wb_status       VARCHAR(50),
    changed_at      TIMESTAMP DEFAULT NOW()
);
```

---

## 六、供货单（FBS Supply）

```sql
CREATE TABLE supplies (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_supply_id    VARCHAR(100) UNIQUE,       -- "WB-GI-XXXXXXXX"
    name            VARCHAR(500),
    type            VARCHAR(20) DEFAULT 'fbs',
    is_done         BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP,
    closed_at       TIMESTAMP,
    scan_dt         TIMESTAMP,
    synced_at       TIMESTAMP
);

CREATE TABLE supply_orders (
    supply_id   BIGINT REFERENCES supplies(id),
    order_id    BIGINT REFERENCES orders(id),
    added_at    TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (supply_id, order_id)
);

-- 箱子（Trbx）
CREATE TABLE supply_boxes (
    id          BIGSERIAL PRIMARY KEY,
    supply_id   BIGINT REFERENCES supplies(id),
    wb_box_id   BIGINT,
    barcode     VARCHAR(200),
    created_at  TIMESTAMP DEFAULT NOW()
);
```

---

## 七、广告活动

```sql
CREATE TABLE ad_campaigns (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_advert_id    BIGINT UNIQUE,
    name            VARCHAR(500),
    type            INT,                       -- 8=自动, 9=竞价搜索, 6=媒体
    status          INT,                       -- 4=就绪, 9=活跃, 11=暂停, 7=完成
    daily_budget    DECIMAL(15,2),
    total_budget    DECIMAL(15,2),
    start_time      TIMESTAMP,
    end_time        TIMESTAMP,
    created_at      TIMESTAMP,
    updated_at      TIMESTAMP,
    synced_at       TIMESTAMP
);

-- 广告关联商品
CREATE TABLE ad_campaign_products (
    campaign_id BIGINT REFERENCES ad_campaigns(id),
    nm_id       BIGINT,
    bid         DECIMAL(10,2),
    PRIMARY KEY (campaign_id, nm_id)
);

-- 搜索词出价
CREATE TABLE ad_keyword_bids (
    id          BIGSERIAL PRIMARY KEY,
    campaign_id BIGINT REFERENCES ad_campaigns(id),
    keyword     VARCHAR(500),
    bid         DECIMAL(10,2),
    is_active   BOOLEAN DEFAULT TRUE
);

-- 否定词
CREATE TABLE ad_negative_keywords (
    id          BIGSERIAL PRIMARY KEY,
    campaign_id BIGINT REFERENCES ad_campaigns(id),
    keyword     VARCHAR(500)
);

-- 广告日统计
CREATE TABLE ad_daily_stats (
    id          BIGSERIAL PRIMARY KEY,
    campaign_id BIGINT REFERENCES ad_campaigns(id),
    stat_date   DATE,
    views       BIGINT DEFAULT 0,
    clicks      BIGINT DEFAULT 0,
    ctr         DECIMAL(10,4),
    cpc         DECIMAL(10,2),
    spend       DECIMAL(15,2),
    add_to_cart BIGINT DEFAULT 0,
    orders      BIGINT DEFAULT 0,
    cr          DECIMAL(10,4),               -- 转化率
    revenue     DECIMAL(15,2),
    UNIQUE (campaign_id, stat_date)
);

-- 促销活动（Акции）
CREATE TABLE promotions (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_promotion_id BIGINT UNIQUE,
    name            VARCHAR(500),
    period_start    TIMESTAMP,
    period_end      TIMESTAMP,
    discount        INT,
    synced_at       TIMESTAMP
);

CREATE TABLE promotion_products (
    promotion_id    BIGINT REFERENCES promotions(id),
    nm_id           BIGINT,
    discount        INT,
    PRIMARY KEY (promotion_id, nm_id)
);
```

---

## 八、分析数据

```sql
-- 销售漏斗（每日商品统计）
CREATE TABLE analytics_sales_funnel (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    stat_date       DATE NOT NULL,
    nm_id           BIGINT,
    vendor_code     VARCHAR(500),
    brand           VARCHAR(500),
    subject         VARCHAR(500),
    open_card       BIGINT DEFAULT 0,          -- 商品页浏览量
    add_to_cart     BIGINT DEFAULT 0,          -- 加购次数
    orders          BIGINT DEFAULT 0,          -- 下单次数
    orders_sum      DECIMAL(15,2),
    buyouts         BIGINT DEFAULT 0,          -- 完成支付
    buyouts_sum     DECIMAL(15,2),
    cancel_count    BIGINT DEFAULT 0,
    cancel_sum      DECIMAL(15,2),
    conv_to_cart    DECIMAL(10,4),             -- 浏览→加购转化率
    cart_to_order   DECIMAL(10,4),             -- 加购→下单转化率
    UNIQUE (account_id, stat_date, nm_id)
);

-- 搜索词报告
CREATE TABLE analytics_search_terms (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    stat_date       DATE NOT NULL,
    keyword         VARCHAR(1000),
    nm_id           BIGINT,
    orders          BIGINT DEFAULT 0,
    avg_position    DECIMAL(10,2),             -- 平均排名位置
    frequency       BIGINT,                    -- 搜索量
    UNIQUE (account_id, stat_date, keyword, nm_id)
);
```

---

## 九、评价与问答

```sql
CREATE TABLE reviews (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_review_id    VARCHAR(200) UNIQUE,
    nm_id           BIGINT,
    vendor_code     VARCHAR(500),
    size            VARCHAR(100),
    rating          SMALLINT,                  -- 1-5
    text            TEXT,
    photo_urls      JSONB,
    video_urls      JSONB,
    was_viewed      BOOLEAN DEFAULT FALSE,
    is_answered     BOOLEAN DEFAULT FALSE,
    answer_text     TEXT,
    answer_at       TIMESTAMP,
    is_pinned       BOOLEAN DEFAULT FALSE,
    is_archived     BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL,
    synced_at       TIMESTAMP
);

CREATE TABLE questions (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_question_id  VARCHAR(200) UNIQUE,
    nm_id           BIGINT,
    vendor_code     VARCHAR(500),
    text            TEXT,
    was_viewed      BOOLEAN DEFAULT FALSE,
    is_answered     BOOLEAN DEFAULT FALSE,
    answer_text     TEXT,
    answer_at       TIMESTAMP,
    created_at      TIMESTAMP NOT NULL,
    synced_at       TIMESTAMP
);

CREATE TABLE chats (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_chat_id      VARCHAR(200) UNIQUE,
    buyer_id        VARCHAR(200),
    order_id        BIGINT,
    last_message_at TIMESTAMP,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE chat_messages (
    id          BIGSERIAL PRIMARY KEY,
    chat_id     BIGINT REFERENCES chats(id),
    sender      VARCHAR(20),               -- seller/buyer
    text        TEXT,
    file_id     VARCHAR(200),
    sent_at     TIMESTAMP NOT NULL
);

-- 退货申请
CREATE TABLE return_claims (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_claim_id     VARCHAR(200) UNIQUE,
    order_id        BIGINT REFERENCES orders(id),
    nm_id           BIGINT,
    status          VARCHAR(50),               -- pending/approved/rejected
    reason          TEXT,
    response_text   TEXT,
    created_at      TIMESTAMP NOT NULL,
    responded_at    TIMESTAMP,
    synced_at       TIMESTAMP
);
```

---

## 十、财务

```sql
-- 账户余额快照（因限流严格，定期拉取存储）
CREATE TABLE account_balance (
    id          BIGSERIAL PRIMARY KEY,
    account_id  INT REFERENCES seller_accounts(id),
    currency    VARCHAR(10) DEFAULT 'RUB',
    current     DECIMAL(15,2),
    for_withdraw DECIMAL(15,2),
    snapshot_at TIMESTAMP DEFAULT NOW()
);

-- 销售实现报告（对账单汇总）
CREATE TABLE sales_reports (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    wb_report_id    BIGINT UNIQUE,
    date_from       DATE,
    date_to         DATE,
    created_at      DATE,
    total_sales     DECIMAL(15,2),
    total_returns   DECIMAL(15,2),
    total_commission DECIMAL(15,2),
    total_delivery  DECIMAL(15,2),
    total_penalty   DECIMAL(15,2),
    net_payable     DECIMAL(15,2),             -- 实际打款金额
    synced_at       TIMESTAMP
);

-- 销售对账明细（每笔交易一行）
CREATE TABLE sales_report_items (
    id                      BIGSERIAL PRIMARY KEY,
    report_id               BIGINT REFERENCES sales_reports(id),
    account_id              INT REFERENCES seller_accounts(id),
    nm_id                   BIGINT,
    sa_name                 VARCHAR(500),      -- 卖家 SKU
    ts_name                 VARCHAR(100),      -- 尺码
    barcode                 VARCHAR(200),
    brand_name              VARCHAR(500),
    subject_name            VARCHAR(500),
    doc_type                VARCHAR(50),       -- Продажа/Возврат
    quantity                INT,
    retail_price            DECIMAL(15,2),
    retail_amount           DECIMAL(15,2),     -- 含税销售额
    sale_percent            INT,               -- 折扣 %
    commission_percent      DECIMAL(10,4),
    delivery_rub            DECIMAL(15,2),
    penalty                 DECIMAL(15,2),
    additional_payment      DECIMAL(15,2),
    ppvz_for_pay            DECIMAL(15,2),     -- 实际打款给卖家
    srid                    VARCHAR(500),
    order_dt                TIMESTAMP,
    sale_dt                 TIMESTAMP
);
```

---

## 十一、统计报表缓存

```sql
-- 基础销售统计（旧版 statistics API）
CREATE TABLE stats_orders (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    g_number        VARCHAR(200),              -- 订单号
    date            TIMESTAMP NOT NULL,
    last_change_date TIMESTAMP,
    supplier_article VARCHAR(500),
    tech_size       VARCHAR(100),
    barcode         VARCHAR(200),
    total_price     DECIMAL(15,2),
    discount_percent INT,
    warehouse_name  VARCHAR(500),
    oblast          VARCHAR(500),              -- 地区
    nm_id           BIGINT,
    subject         VARCHAR(500),
    category        VARCHAR(500),
    brand           VARCHAR(500),
    is_cancel       BOOLEAN,
    cancel_date     TIMESTAMP,
    order_type      VARCHAR(100),
    srid            VARCHAR(500),
    synced_at       TIMESTAMP
);

CREATE TABLE stats_sales (
    id              BIGSERIAL PRIMARY KEY,
    account_id      INT REFERENCES seller_accounts(id),
    g_number        VARCHAR(200),
    date            TIMESTAMP NOT NULL,
    last_change_date TIMESTAMP,
    supplier_article VARCHAR(500),
    tech_size       VARCHAR(100),
    barcode         VARCHAR(200),
    total_price     DECIMAL(15,2),
    discount_percent INT,
    for_pay         DECIMAL(15,2),             -- 卖家实收
    finished_price  DECIMAL(15,2),
    price_with_disc DECIMAL(15,2),
    nm_id           BIGINT,
    subject         VARCHAR(500),
    category        VARCHAR(500),
    brand           VARCHAR(500),
    is_storno       BOOLEAN,                   -- 是否退货
    srid            VARCHAR(500),
    synced_at       TIMESTAMP
);
```

---

## 十二、同步任务追踪

```sql
CREATE TABLE sync_tasks (
    id          BIGSERIAL PRIMARY KEY,
    account_id  INT REFERENCES seller_accounts(id),
    task_type   VARCHAR(100),                  -- 如 warehouse_remains/acceptance_report
    wb_task_id  VARCHAR(200),                  -- WB 的异步任务 ID
    status      VARCHAR(50),                   -- pending/processing/done/error
    file_url    TEXT,                          -- 下载链接
    created_at  TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);
```

---

## 与通用电商平台数据结构的适配分析

| 通用电商概念 | WB API 映射 | 备注 |
|------------|------------|------|
| **商品（Product）** | `products` + `product_skus` | nmID=WB商品，chrtID=SKU规格 |
| **分类（Category）** | `wb_categories` + `wb_subjects` | 两级分类结构 |
| **价格（Price）** | `product_prices` | 含门市价+折扣，无批发/阶梯价 |
| **库存（Inventory）** | `stock` | 按仓库+条码维度 |
| **订单（Order）** | `orders` | 1订单=1商品1件（WB的"拼单"在gNumber层） |
| **履约/物流** | `supplies` + `supply_orders` | FBS需供货单，FBW另有入仓计划 |
| **评价（Review）** | `reviews` + `questions` | 评价和问答分开 |
| **营销活动** | `ad_campaigns` + `promotions` | 广告+促销两套体系 |
| **财务对账** | `sales_reports` + `sales_report_items` | 周度对账报告 |
| **客服/IM** | `chats` + `chat_messages` | 买卖家双向聊天 |

### 设计要点

1. **WB 订单是最细粒度**：1 个订单（sborochnoye zadaniye）= 1 件商品，与通用平台的"一订单多商品"不同。多件合并用 `gNumber`/`orderUid` 关联。

2. **多履约模式共存**：FBS/DBS/FBW/Click-Collect 共用 `orders` 表，用 `delivery_type` 字段区分；供货单（`supplies`）只适用于 FBS。

3. **库存双轨**：卖家仓库存通过 `stock` 表管理，FBW 仓的库存通过 WB Analytics API（`stats_orders`）的库存报告拉取，不能直接写入。

4. **异步报告模式**：多个报告（仓库库存报告、付费存储报告等）是三步骤异步流程，用 `sync_tasks` 表追踪任务状态。

5. **限流敏感**：财务接口限流极严（1次/分钟），需在本地缓存并定时同步，不能实时查询。

6. **Token 分类**：不同功能需要不同类别的 Token，系统需在 `seller_accounts` 表中存储多个 Token 或维护 Token 权限映射。
