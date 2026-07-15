# Weekly Rates SQL Skill

用于回答周汇率、RUB/CNY/BYN 换算、周报汇率缺失排查相关问题。

## 适用问题

- 查询某一周使用的人民币、卢布、白俄罗斯卢布换算参数。
- 排查 WR、WSU、WSU-DEEP 因缺少汇率无法计算的问题。
- 解释周利润归集中 WB BYN 转 CNY、Ozon RUB 转 CNY 的口径。

## 周汇率表

### `ec_weekly_rates`

周报使用的汇率表，一周一条。

- `week_start`：周开始日期，必须是周一，唯一。
- `rate_cny_rub`：1 CNY 对应多少 RUB。
- `rate_byn_rub`：1 BYN 对应多少 RUB。
- `created_at`、`updated_at`。

关系：

- WR、WSU、WSU-DEEP 都按 `from_date.beginning_of_week(:monday)` 读取 `ec_weekly_rates.week_start`。
- `week_start` 缺失时，周利润归集不可计算。
- `ec_weekly_rates` 不直接关联 SKU、订单或平台账号，只作为周报换算参数。

## 换算口径

- Ozon 原始财务金额通常为 RUB；转 CNY 使用 `rub_cny = 1 / rate_cny_rub`。
- WB WR 结果是 BYN 口径；转 CNY 使用 `byn_cny = rate_byn_rub / rate_cny_rub`。
- Ozon 货物成本在 WR 内需要从 CNY 成本折到 RUB，使用 `rate_cny_rub`，并在现有周利润归集逻辑中带 3% 缓冲。

## 查询策略

- 用户问“某周汇率”“周报为什么算不出来”“WR/WSU 用哪个汇率”时，优先查询 `ec_weekly_rates`。
- 日期不是周一时，先换算到该日期所在自然周周一再查 `week_start`。
- 不要使用不存在的 `currency` 或 `rate_to_cny` 字段。
- 周利润字段和平台财务归因逻辑加载 `weekly_profit_attribution` Skill；本 Skill 只描述汇率表和换算口径。
