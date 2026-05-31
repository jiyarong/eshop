"""
Generate per-section markdown docs from raw_spec.json (Ozon Seller API OpenAPI spec).
"""
import json
import re
from pathlib import Path

OUT_DIR = Path(__file__).parent
MARKDOWNS_DIR = OUT_DIR / "markdowns"
MARKDOWNS_DIR.mkdir(exist_ok=True)

spec = json.loads((OUT_DIR / "raw_spec.json").read_bytes())

info = spec.get("info", {})
servers = spec.get("servers", [{"url": "https://api-seller.ozon.ru"}])
BASE_URL = servers[0]["url"] if servers else "https://api-seller.ozon.ru"
tags_meta = {t["name"]: t.get("description", "") for t in spec.get("tags", [])}

# ── Group paths by tag ──────────────────────────────────────────────────────
tag_ops: dict[str, list[tuple]] = {}
for path, path_item in spec.get("paths", {}).items():
    for method, op in path_item.items():
        if method.upper() not in ("GET", "POST", "PUT", "PATCH", "DELETE"):
            continue
        for tag in op.get("tags", ["other"]):
            tag_ops.setdefault(tag, []).append((method.upper(), path, op))

# ── Tag groupings → markdown files ─────────────────────────────────────────
# (file_slug, zh_title, [tags_to_include])
SECTIONS = [
    ("01_overview",       "概览与认证",
     ["Introduction", "Getting started", "Auth", "OAuth-token", "Environment",
      "Process", "APIkey", "SellerInfo", "SellerRating", "AccessTokenAPI"]),

    ("02_products",       "商品管理 API",
     ["CategoryAPI", "ProductAPI", "BarcodeAPI", "BrandAPI", "CertificationAPI"]),

    ("03_prices_stocks",  "价格、折扣与库存 API",
     ["Prices&StocksAPI", "PricingStrategyAPI"]),

    ("04_warehouses",     "仓库管理 API",
     ["WarehouseAPI", "FBSWarehouseSetup", "PolygonAPI"]),

    ("05_orders_fbs",     "FBS 订单 API（卖家仓发货）",
     ["FBS", "FBS&rFBSMarks", "DeliveryFBS", "DeliveryrFBS", "Pass",
      "OrderAPI", "CancelReasonAPI"]),

    ("06_orders_fbo",     "FBO 订单 API（Ozon 仓发货）",
     ["FBO", "FBO delivery", "FboSupplyRequest", "FboPostingAPI"]),

    ("07_orders_fbp",     "FBP/DBS 订单 API（快递上门自提）",
     ["DeliveryFBPDraft", "DraftDirectFBP", "DraftDropOffFBP", "DraftPickupFBP",
      "OrderDirectFBP", "OrderDropOffFBP", "OrderPickupFBP", "DeliveryFBP"]),

    ("08_returns",        "退货与取消 API",
     ["ReturnsAPI", "ReturnAPI", "RFBSReturnsAPI", "CancellationAPI"]),

    ("09_communication",  "客户沟通 API（聊天、评价、问答）",
     ["ChatAPI", "ReviewAPI", "Questions&Answers"]),

    ("10_promotions",     "促销活动 API",
     ["Promos", "SellerActions", "Premium"]),

    ("11_analytics",      "数据分析 API",
     ["AnalyticsAPI"]),

    ("12_reports",        "报表 API",
     ["ReportAPI", "SupplierAPI"]),

    ("13_finance",        "财务 API",
     ["FinanceAPI", "Receipt"]),

    ("14_logistics",      "物流与配送 API",
     ["OzonLogistics", "DeliveryAPI"]),

    ("15_other",          "其他 API（数字商品、通知推送、Beta）",
     ["Digital", "News", "BetaIntro", "BetaMethod", "Quants",
      "push_intro", "push_start", "push_resending", "push_types",
      "service_response", "Errors"]),
]


def resolve_ref(ref: str, spec: dict) -> dict:
    """Follow a $ref string within the spec."""
    parts = ref.lstrip("#/").split("/")
    node = spec
    for p in parts:
        node = node.get(p, {})
    return node


def schema_summary(schema: dict, spec: dict, depth: int = 0) -> str:
    """Recursively summarize a JSON schema as a short string."""
    if not schema or depth > 3:
        return ""
    ref = schema.get("$ref")
    if ref:
        name = ref.split("/")[-1]
        return f"`{name}`"
    stype = schema.get("type", "")
    if stype == "array":
        items = schema.get("items", {})
        return f"array[{schema_summary(items, spec, depth+1)}]"
    if stype == "object" or schema.get("properties"):
        props = schema.get("properties", {})
        if props:
            pairs = [f"{k}: {schema_summary(v, spec, depth+1)}" for k, v in list(props.items())[:5]]
            suffix = ", ..." if len(props) > 5 else ""
            return "{" + ", ".join(pairs) + suffix + "}"
        return "object"
    return stype or "any"


def render_schema_table(schema: dict, spec: dict, required: list = None) -> list[str]:
    """Render object schema properties as a markdown table."""
    ref = schema.get("$ref")
    if ref:
        schema = resolve_ref(ref, spec)
    props = schema.get("properties", {})
    if not props:
        return []
    required = required or schema.get("required", [])
    lines = ["| 字段 | 类型 | 必填 | 说明 |", "|------|------|------|------|"]
    for name, prop in list(props.items())[:40]:
        ref2 = prop.get("$ref")
        if ref2:
            ptype = f"`{ref2.split('/')[-1]}`"
        else:
            ptype = prop.get("type", "any")
            if ptype == "array":
                items = prop.get("items", {})
                inner = items.get("$ref", "").split("/")[-1] or items.get("type", "any")
                ptype = f"array[{inner}]"
        req = "✓" if name in required else ""
        desc = prop.get("description", "").replace("\n", " ")[:100]
        lines.append(f"| `{name}` | {ptype} | {req} | {desc} |")
    if len(props) > 40:
        lines.append(f"| _(+{len(props)-40} more fields)_ | | | |")
    return lines


def render_endpoint(method: str, path: str, op: dict, spec: dict) -> list[str]:
    lines = []
    summary = op.get("summary", op.get("operationId", path))
    op_id = op.get("operationId", "")
    lines.append(f"\n### {method} `{path}`")
    lines.append(f"**{summary}**  ")
    if op_id:
        lines.append(f"operationId: `{op_id}`  ")
    desc = (op.get("description") or "").strip()
    if desc:
        lines.append("")
        lines.append(desc[:600])
    lines.append("")

    # Path/Query params
    params = op.get("parameters", [])
    if params:
        lines.append("**参数**:\n")
        lines.append("| 名称 | 位置 | 类型 | 必填 | 说明 |")
        lines.append("|------|------|------|------|------|")
        for p in params:
            if p.get("$ref"):
                p = resolve_ref(p["$ref"], spec)
            s = p.get("schema", {})
            ptype = s.get("type", p.get("type", ""))
            if s.get("$ref"):
                ptype = f"`{s['$ref'].split('/')[-1]}`"
            req = "✓" if p.get("required") else ""
            desc = p.get("description", "").replace("\n", " ")[:80]
            lines.append(f"| `{p.get('name','')}` | {p.get('in','')} | {ptype} | {req} | {desc} |")
        lines.append("")

    # Request body
    body = op.get("requestBody", {})
    if body:
        for ct, ct_val in body.get("content", {}).items():
            schema = ct_val.get("schema", {})
            if schema.get("$ref"):
                schema = resolve_ref(schema["$ref"], spec)
            lines.append(f"**请求体** (`{ct}`):\n")
            tbl = render_schema_table(schema, spec)
            if tbl:
                lines.extend(tbl)
                lines.append("")
            else:
                lines.append(f"```json\n{json.dumps(schema, ensure_ascii=False)[:300]}\n```\n")

    # Responses
    responses = op.get("responses", {})
    if responses:
        for code, resp in list(responses.items())[:3]:
            if resp.get("$ref"):
                resp = resolve_ref(resp["$ref"], spec)
            rdesc = resp.get("description", "")
            lines.append(f"**响应 {code}**: {rdesc}")
            content = resp.get("content", {})
            for ct, ct_val in content.items():
                schema = ct_val.get("schema", {})
                tbl = render_schema_table(schema, spec)
                if tbl:
                    lines.extend(tbl)
                break
        lines.append("")

    return lines


def render_section(slug: str, title: str, tags: list[str]) -> int:
    lines = [f"# {title}\n"]
    lines.append(f"**Base URL**: `{BASE_URL}`  ")
    lines.append(f"**版本**: {info.get('version', 'N/A')}  \n")

    # Section description from tags_meta
    for tag in tags:
        d = tags_meta.get(tag, "")
        if d:
            lines.append(d.strip()[:400])
            lines.append("")
            break

    lines.append("---\n")

    # Collect all endpoints for this section
    all_eps = []
    for tag in tags:
        for ep in tag_ops.get(tag, []):
            all_eps.append(ep)

    if not all_eps:
        lines.append("_（本节在 spec 中无接口，仅包含概念性说明）_\n")
        (MARKDOWNS_DIR / f"{slug}.md").write_text("\n".join(lines), encoding="utf-8")
        return 0

    # Summary table
    lines.append("## 接口列表\n")
    lines.append("| 方法 | 路径 | 说明 |")
    lines.append("|------|------|------|")
    for method, path, op in all_eps:
        summary = op.get("summary", op.get("operationId", ""))
        lines.append(f"| {method} | `{path}` | {summary} |")
    lines.append("")

    # Detailed blocks
    lines.append("---\n")
    lines.append("## 接口详情\n")
    for method, path, op in all_eps:
        lines.extend(render_endpoint(method, path, op, spec))
        lines.append("---")

    out_path = MARKDOWNS_DIR / f"{slug}.md"
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return len(all_eps)


def main():
    total = 0
    print(f"\nOzon Seller API — {info.get('title')} v{info.get('version')}")
    print(f"{len(spec.get('paths', {}))} paths, {len(spec.get('tags', []))} tags")
    print(f"\nGenerating {len(SECTIONS)} markdown files...\n")

    used_tags = set()
    for slug, title, tags in SECTIONS:
        n = render_section(slug, title, tags)
        total += n
        used_tags.update(tags)
        print(f"  {slug}.md — {n} endpoints")

    # Check coverage
    missed = {t for t in tag_ops if t not in used_tags and tag_ops[t]}
    if missed:
        print(f"\nWarning: {len(missed)} tags not covered: {missed}")

    print(f"\nTotal: {total} endpoints across {len(SECTIONS)} files")
    print(f"Output: {MARKDOWNS_DIR}")


if __name__ == "__main__":
    main()
