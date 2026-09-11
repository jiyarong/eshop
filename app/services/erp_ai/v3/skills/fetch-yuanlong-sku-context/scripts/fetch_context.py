#!/usr/bin/env python3

import argparse
import datetime as dt
import os
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


DEFAULT_BASE_URL = "http://eshop.evexport.cn"
MAX_WEEKS = 12
DEFAULT_WEEKS = 4
DEFAULT_MAX_WORKERS = 6

SECTIONS = (
    {
        "filename": "base.md",
        "path": "/ai/v3/sku/base_context.md",
        "key": "base",
    },
    {
        "filename": "sales_funnel.md",
        "path": "/ai/v3/sku/sales_funnel_context.md",
        "key": "sales_funnel",
    },
    {
        "filename": "profit.md",
        "path": "/ai/v3/sku/profit_context.md",
        "key": "profit",
    },
    {
        "filename": "inventory.md",
        "path": "/ai/v3/sku/inventory_context.md",
        "key": "inventory",
    },
    {
        "filename": "lifecycle.md",
        "path": "/ai/v3/sku/lifecycle_context.md",
        "key": "lifecycle",
    },
    {
        "filename": "advertise_per_week.md",
        "path": "/ai/v3/sku/advertising_context.md",
        "key": "advertise_per_week",
    },
    {
        "filename": "ec_orders_full_period.md",
        "path": "/ai/v3/sku/orders_context.md",
        "key": "ec_orders_full_period",
    },
    {
        "filename": "supply_orders_full_period.md",
        "path": "/ai/v3/sku/supply_orders_context.md",
        "key": "supply_orders_full_period",
    },
    {
        "filename": "operation_actions_full_period.md",
        "path": "/ai/v3/sku/operation_actions_context.md",
        "key": "operation_actions_full_period",
    },
    {
        "filename": "warehouse_recommendation.md",
        "path": "/ai/v3/sku/warehouse_recommendation_context.md",
        "key": "warehouse_recommendation",
        "target_days": True,
    },
    {
        "filename": "search_terms_per_week.md",
        "path": "/ai/v3/sku/search_terms_context.md",
        "key": "search_terms_per_week",
    },
)


def parse_args():
    parser = argparse.ArgumentParser(description="Fetch and cache Yuanlong SKU v3 context as Markdown")
    parser.add_argument("sku_code")
    parser.add_argument("--weeks", type=int, choices=range(1, MAX_WEEKS + 1), default=DEFAULT_WEEKS)
    parser.add_argument("--period-from")
    parser.add_argument("--period-to")
    parser.add_argument("--target-days", type=int)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--max-workers", type=int, choices=range(1, len(SECTIONS) + 1), default=DEFAULT_MAX_WORKERS)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--base-url", default=os.environ.get("YUANLONG_API_BASE_URL", DEFAULT_BASE_URL))
    return parser.parse_args()


def safe_path_part(value):
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "_", value.strip().upper())
    if not normalized or normalized in {".", ".."}:
        raise ValueError("sku_code cannot be used as a local path")
    return normalized


def parse_date(value, name):
    try:
        return dt.date.fromisoformat(value)
    except ValueError as error:
        raise ValueError(f"{name} must be YYYY-MM-DD") from error


def requested_period(args):
    if bool(args.period_from) != bool(args.period_to):
        raise ValueError("--period-from and --period-to must be provided together")

    if args.period_from:
        period_from = parse_date(args.period_from, "--period-from")
        period_to = parse_date(args.period_to, "--period-to")
    else:
        today = dt.datetime.now().astimezone().date()
        current_week_start = today - dt.timedelta(days=today.weekday())
        period_to = current_week_start - dt.timedelta(days=1)
        period_from = period_to - dt.timedelta(days=(args.weeks * 7) - 1)

    if period_from.weekday() != 0:
        raise ValueError("period_from must be a Monday")
    if period_to.weekday() != 6:
        raise ValueError("period_to must be a Sunday")
    if period_to < period_from:
        raise ValueError("period_to must not be earlier than period_from")
    if ((period_to - period_from).days + 1) % 7 != 0:
        raise ValueError("period range must contain complete natural weeks")

    return period_from, period_to


def fetch_markdown(section, args, api_key, period_from, period_to):
    query = {
        "sku_code": args.sku_code,
        "period_from": period_from.isoformat(),
        "period_to": period_to.isoformat(),
    }
    if section.get("target_days") and args.target_days is not None:
        query["target_days"] = str(args.target_days)

    url = f"{args.base_url.rstrip('/')}{section['path']}?{urllib.parse.urlencode(query)}"
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "text/markdown",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return section["filename"], body, url
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{section['path']} returned HTTP {error.code}: {body}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"{section['path']} request failed: {error.reason}") from error


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary_path = Path(handle.name)
    os.replace(temporary_path, path)


def cache_is_current(metadata_path, args, period_from, period_to):
    try:
        metadata = metadata_path.read_text(encoding="utf-8")
    except OSError:
        return False

    required_markers = [
        "- **schema_version:** 3",
        f"- **period_from:** {period_from.isoformat()}",
        f"- **period_to:** {period_to.isoformat()}",
        f"- **weeks:** {args.weeks}",
        f"- **target_days:** {args.target_days or ''}",
    ]
    if not all(marker in metadata for marker in required_markers):
        return False

    return all((metadata_path.parent / section["filename"]).exists() for section in SECTIONS)


def fetch_sections(args, api_key, period_from, period_to):
    max_workers = min(args.max_workers, len(SECTIONS))
    results = {}
    source_urls = {}

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(fetch_markdown, section, args, api_key, period_from, period_to): section
            for section in SECTIONS
        }
        for future in as_completed(futures):
            filename, body, url = future.result()
            results[filename] = body
            source_urls[filename] = url

    return results, source_urls


def write_context(output_dir, results, source_urls, args, period_from, period_to):
    for section in SECTIONS:
        filename = section["filename"]
        body = results[filename].rstrip() + "\n"
        atomic_write(output_dir / filename, body)

    fetched_at = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    metadata_lines = [
        "# SKU context metadata",
        "",
        "- **schema_version:** 3",
        f"- **sku_code:** {args.sku_code.strip().upper()}",
        f"- **period_from:** {period_from.isoformat()}",
        f"- **period_to:** {period_to.isoformat()}",
        f"- **weeks:** {args.weeks}",
        f"- **target_days:** {args.target_days or ''}",
        "- **format:** markdown",
        "- **endpoint_strategy:** v3_split_context",
        f"- **fetched_at:** {fetched_at}",
        "",
        "## Files",
        "",
    ]
    for section in SECTIONS:
        filename = section["filename"]
        metadata_lines.append(f"- `{filename}`: `{section['path']}`")

    metadata_lines.extend(["", "## Sources", ""])
    for section in SECTIONS:
        filename = section["filename"]
        metadata_lines.append(f"- `{filename}`: {source_urls[filename]}")

    atomic_write(output_dir / "_metadata.md", "\n".join(metadata_lines).rstrip() + "\n")


def main():
    args = parse_args()
    try:
        sku_path = safe_path_part(args.sku_code)
        period_from, period_to = requested_period(args)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    today = dt.datetime.now().astimezone().date().isoformat()
    output_dir = Path.cwd() / "skus" / sku_path / "context_data" / today
    metadata_path = output_dir / "_metadata.md"
    if metadata_path.exists() and not args.refresh and cache_is_current(metadata_path, args, period_from, period_to):
        print(f"Using today's cached v3 context: {output_dir}")
        return 0

    api_key = os.environ.get("YUANLONG_API_KEY", "").strip()
    if not api_key:
        print("YUANLONG_API_KEY is required", file=sys.stderr)
        return 2

    try:
        results, source_urls = fetch_sections(args, api_key, period_from, period_to)
        write_context(output_dir, results, source_urls, args, period_from, period_to)
    except (RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1

    print(f"Wrote SKU v3 context: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
