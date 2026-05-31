"""
WB API 连通性测试脚本
使用方式: WB_API_KEY=your_token python3 test_api.py
"""
import os
import json
import time
import urllib.request
import urllib.error
from datetime import datetime, timedelta

API_KEY = os.environ.get("WB_API_KEY", "")
if not API_KEY:
    print("❌ 未设置环境变量 WB_API_KEY")
    print("   用法: WB_API_KEY=your_token python3 test_api.py")
    exit(1)

HEADERS = {
    "Authorization": API_KEY,
    "Content-Type": "application/json",
}

# 每个测试项: (名称, 方法, URL, body)
TESTS = [
    # ── 通用 ──────────────────────────────────────────────────────────────
    (
        "Ping（连接检测）",
        "GET",
        "https://common-api.wildberries.ru/ping",
        None,
    ),
    (
        "卖家信息",
        "GET",
        "https://common-api.wildberries.ru/api/v1/seller-info",
        None,
    ),
    # ── 商品内容 ──────────────────────────────────────────────────────────
    (
        "父级分类列表",
        "GET",
        "https://content-api.wildberries.ru/content/v2/object/parent/all",
        None,
    ),
    (
        "商品卡片列表（首页）",
        "POST",
        "https://content-api.wildberries.ru/content/v2/get/cards/list",
        {"settings": {"cursor": {"limit": 5}, "filter": {"withPhoto": -1}}},
    ),
    # ── 价格与折扣 ────────────────────────────────────────────────────────
    (
        "商品价格列表",
        "GET",
        "https://discounts-prices-api.wildberries.ru/api/v2/list/goods/filter?limit=5&offset=0",
        None,
    ),
    # ── 订单 FBS ─────────────────────────────────────────────────────────
    (
        "FBS 新订单",
        "GET",
        "https://marketplace-api.wildberries.ru/api/v3/orders/new",
        None,
    ),
    (
        "卖家仓库列表",
        "GET",
        "https://marketplace-api.wildberries.ru/api/v3/warehouses",
        None,
    ),
    # ── 统计 ──────────────────────────────────────────────────────────────
    (
        "统计-订单报表",
        "GET",
        "https://statistics-api.wildberries.ru/api/v1/supplier/orders"
        f"?dateFrom={(datetime.utcnow()-timedelta(days=1)).strftime('%Y-%m-%d')}",
        None,
    ),
    # ── 分析 ──────────────────────────────────────────────────────────────
    (
        "销售漏斗",
        "POST",
        "https://seller-analytics-api.wildberries.ru/api/analytics/v3/sales-funnel/products",
        {
            "filter": {
                "startDate": (datetime.utcnow() - timedelta(days=7)).strftime("%Y-%m-%d"),
                "endDate": datetime.utcnow().strftime("%Y-%m-%d"),
            },
            "selectedPeriod": {
                "start": (datetime.utcnow() - timedelta(days=7)).strftime("%Y-%m-%d"),
                "end": datetime.utcnow().strftime("%Y-%m-%d"),
            },
            "page": 1,
        },
    ),
    # ── 评价/问答 ─────────────────────────────────────────────────────────
    (
        "未读评价/问题检测",
        "GET",
        "https://feedbacks-api.wildberries.ru/api/v1/new-feedbacks-questions",
        None,
    ),
    # ── 财务 ──────────────────────────────────────────────────────────────
    (
        "账户余额",
        "GET",
        "https://finance-api.wildberries.ru/api/v1/account/balance",
        None,
    ),
    # ── 广告 ──────────────────────────────────────────────────────────────
    (
        "广告活动数量",
        "GET",
        "https://advert-api.wildberries.ru/adv/v1/promotion/count",
        None,
    ),
]

PASS = "✅"
FAIL = "❌"
WARN = "⚠️ "

results = []

print(f"\n{'='*60}")
print(f"  WB API 连通性测试  ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')})")
print(f"{'='*60}\n")

for name, method, url, body in TESTS:
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            status = resp.status
            raw = resp.read()
            try:
                payload = json.loads(raw)
                preview = json.dumps(payload, ensure_ascii=False)[:120]
            except Exception:
                preview = raw[:120].decode(errors="replace")
            icon = PASS
    except urllib.error.HTTPError as e:
        status = e.code
        try:
            payload = json.loads(e.read())
            preview = json.dumps(payload, ensure_ascii=False)[:120]
        except Exception:
            preview = str(e.reason)
        icon = WARN if status in (401, 403, 429) else FAIL
    except Exception as e:
        status = 0
        preview = str(e)[:120]
        icon = FAIL

    line = f"{icon}  [{status}] {name}"
    print(line)
    print(f"      {url}")
    print(f"      → {preview}\n")
    results.append((icon, status, name))
    time.sleep(2)

# 汇总
passed = sum(1 for r in results if r[0] == PASS)
warned = sum(1 for r in results if r[0] == WARN)
failed = sum(1 for r in results if r[0] == FAIL)

print(f"{'='*60}")
print(f"  结果: {passed} 通过 / {warned} 需注意（401/403/429） / {failed} 失败")
print(f"{'='*60}\n")

if warned:
    print("💡 提示：401=Token无效或权限不足，403=无访问权限，429=触发限流")
