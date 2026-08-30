#!/usr/bin/env python3

import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


DEFAULT_BASE_URL = "http://eshop.evexport.cn"
MARKETING_CONTEXT_PATH = "/ai/v2/skus/marketing_context"

# Legacy full_context rows are retained only as an audit fallback.  These
# allowlists keep accidental legacy responses useful for analysis without
# carrying order identifiers, sync metadata, or buyer details into Markdown.
LEGACY_ORDER_FIELDS = (
    "platform",
    "store_id",
    "store_name",
    "order_status",
    "ordered_at",
    "fulfillment_type",
    "fulfillment_status",
    "warehouse_name",
    "delivery_method_name",
    "shipped_at",
    "delivered_at",
    "sku_code",
    "platform_sku_id",
    "quantity",
    "currency_code",
    "unit_price",
    "discount_amount",
    "commission_amount",
    "payout",
)

LEGACY_SUPPLY_FIELDS = (
    "platform",
    "store_id",
    "store_name",
    "status",
    "platform_item_id",
    "sku_code",
    "product_name",
    "quantity",
    "accepted_quantity",
    "remaining_quantity",
    "warehouse_name",
    "actual_warehouse_name",
    "transit_warehouse_name",
    "packaging",
    "pallet",
    "ready_for_sale_quantity",
    "unloading_quantity",
)

LEGACY_CONTEXT_FILES = (
    "base.md",
    "weekly_profit_per_week.md",
    "sales_funnel_per_week.md",
    "advertise_per_week.md",
    "search_terms_per_week.md",
    "ec_orders_full_period.md",
    "supply_orders_full_period.md",
    "operation_actions_full_period.md",
    "current_inventory_info.md",
    "history_inventory_info.md",
)


def parse_args():
    parser = argparse.ArgumentParser(description="Fetch and cache Yuanlong SKU context as Markdown")
    parser.add_argument("sku_code")
    parser.add_argument("--period-from")
    parser.add_argument("--period-to")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--base-url", default=os.environ.get("YUANLONG_API_BASE_URL", DEFAULT_BASE_URL))
    args = parser.parse_args()

    if bool(args.period_from) != bool(args.period_to):
        parser.error("--period-from and --period-to must be supplied together")
    return args


def safe_path_part(value):
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "_", value.strip().upper())
    if not normalized or normalized in {".", ".."}:
        raise ValueError("sku_code cannot be used as a local path")
    return normalized


def fetch_json(args, api_key):
    query = {"sku_code": args.sku_code}
    if args.period_from:
        query.update(period_from=args.period_from, period_to=args.period_to)
    url = f"{args.base_url.rstrip('/')}{MARKETING_CONTEXT_PATH}?{urllib.parse.urlencode(query)}"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response), url
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"API returned HTTP {error.code}: {body}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"API request failed: {error.reason}") from error


def scalar(value):
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    return str(value)


def table_cell(value):
    return scalar(value).replace("\\", "\\\\").replace("|", "\\|").replace("\r\n", "<br>").replace("\n", "<br>")


def flat_dict_list(value):
    return all(
        isinstance(item, dict) and all(not isinstance(child, (dict, list)) for child in item.values())
        for item in value
    )


def render_table(value):
    if flat_dict_list(value):
        columns = list(dict.fromkeys(key for item in value for key in item))
        lines = [
            f"| {' | '.join(columns)} |",
            f"| {' | '.join(['---'] * len(columns))} |",
        ]
        lines.extend(
            f"| {' | '.join(table_cell(item.get(column)) for column in columns)} |"
            for item in value
        )
        return lines

    if all(not isinstance(item, (dict, list)) for item in value):
        return ["| value |", "| --- |", *(f"| {table_cell(item)} |" for item in value)]

    return None


def flatten_dict(value, prefix=""):
    flattened = {}
    for key, child in value.items():
        column = f"{prefix}.{key}" if prefix else key
        if isinstance(child, dict):
            flattened.update(flatten_dict(child, column))
        elif isinstance(child, list):
            flattened[column] = json.dumps(child, ensure_ascii=False, separators=(",", ":"))
        else:
            flattened[column] = child
    return flattened


def render_history_inventory(value):
    if not isinstance(value, list) or not value:
        return render_markdown(value)

    rows = []
    for snapshot in value:
        if not isinstance(snapshot, dict):
            return render_markdown(value)
        content = snapshot.get("content")
        overview = content.get("overview") if isinstance(content, dict) else None
        row = {"snapshot_date": snapshot.get("snapshot_date")}
        if isinstance(overview, dict):
            row.update(flatten_dict(overview))
        rows.append(row)
    return render_table(rows)


def render_markdown(value, level=2):
    lines = []
    heading = "#" * min(level, 6)

    if isinstance(value, dict):
        if not value:
            return ["_Empty object._"]
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                lines.extend([f"{heading} {key}", ""])
                lines.extend(render_markdown(child, level + 1))
                lines.append("")
            else:
                lines.append(f"- **{key}:** {scalar(child)}")
        return lines

    if isinstance(value, list):
        if not value:
            return ["_Empty list._"]
        table = render_table(value)
        if table:
            return table
        for index, child in enumerate(value, start=1):
            if isinstance(child, (dict, list)):
                lines.extend([f"{heading} Item {index}", ""])
                lines.extend(render_markdown(child, level + 1))
                lines.append("")
            else:
                lines.append(f"- {scalar(child)}")
        return lines

    return [scalar(value)]


def compact_rows(value, fields):
    if not isinstance(value, list):
        return value

    return [
        {field: row[field] for field in fields if field in row}
        if isinstance(row, dict)
        else row
        for row in value
    ]


def compact_legacy_context(context):
    """Keep a legacy response readable if an old endpoint response is supplied."""
    compacted = dict(context)
    if "ec_orders_full_period" in compacted:
        compacted["ec_orders_full_period"] = compact_rows(
            compacted["ec_orders_full_period"], LEGACY_ORDER_FIELDS
        )
    if "supply_orders_full_period" in compacted:
        compacted["supply_orders_full_period"] = compact_rows(
            compacted["supply_orders_full_period"], LEGACY_SUPPLY_FIELDS
        )
    return compacted


def response_context(data):
    """Accept both the compact marketing response and the legacy envelope."""
    context = data.get("context")
    if isinstance(context, dict):
        return compact_legacy_context(context), data.get("sku_code")

    context = {
        key: value
        for key, value in data.items()
        if key not in {"schema_version", "period", "sku_code"}
    }
    sku = data.get("sku") if isinstance(data.get("sku"), dict) else {}
    return context, sku.get("sku_code")


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary_path = Path(handle.name)
    os.replace(temporary_path, path)


def cache_is_current(metadata_path):
    try:
        return MARKETING_CONTEXT_PATH in metadata_path.read_text(encoding="utf-8")
    except OSError:
        return False


def write_context(output_dir, payload, source_url):
    data = payload.get("data")
    if not isinstance(data, dict):
        raise RuntimeError("API response does not contain data")

    context, context_sku_code = response_context(data)
    if not context:
        raise RuntimeError("API response does not contain a supported context")

    for key, value in context.items():
        rendered = render_history_inventory(value) if key == "history_inventory_info" else render_markdown(value)
        body = [f"# {key}", "", *rendered, ""]
        atomic_write(output_dir / f"{safe_path_part(key).lower()}.md", "\n".join(body).rstrip() + "\n")

    # A refreshed marketing response supersedes files produced by the old
    # full_context endpoint. Remove only these known generated artifacts so a
    # stale, high-volume order file cannot be picked up accidentally.
    if MARKETING_CONTEXT_PATH in source_url:
        for filename in LEGACY_CONTEXT_FILES:
            (output_dir / filename).unlink(missing_ok=True)

    fetched_at = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    period = data.get("period") or {}
    metadata = "\n".join(
        [
            "# SKU context metadata",
            "",
            f"- **sku_code:** {data.get('sku_code') or context_sku_code or ''}",
            f"- **period_from:** {period.get('from', '')}",
            f"- **period_to:** {period.get('to', '')}",
            f"- **endpoint:** {MARKETING_CONTEXT_PATH if MARKETING_CONTEXT_PATH in source_url else 'legacy'}",
            f"- **fetched_at:** {fetched_at}",
            f"- **source:** {source_url}",
            "",
        ]
    )
    atomic_write(output_dir / "_metadata.md", metadata)


def main():
    args = parse_args()
    try:
        sku_path = safe_path_part(args.sku_code)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    today = dt.datetime.now().astimezone().date().isoformat()
    output_dir = Path.cwd() / "skus" / sku_path / "context_data" / today
    metadata_path = output_dir / "_metadata.md"
    if metadata_path.exists() and not args.refresh and cache_is_current(metadata_path):
        print(f"Using today's cached context: {output_dir}")
        return 0

    api_key = os.environ.get("YUANLONG_API_KEY", "").strip()
    if not api_key:
        print("YUANLONG_API_KEY is required", file=sys.stderr)
        return 2

    try:
        payload, source_url = fetch_json(args, api_key)
        write_context(output_dir, payload, source_url)
    except (RuntimeError, OSError, ValueError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        return 1

    print(f"Wrote SKU context: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
