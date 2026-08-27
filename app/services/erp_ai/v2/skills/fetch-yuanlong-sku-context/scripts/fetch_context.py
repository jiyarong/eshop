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
    url = f"{args.base_url.rstrip('/')}/ai/v2/skus/full_context?{urllib.parse.urlencode(query)}"
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
        for index, child in enumerate(value, start=1):
            if isinstance(child, (dict, list)):
                lines.extend([f"{heading} Item {index}", ""])
                lines.extend(render_markdown(child, level + 1))
                lines.append("")
            else:
                lines.append(f"- {scalar(child)}")
        return lines

    return [scalar(value)]


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(content)
        temporary_path = Path(handle.name)
    os.replace(temporary_path, path)


def write_context(output_dir, payload, source_url):
    data = payload.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("context"), dict):
        raise RuntimeError("API response does not contain data.context")

    for key, value in data["context"].items():
        body = [f"# {key}", "", *render_markdown(value), ""]
        atomic_write(output_dir / f"{safe_path_part(key).lower()}.md", "\n".join(body).rstrip() + "\n")

    fetched_at = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    period = data.get("period") or {}
    metadata = "\n".join(
        [
            "# SKU context metadata",
            "",
            f"- **sku_code:** {data.get('sku_code', '')}",
            f"- **period_from:** {period.get('from', '')}",
            f"- **period_to:** {period.get('to', '')}",
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
    output_dir = Path.cwd() / "skus" / sku_path / today
    metadata_path = output_dir / "_metadata.md"
    if metadata_path.exists() and not args.refresh:
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
