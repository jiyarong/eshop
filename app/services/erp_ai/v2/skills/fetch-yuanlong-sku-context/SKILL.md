---
name: fetch-yuanlong-sku-context
description: 获取辕隆 ERP 中单个 SKU 最近数周的经营数据并保存为本地 Markdown 文件。当分析、诊断、规划或生成报告前需要 SKU 业务上下文时使用。
---

# 获取辕隆 SKU 上下文

需要 SKU 的基础信息、逐周利润、渠道漏斗、广告、搜索表现、库存或运营动作时，运行：

```bash
python3 <skill目录>/scripts/fetch_context.py <SKU_CODE> [--weeks <1-12>]
```

`--weeks` 默认是 4。API 会按用户时区自动计算最近已结束自然周的开始和结束日期，最多获取 12 周。

数据保存在当前工作目录：

```text
skus/<SKU_CODE>/context_data/<YYYY-MM-DD>/
```
