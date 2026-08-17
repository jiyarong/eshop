#!/usr/bin/env python3
"""Validate WB FBS archived reports against production order data.

Usage:
    python3 script/verify_wb_fbs_worldchoice.py REPORT_FOLDER ACCOUNT_ID

Examples:
    python3 script/verify_wb_fbs_worldchoice.py \
      ~/Downloads/WB归档报表/МИРОВОЙ\ ВЫБОР 3
    python3 script/verify_wb_fbs_worldchoice.py \
      ~/Downloads/WB归档报表/Такси\ Линк 2

The report is authoritative only for orders that WB has moved into its archive.
Orders in the database for the same month but absent from the report are shown
as informational counts because they may not have reached WB's archive yet.
The command exits non-zero when a report order is missing or misclassified in
raw_wb_orders or the normalized ec_orders tables.
"""

import json
import base64
import re
import subprocess
import sys
import uuid
import zipfile
from collections import Counter
from pathlib import Path

import openpyxl


CONTAINER_CMD = "docker ps --format '{{.Names}}' | grep eshop_manage-web | head -1"
REPORT_XLSX = "report_part_0.xlsx"


def parse_period(filename):
    match = re.search(
        r"(\d{2})\.(\d{2})\.(\d{4})-(\d{2})\.(\d{2})\.(\d{4})",
        filename,
    )
    if not match:
        return None
    day_from, month_from, year_from, day_to, month_to, year_to = map(
        int, match.groups()
    )
    return {
        "month": f"{year_from:04d}-{month_from:02d}",
        "from": f"{year_from:04d}-{month_from:02d}-{day_from:02d}",
        "to": f"{year_to:04d}-{month_to:02d}-{day_to:02d}",
    }


def read_order_ids(zip_path):
    with zipfile.ZipFile(zip_path) as archive:
        if REPORT_XLSX not in archive.namelist():
            raise ValueError(f"{zip_path.name}: missing {REPORT_XLSX}")
        with archive.open(REPORT_XLSX) as report:
            # WB writes an incorrect A1:A1 worksheet dimension. openpyxl's
            # read-only mode trusts it and silently hides all order rows.
            sheet = openpyxl.load_workbook(report, data_only=True).active
            rows = sheet.iter_rows(values_only=True)
            header = next(rows, ())
            if not header or header[0] != "工作編號":
                raise ValueError(f"{zip_path.name}: unexpected header {header!r}")
            return [int(row[0]) for row in rows if row and row[0] is not None]


def load_reports(folder):
    folder = Path(folder).expanduser().resolve()
    if not folder.is_dir():
        raise ValueError(f"report folder does not exist: {folder}")

    reports = []
    seen_months = set()
    for zip_path in sorted(folder.glob("*.zip")):
        period = parse_period(zip_path.name)
        if not period:
            raise ValueError(f"cannot parse report period: {zip_path.name}")
        if period["month"] in seen_months:
            raise ValueError(f"duplicate report month: {period['month']}")
        seen_months.add(period["month"])
        ids = read_order_ids(zip_path)
        duplicates = sorted(order_id for order_id, count in Counter(ids).items() if count > 1)
        reports.append({**period, "file": zip_path.name, "ids": ids, "duplicates": duplicates})
        duplicate_note = f", duplicates={len(duplicates)}" if duplicates else ""
        print(f"  {period['month']}: {len(ids)} archived orders{duplicate_note}", flush=True)

    if not reports:
        raise ValueError(f"no ZIP reports found in {folder}")
    return reports


RAILS_TEMPLATE = r'''
$stdout.sync = true
Rails.logger = Logger.new(IO::NULL)

account_id = ACCOUNT_ID_PLACEHOLDER
reports = REPORTS_JSON_PLACEHOLDER
store = Ec::Store.find_by(platform: "wb", wb_raw_account_id: account_id)
abort("No WB store linked to raw account #{account_id}") unless store

puts "\nStore: #{store.store_name} (store_id=#{store.id}, account_id=#{account_id})"
puts "=" * 94
puts format("%-7s %7s %7s %7s %7s %9s %9s %9s", "month", "report", "raw", "ec", "dup", "raw miss", "ec miss", "DB extra")
puts "-" * 94

failure_count = 0
totals = Hash.new(0)

reports.each do |report|
  report_ids = report.fetch(:ids).map(&:to_i)
  from = Time.find_zone!("Europe/Moscow").parse(report.fetch(:from)).beginning_of_day
  to = Time.find_zone!("Europe/Moscow").parse(report.fetch(:to)).end_of_day

  raw_rows = RawWb::Order
    .where(wb_order_id: report_ids)
    .pluck(:wb_order_id, :account_id, :delivery_type, :created_at)
  valid_raw_ids = raw_rows.filter_map do |wb_order_id, row_account_id, delivery_type, created_at|
    next unless row_account_id == account_id
    next unless delivery_type == "fbs"
    next unless created_at&.between?(from, to)
    wb_order_id.to_i
  end.uniq

  ec_ids = Ec::OrderItem
    .joins(:order, :fulfillment)
    .where(ec_orders: { platform: "wb", store_id: store.id })
    .where(ec_order_fulfillments: { fulfillment_type: "fbs", store_id: store.id })
    .where(external_item_id: report_ids.map(&:to_s))
    .distinct
    .pluck(:external_item_id)
    .map(&:to_i)

  raw_missing = report_ids.uniq - valid_raw_ids
  ec_missing = report_ids.uniq - ec_ids
  db_extra = RawWb::Order
    .where(account_id: account_id, delivery_type: "fbs", created_at: from..to)
    .where.not(wb_order_id: report_ids)
    .count
  duplicates = report.fetch(:duplicates)

  row_failures = raw_missing.size + ec_missing.size + duplicates.size
  failure_count += row_failures
  totals[:report] += report_ids.uniq.size
  totals[:raw] += valid_raw_ids.size
  totals[:ec] += ec_ids.size
  totals[:duplicates] += duplicates.size
  totals[:raw_missing] += raw_missing.size
  totals[:ec_missing] += ec_missing.size
  totals[:db_extra] += db_extra

  puts format(
    "%-7s %7d %7d %7d %7d %9d %9d %9d%s",
    report.fetch(:month), report_ids.uniq.size, valid_raw_ids.size, ec_ids.size,
    duplicates.size, raw_missing.size, ec_missing.size, db_extra,
    row_failures.zero? ? "" : "  NG"
  )
  puts "  raw missing/misclassified IDs: #{raw_missing.first(20).inspect}" if raw_missing.any?
  puts "  ec missing IDs: #{ec_missing.first(20).inspect}" if ec_missing.any?
  puts "  duplicate report IDs: #{duplicates.first(20).inspect}" if duplicates.any?
end

puts "-" * 94
puts format(
  "%-7s %7d %7d %7d %7d %9d %9d %9d",
  "TOTAL", totals[:report], totals[:raw], totals[:ec], totals[:duplicates],
  totals[:raw_missing], totals[:ec_missing], totals[:db_extra]
)
puts "\nDB extra is informational: same-month FBS orders not yet present in WB's archive report."
puts failure_count.zero? ? "RESULT: OK" : "RESULT: NG (#{failure_count} validation failures)"
exit(failure_count.zero? ? 0 : 2)
'''


def build_rails_script(reports, account_id):
    payload = json.dumps(reports, ensure_ascii=False)
    return (
        RAILS_TEMPLATE.replace("ACCOUNT_ID_PLACEHOLDER", str(account_id))
        .replace("REPORTS_JSON_PLACEHOLDER", payload)
    )


def run_on_server(rails_script):
    encoded = base64.b64encode(rails_script.encode("utf-8")).decode("ascii")
    container_path = f"/tmp/verify_wb_fbs_archived_{uuid.uuid4().hex}.rb"
    remote_command = (
        f"container=$({CONTAINER_CMD}); "
        'test -n "$container" && '
        f"printf %s {encoded} | base64 -d | docker exec -i \"$container\" "
        f"sh -c 'cat > {container_path}' && "
        f'docker exec "$container" bin/rails runner {container_path}'
    )
    result = subprocess.run(
        ["ssh", "root@eshop.evexport.cn", remote_command],
        check=False,
    )
    return result.returncode


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1

    try:
        account_id = int(sys.argv[2])
        print(f"Reading reports from {Path(sys.argv[1]).expanduser()}")
        reports = load_reports(sys.argv[1])
        return run_on_server(build_rails_script(reports, account_id))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
