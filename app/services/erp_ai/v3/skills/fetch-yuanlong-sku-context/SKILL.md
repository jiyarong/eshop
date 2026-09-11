---
name: fetch-yuanlong-sku-context
description: 并发获取辕隆 ERP 单个 SKU 的 v3 分段经营上下文并缓存为本地 Markdown。当分析、诊断、规划或生成报告前需要 SKU 最新业务上下文时使用。
---

# 获取辕隆 SKU v3 上下文

需要 SKU 的基础信息、利润归集、销售漏斗、广告、搜索词、订单、送仓、运营动作、库存、生命周期或分仓建议时，运行：

```bash
python3 <skill目录>/scripts/fetch_context.py <SKU_CODE> [--weeks <1-12>]
```

脚本会并发请求 `/ai/v3/sku/*_context.md` 分段接口，由服务端直接返回 Markdown。`--weeks` 默认是 4，按本地日期计算最近已结束自然周；也可以传 `--period-from <YYYY-MM-DD> --period-to <YYYY-MM-DD>` 指定完整自然周范围。

必需环境变量：

- `YUANLONG_API_KEY`：ERP API Token

可选参数：

- `--base-url`：默认读取 `YUANLONG_API_BASE_URL`，否则使用 `http://eshop.evexport.cn`
- `--target-days`：分仓建议目标覆盖天数，接口默认 28
- `--refresh`：忽略当天缓存重新拉取

数据保存在当前工作目录：

```text
skus/<SKU_CODE>/context_data/<YYYY-MM-DD>/
```

每个上下文板块单独写入一个 Markdown 文件，便于按需读取。字段结构参考 [references/api-schema.md](references/api-schema.md)。
