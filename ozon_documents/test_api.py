"""
Ozon Seller API 连通性测试脚本
使用方式: OZON_CLIENT_ID=xxx OZON_API_KEY=yyy python3 test_api.py
"""
import os
import json
import time
import urllib.request
import urllib.error
from datetime import datetime, timedelta, timezone

CLIENT_ID = os.environ.get("OZON_CLIENT_ID", "")
API_KEY   = os.environ.get("OZON_API_KEY", "")

if not CLIENT_ID or not API_KEY:
    print("❌ 未设置环境变量")
    print("   用法: OZON_CLIENT_ID=xxx OZON_API_KEY=yyy python3 test_api.py")
    exit(1)

BASE = "https://api-seller.ozon.ru"

HEADERS = {
    "Client-Id":      CLIENT_ID,
    "Api-Key":        API_KEY,
    "Content-Type":   "application/json",
}

# 日期辅助
now   = datetime.now(timezone.utc)
d7    = (now - timedelta(days=7)).strftime("%Y-%m-%dT00:00:00Z")
today = now.strftime("%Y-%m-%dT23:59:59Z")
month = now.month
year  = now.year

# 每条: (显示名称, 方法, 路径, body或None)
TESTS = [
    # ── 认证 & 卖家信息 ───────────────────────────────────────────────────
    (
        "当前 API Key 权限列表",
        "POST", "/v1/roles",
        {},
    ),
    (
        "卖家账号信息",
        "POST", "/v1/seller/info",
        {},
    ),
    (
        "卖家评分概览",
        "POST", "/v1/rating/summary",
        {"rating_type": ["ALL"]},
    ),

    # ── 商品 ──────────────────────────────────────────────────────────────
    (
        "商品类目树",
        "POST", "/v1/description-category/tree",
        {"language": "ZH_HANS"},
    ),
    (
        "商品列表（首页 10 条）",
        "POST", "/v3/product/list",
        {"filter": {}, "limit": 10, "last_id": ""},
    ),
    (
        "商品价格信息（首页 5 条）",
        "POST", "/v5/product/info/prices",
        {"limit": 5, "filter": {}, "cursor": ""},
    ),
    (
        "商品库存（首页 5 条）",
        "POST", "/v4/product/info/stocks",
        {"limit": 5, "filter": {}, "cursor": ""},
    ),

    # ── 仓库 ──────────────────────────────────────────────────────────────
    (
        "卖家仓库列表",
        "POST", "/v2/warehouse/list",
        {"limit": 100},
    ),

    # ── FBS 发货单 ────────────────────────────────────────────────────────
    (
        "FBS 发货单列表（近 7 天）",
        "POST", "/v3/posting/fbs/list",
        {
            "dir":    "asc",
            "filter": {"since": d7, "to": today, "status": ""},
            "limit":  10,
            "offset": 0,
            "with":   {"analytics_data": True, "financial_data": True},
        },
    ),

    # ── FBO 发货单 ────────────────────────────────────────────────────────
    (
        "FBO 发货单列表（近 7 天）",
        "POST", "/v2/posting/fbo/list",
        {
            "dir":    "asc",
            "filter": {"since": d7, "to": today, "status": ""},
            "limit":  10,
            "offset": 0,
            "with":   {"analytics_data": True, "financial_data": True},
        },
    ),

    # ── 退货 ──────────────────────────────────────────────────────────────
    (
        "FBS 退货列表（首页 5 条）",
        "POST", "/v2/returns/rfbs/list",
        {
            "filter": {},
            "limit":  5,
            "last_id": 0,
        },
    ),

    # ── 财务 ──────────────────────────────────────────────────────────────
    (
        "财务流水（近 7 天，首页）",
        "POST", "/v3/finance/transaction/list",
        {
            "filter": {
                "date": {"from": d7, "to": today},
                "operation_type": [],
                "transaction_type": "all",
            },
            "page":      1,
            "page_size": 10,
        },
    ),
    (
        f"月度对账报表（上个月）",
        "POST", "/v2/finance/realization",
        {"month": month - 1 if month > 1 else 12, "year": year if month > 1 else year - 1},
    ),

    # ── 分析 ──────────────────────────────────────────────────────────────
    (
        "销售分析数据（近 7 天，按 SKU）",
        "POST", "/v1/analytics/data",
        {
            "date_from":  (now - timedelta(days=7)).strftime("%Y-%m-%d"),
            "date_to":    now.strftime("%Y-%m-%d"),
            "dimension":  ["sku"],
            "filters":    [],
            "limit":      5,
            "offset":     0,
            "metrics":    ["revenue", "ordered_units"],
            "sort":       [{"key": "revenue", "order": "DESC"}],
        },
    ),
    (
        "仓库库存分析（FBO）",
        "POST", "/v2/analytics/stock_on_warehouses",
        {"limit": 5, "offset": 0, "warehouse_type": "ALL"},
    ),

    # ── 评价 ──────────────────────────────────────────────────────────────
    (
        "评价列表（已发布，首页 5 条）",
        "POST", "/v1/review/list",
        {"last_id": "", "limit": 20, "sort_dir": "DESC", "status": "ALL"},
    ),

    # ── 聊天 ──────────────────────────────────────────────────────────────
    (
        "聊天列表（首页 5 条）",
        "POST", "/v3/chat/list",
        {"limit": 5, "offset": 0},
    ),

    # ── 报表 ──────────────────────────────────────────────────────────────
    (
        "报表任务列表",
        "POST", "/v1/report/list",
        {"page": 1, "page_size": 5, "report_type": ""},
    ),

    # ── 促销 ──────────────────────────────────────────────────────────────
    (
        "当前可参与的促销活动",
        "GET", "/v1/actions",
        None,
    ),
]

PASS = "✅"
FAIL = "❌"
WARN = "⚠️ "

results = []

print(f"\n{'='*64}")
print(f"  Ozon Seller API 连通性测试  ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
print(f"  Client-Id: {CLIENT_ID[:6]}***")
print(f"{'='*64}\n")

for name, method, path, body in TESTS:
    url  = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req  = urllib.request.Request(url, data=data, headers=HEADERS, method=method)

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status  = resp.status
            raw     = resp.read()
            try:
                payload = json.loads(raw)
                preview = json.dumps(payload, ensure_ascii=False)[:150]
            except Exception:
                preview = raw[:150].decode(errors="replace")
            icon = PASS
    except urllib.error.HTTPError as e:
        status = e.code
        try:
            payload = json.loads(e.read())
            preview = json.dumps(payload, ensure_ascii=False)[:150]
        except Exception:
            preview = str(e.reason)
        icon = WARN if status in (401, 403, 429) else FAIL
    except Exception as e:
        status  = 0
        preview = str(e)[:150]
        icon    = FAIL

    print(f"{icon}  [{status}] {name}")
    print(f"      {method} {path}")
    print(f"      → {preview}\n")
    results.append((icon, status, name))
    time.sleep(0.5)

# ── 汇总 ─────────────────────────────────────────────────────────────────────
passed = sum(1 for r in results if r[0] == PASS)
warned = sum(1 for r in results if r[0] == WARN)
failed = sum(1 for r in results if r[0] == FAIL)

print(f"{'='*64}")
print(f"  结果: {passed} 通过 / {warned} 需注意（401/403/429）/ {failed} 失败")
print(f"{'='*64}\n")

if warned:
    print("💡 提示:")
    print("   401 — Client-Id 或 Api-Key 无效")
    print("   403 — 当前 Key 无此接口权限（在 Ozon 后台 → 设置 → API Keys 中开启）")
    print("   429 — 触发限流，适当加大 sleep 间隔")
