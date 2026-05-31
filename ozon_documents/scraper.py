"""
Ozon Seller API docs scraper — pure HTTP (no browser).
Tries to fetch the OpenAPI/Swagger spec directly, then falls back to HTML parsing.
"""
import json
import re
import sys
import time
from pathlib import Path

import httpx

OUT_DIR = Path(__file__).parent
MARKDOWNS_DIR = OUT_DIR / "markdowns"
MARKDOWNS_DIR.mkdir(exist_ok=True)

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) "
                  "Chrome/124.0.0.0 Safari/537.36",
    "Accept": "application/json, text/html, */*",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Referer": "https://docs.ozon.ru/",
}

# Candidate OpenAPI spec URLs — Ozon typically serves Redoc from one of these
SPEC_CANDIDATES = [
    "https://docs.ozon.ru/api/seller/zh/swagger.json",
    "https://docs.ozon.ru/api/seller/swagger.json",
    "https://docs.ozon.ru/api/seller/zh/openapi.json",
    "https://docs.ozon.ru/api/seller/openapi.json",
    "https://docs.ozon.ru/api/seller/zh/api.json",
    "https://api-seller.ozon.ru/openapi.json",
    "https://api-seller.ozon.ru/swagger.json",
    "https://docs.ozon.ru/assets/seller-api.json",
    "https://docs.ozon.ru/api/seller/zh/spec.json",
    "https://docs.ozon.ru/api/seller/zh/spec.yaml",
]

# Also try fetching the main HTML to find the spec URL embedded in it
MAIN_URLS = [
    "https://docs.ozon.ru/api/seller/zh/",
    "https://docs.ozon.ru/api/seller/",
]


def fetch(client: httpx.Client, url: str, timeout: int = 20) -> httpx.Response | None:
    try:
        r = client.get(url, timeout=timeout, follow_redirects=True)
        print(f"  GET {url} → {r.status_code} ({len(r.content)} bytes)")
        return r
    except Exception as e:
        print(f"  GET {url} → ERROR: {e}")
        return None


def find_spec_url_in_html(html: str, base: str) -> str | None:
    """Look for the OpenAPI spec URL embedded in Redoc HTML."""
    patterns = [
        r'spec-url=["\']([^"\']+)["\']',
        r'"specUrl"\s*:\s*"([^"]+)"',
        r"'specUrl'\s*:\s*'([^']+)'",
        r'src=["\']([^"\']*(?:swagger|openapi|spec|api)[^"\']*\.(?:json|yaml))["\']',
        r'href=["\']([^"\']*(?:swagger|openapi|spec|api)[^"\']*\.(?:json|yaml))["\']',
        r'url:\s*["\']([^"\']+(?:swagger|openapi|spec|api)[^"\']*)["\']',
    ]
    for pat in patterns:
        m = re.search(pat, html, re.IGNORECASE)
        if m:
            url = m.group(1)
            if url.startswith("/"):
                from urllib.parse import urlparse
                p = urlparse(base)
                url = f"{p.scheme}://{p.netloc}{url}"
            return url
    return None


def spec_to_markdown(spec: dict, tag: str, title: str) -> str:
    """Convert OpenAPI spec section for a tag into markdown."""
    lines = [f"# {title}\n"]

    info = spec.get("info", {})
    lines.append(f"**Base URL**: `{spec.get('servers', [{}])[0].get('url', 'https://api-seller.ozon.ru')}`  ")
    lines.append(f"**版本**: {info.get('version', 'N/A')}  \n")
    lines.append("---\n")

    paths = spec.get("paths", {})
    schemas = spec.get("components", {}).get("schemas", spec.get("definitions", {}))

    # Group endpoints by tag
    tag_endpoints = []
    for path, path_item in paths.items():
        for method, op in path_item.items():
            if method.upper() not in ("GET", "POST", "PUT", "PATCH", "DELETE"):
                continue
            op_tags = [t.lower() for t in op.get("tags", [])]
            if tag.lower() in " ".join(op_tags) or not tag:
                tag_endpoints.append((method.upper(), path, op))

    if tag_endpoints:
        lines.append("## 接口列表\n")
        lines.append("| 方法 | 路径 | 说明 |")
        lines.append("|------|------|------|")
        for method, path, op in tag_endpoints:
            summary = op.get("summary", op.get("operationId", ""))
            lines.append(f"| {method} | `{path}` | {summary} |")
        lines.append("")

        # Detail for each endpoint
        for method, path, op in tag_endpoints:
            summary = op.get("summary", op.get("operationId", path))
            lines.append(f"\n### {method} `{path}`")
            lines.append(f"**{summary}**\n")
            if op.get("description"):
                lines.append(op["description"] + "\n")

            # Parameters
            params = op.get("parameters", [])
            if params:
                lines.append("**参数**:\n")
                lines.append("| 名称 | 位置 | 类型 | 必填 | 说明 |")
                lines.append("|------|------|------|------|------|")
                for p in params:
                    schema = p.get("schema", {})
                    ptype = schema.get("type", p.get("type", ""))
                    required = "✓" if p.get("required") else ""
                    lines.append(f"| `{p.get('name','')}` | {p.get('in','')} | {ptype} | {required} | {p.get('description','')} |")
                lines.append("")

            # Request body
            body = op.get("requestBody", {})
            if body:
                content = body.get("content", {})
                for ct, ct_val in content.items():
                    schema = ct_val.get("schema", {})
                    ref = schema.get("$ref", "")
                    schema_name = ref.split("/")[-1] if ref else ""
                    lines.append(f"**请求体** (`{ct}`): `{schema_name or json.dumps(schema, ensure_ascii=False)[:200]}`\n")

            # Responses
            responses = op.get("responses", {})
            if responses:
                lines.append("**响应**:\n")
                for code, resp in responses.items():
                    desc = resp.get("description", "")
                    lines.append(f"- `{code}`: {desc}")
                lines.append("")

    return "\n".join(lines)


def full_spec_to_markdowns(spec: dict) -> None:
    """Convert full OpenAPI spec into per-tag markdown files."""
    tags_meta = {t["name"]: t.get("description", "") for t in spec.get("tags", [])}
    paths = spec.get("paths", {})

    # Group by tag
    tag_paths: dict[str, list] = {}
    for path, path_item in paths.items():
        for method, op in path_item.items():
            if method.upper() not in ("GET", "POST", "PUT", "PATCH", "DELETE"):
                continue
            for tag in op.get("tags", ["other"]):
                tag_paths.setdefault(tag, []).append((method.upper(), path, op))

    info = spec.get("info", {})
    servers = spec.get("servers", [{}])
    base_url = servers[0].get("url", "https://api-seller.ozon.ru") if servers else "https://api-seller.ozon.ru"

    # Tag → file mapping (ordered)
    TAG_ORDER = [
        ("ProductAPI",       "01_products",          "商品管理 API"),
        ("PriceAPI",         "02_prices",             "价格与折扣 API"),
        ("WarehouseAPI",     "03_stocks_warehouses",  "库存与仓库 API"),
        ("OrderAPI",         "04_orders_fbs",         "FBS 订单 API"),
        ("FBOOrderAPI",      "05_orders_fbo",         "FBO 订单 API"),
        ("ReturnsAPI",       "06_returns",            "退货 API"),
        ("FinanceAPI",       "07_finance",            "财务 API"),
        ("AnalyticsAPI",     "08_analytics",          "数据分析 API"),
        ("DiscountsAPI",     "09_promotions",         "促销活动 API"),
        ("FeedbackAPI",      "10_reviews",            "评价与问答 API"),
        ("ChatAPI",          "11_chats",              "聊天 API"),
        ("ReportAPI",        "12_reports",            "报表 API"),
    ]

    written = set()
    for i, (tag, slug, title) in enumerate(TAG_ORDER):
        endpoints = tag_paths.get(tag, [])
        lines = [f"# {title}\n"]
        lines.append(f"**Base URL**: `{base_url}`  ")
        lines.append(f"**版本**: {info.get('version', 'N/A')}  \n")
        if tags_meta.get(tag):
            lines.append(tags_meta[tag] + "\n")
        lines.append("---\n")

        if endpoints:
            lines.append("## 接口列表\n")
            lines.append("| 方法 | 路径 | 说明 |")
            lines.append("|------|------|------|")
            for method, path, op in endpoints:
                summary = op.get("summary", op.get("operationId", ""))
                lines.append(f"| {method} | `{path}` | {summary} |")
            lines.append("")

            for method, path, op in endpoints:
                summary = op.get("summary", op.get("operationId", path))
                op_id = op.get("operationId", "")
                lines.append(f"\n### {method} `{path}`")
                if op_id:
                    lines.append(f"**operationId**: `{op_id}`  ")
                lines.append(f"**{summary}**\n")
                if op.get("description"):
                    lines.append(op["description"].strip() + "\n")

                params = op.get("parameters", [])
                if params:
                    lines.append("**Query/Path 参数**:\n")
                    lines.append("| 名称 | 位置 | 类型 | 必填 | 说明 |")
                    lines.append("|------|------|------|------|------|")
                    for p in params:
                        s = p.get("schema", {})
                        ptype = s.get("type", p.get("type", ""))
                        req = "✓" if p.get("required") else ""
                        lines.append(f"| `{p.get('name','')}` | {p.get('in','')} | {ptype} | {req} | {p.get('description','')} |")
                    lines.append("")

                body = op.get("requestBody", {})
                if body:
                    for ct, ct_val in body.get("content", {}).items():
                        s = ct_val.get("schema", {})
                        ref = s.get("$ref", "")
                        sname = ref.split("/")[-1] if ref else json.dumps(s, ensure_ascii=False)[:120]
                        lines.append(f"**请求体** (`{ct}`): `{sname}`\n")

                for code, resp in op.get("responses", {}).items():
                    lines.append(f"**响应 {code}**: {resp.get('description', '')}")
                lines.append("")
        else:
            lines.append("_（本版本 spec 中未找到对应接口，请参考官方文档）_\n")

        md_path = MARKDOWNS_DIR / f"{slug}.md"
        md_path.write_text("\n".join(lines), encoding="utf-8")
        print(f"  → {md_path.name} ({len(endpoints)} endpoints)")
        written.add(tag)

    # Catch-all for tags not in TAG_ORDER
    for tag, endpoints in tag_paths.items():
        if tag not in written:
            slug = re.sub(r"[^a-z0-9]+", "_", tag.lower()).strip("_")
            lines = [f"# {tag}\n", "---\n"]
            for method, path, op in endpoints:
                summary = op.get("summary", "")
                lines.append(f"- {method} `{path}` — {summary}")
            md_path = MARKDOWNS_DIR / f"zz_{slug}.md"
            md_path.write_text("\n".join(lines), encoding="utf-8")
            print(f"  → {md_path.name} ({len(endpoints)} endpoints) [extra]")


def main():
    with httpx.Client(headers=HEADERS, timeout=30, follow_redirects=True) as client:

        spec = None

        # ── 1. Try candidate spec URLs directly ──────────────────────────────
        print("\n=== Trying direct spec URLs ===")
        for url in SPEC_CANDIDATES:
            r = fetch(client, url)
            if r and r.status_code == 200:
                ct = r.headers.get("content-type", "")
                if "json" in ct or "yaml" in ct or r.content[:1] in (b"{", b"["):
                    try:
                        spec = r.json()
                        print(f"  ✓ Got spec from {url}")
                        (OUT_DIR / "raw_spec.json").write_bytes(r.content)
                        break
                    except Exception:
                        pass
            time.sleep(0.3)

        # ── 2. Parse main HTML to find embedded spec URL ─────────────────────
        if not spec:
            print("\n=== Parsing HTML for spec URL ===")
            for main_url in MAIN_URLS:
                r = fetch(client, main_url)
                if r and r.status_code == 200:
                    html = r.text
                    (OUT_DIR / "raw_main.html").write_text(html, encoding="utf-8")
                    spec_url = find_spec_url_in_html(html, main_url)
                    if spec_url:
                        print(f"  Found spec URL in HTML: {spec_url}")
                        r2 = fetch(client, spec_url)
                        if r2 and r2.status_code == 200:
                            try:
                                spec = r2.json()
                                (OUT_DIR / "raw_spec.json").write_bytes(r2.content)
                                print("  ✓ Spec fetched")
                                break
                            except Exception as e:
                                print(f"  Failed to parse spec: {e}")
                    else:
                        print(f"  No spec URL found in HTML ({len(html)} chars)")
                        # Print first 500 chars for debugging
                        print(f"  HTML preview: {html[:500]}")
                time.sleep(0.5)

        # ── 3. Generate markdowns ────────────────────────────────────────────
        if spec:
            print("\n=== Generating markdowns ===")
            info = spec.get("info", {})
            print(f"  API: {info.get('title')} v{info.get('version')}")
            paths_count = len(spec.get("paths", {}))
            tags_count = len(spec.get("tags", []))
            print(f"  {paths_count} paths, {tags_count} tags")
            full_spec_to_markdowns(spec)
            print("\nDone.")
        else:
            print("\n✗ Could not find OpenAPI spec. Check raw_main.html for clues.")
            sys.exit(1)


if __name__ == "__main__":
    main()
